import AVFoundation
import XCTest
@testable import Stasi

final class DictationSessionHealthTests: XCTestCase {
    func testDroppedChunkMarksOverflow() throws {
        let health = DictationSessionHealth()

        health.record(.dropped(try makeChunk()))

        XCTAssertEqual(health.failure, .speechBufferOverflow)
    }

    func testFirstFailureWins() throws {
        let health = DictationSessionHealth()

        health.record(.dropped(try makeChunk()))
        health.record(.terminated)

        XCTAssertEqual(health.failure, .speechBufferOverflow)
    }

    func testRuntimeErrorRemainsObservableAfterEarlierSpeechFailure() throws {
        let health = DictationSessionHealth()

        health.record(.dropped(try makeChunk()))
        health.recordAudioRuntimeFailure(.processingBacklog)

        XCTAssertEqual(health.failure, .speechBufferOverflow)
        XCTAssertEqual(health.audioRuntimeError, .processingBacklog)
    }

    func testFirstOverflowClosesSpeechIngressAndRejectsLaterChunks() async throws {
        let health = DictationSessionHealth()
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        var iterator = stream.makeAsyncIterator()
        let first = try makeChunk()
        let overflow = try makeChunk()
        let late = try makeChunk()

        health.ingest(first, into: continuation)
        health.ingest(overflow, into: continuation)
        health.ingest(late, into: continuation)

        let receivedFirst = await iterator.next()
        let receivedAfterOverflow = await iterator.next()
        XCTAssertNotNil(receivedFirst)
        XCTAssertNil(receivedAfterOverflow)
        XCTAssertEqual(health.failure, .speechBufferOverflow)
    }

    func testDeliberateShutdownIgnoresLateYieldAfterLastBufferedChunk() async throws {
        let health = DictationSessionHealth()
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        var iterator = stream.makeAsyncIterator()

        health.ingest(try makeChunk(), into: continuation)
        health.closeSpeechIngress(continuation)
        health.ingest(try makeChunk(), into: continuation)

        let receivedBuffered = await iterator.next()
        let receivedLate = await iterator.next()
        XCTAssertNotNil(receivedBuffered)
        XCTAssertNil(receivedLate)
        XCTAssertNil(health.failure)
    }

    private func makeChunk() throws -> AudioChunk {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        return AudioChunk(buffer: buffer)
    }
}
