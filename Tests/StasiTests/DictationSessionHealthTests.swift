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
