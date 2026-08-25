import AVFoundation
import Foundation

// MARK: - Mikrofon-Auswahl (v4)
// Popover-Geräteliste + Auswahl pro Engine (kAudioOutputUnitProperty_
// CurrentDevice auf dem InputNode) – das System-Standardgerät bleibt unangetastet.

/// Ein Eintrag der Mikrofon-Liste.
struct MicDevice: Equatable, Identifiable {
    /// Stabile Transport-UID (überlebt Reboots, im Gegensatz zur DeviceID).
    let uid: String
    let name: String
    /// Aktives macOS-Eingabegerät → Label „STANDARD“.
    let isDefault: Bool
    var id: String { uid }
}

enum MicrophoneCatalog {
    /// Standardgerät zuerst, Rest alphabetisch; leere Namen raus; UID-Duplette raus.
    static func catalog(from devices: [MicDevice]) -> [MicDevice] {
        sort(dedupe(sanitize(devices)))
    }

    /// Leere Namen/UIDs fliegen raus.
    static func sanitize(_ devices: [MicDevice]) -> [MicDevice] {
        devices.filter { !$0.name.isEmpty && !$0.uid.isEmpty }
    }

    /// Dedup nach UID – erster gewinnt.
    static func dedupe(_ devices: [MicDevice]) -> [MicDevice] {
        var seen = Set<String>()
        return devices.filter { seen.insert($0.uid).inserted }
    }

    /// Standard zuerst, danach alphabetisch.
    static func sort(_ devices: [MicDevice]) -> [MicDevice] {
        devices.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: CoreAudio-Erkennung

enum MicrophoneScanner {
    struct RawDevice {
        let deviceID: AudioDeviceID
        let name: String
        let transportUID: String?
        let inputChannels: Int
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Alle Hardware-Audiogeräte mit Eingangskanälen.
    static func scan() -> [RawDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr
        else { return [] }

        return ids.compactMap { id in
            let channels = inputChannelCount(id)
            guard channels > 0 else { return nil }
            return RawDevice(deviceID: id,
                             name: deviceName(id),
                             transportUID: transportUID(id),
                             inputChannels: channels)
        }
    }

    /// Transport-UID des aktiven macOS-Eingabegeräts (nil = Systemstandard).
    static func defaultInputTransportUID() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return nil }
        return transportUID(deviceID)
    }

    // MARK: Auflösung UID → DeviceID + Anwenden auf die Engine

    /// UID → aktuelle AudioDeviceID (UIDs sind stabil, IDs nicht).
    static func deviceID(forTransportUID uid: String) -> AudioDeviceID? {
        scan().first(where: { $0.transportUID == uid })?.deviceID
    }

    /// Setzt das Gerät auf dem InputNode der Engine (VOR dem Start!).
    /// Liefert false, wenn das Gerät fehlt oder die Property abgelehnt wird –
    /// dann läuft einfach das Standardgerät weiter.
    static func apply(_ uid: String?, to node: AVAudioInputNode) -> Bool {
        guard let uid else { return true } // kein Wunsch → Standard lassen
        guard let deviceID = deviceID(forTransportUID: uid) else {
            DebugLog.log("STASI-AUDIO: Wunsch-Mikrofon nicht gefunden (\(uid)) – nutze Standard")
            return false
        }
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &id) { pointer in
            AudioUnitSetProperty(node.audioUnit!,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioObjectPropertyScopeGlobal,
                                 0,
                                 pointer,
                                 size)
        }
        if status != noErr {
            DebugLog.log("STASI-AUDIO: Mikrofon konnte nicht gesetzt werden (OSStatus \(status)) – nutze Standard")
            return false
        }
        return true
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector,
                                       on id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfString) == noErr,
              let managed = cfString?.takeRetainedValue() else { return nil }
        return managed as String
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        stringProperty(kAudioDevicePropertyDeviceNameCFString, on: id) ?? ""
    }

    private static func transportUID(_ id: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, on: id)
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        let list = buffer.bindMemory(to: AudioBufferList.self, capacity: 1).pointee
        var count = 0
        for i in 0..<Int(list.mNumberBuffers) {
            let buf = withUnsafeBytes(of: list.mBuffers) { raw in
                raw.loadUnaligned(fromByteOffset: i * MemoryLayout<AudioBuffer>.stride,
                                  as: AudioBuffer.self)
            }
            count += Int(buf.mNumberChannels)
        }
        return count
    }
}
