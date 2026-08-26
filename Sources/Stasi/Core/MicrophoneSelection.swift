import CoreAudio
import Foundation

// MARK: - Mikrofon-Auswahl (v4)
// Popover-Geräteliste + Auswahl fuer die input-only AUHAL. Das
// System-Standardgeraet selbst bleibt unangetastet.

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

    /// UI-fertiger Katalog inklusive echtem Systemstandard-Gerät.
    static func devices() -> [MicDevice] {
        let defaultUID = defaultInputTransportUID()
        return MicrophoneCatalog.catalog(from: scan().map { raw in
            MicDevice(uid: raw.transportUID ?? raw.name,
                      name: raw.name,
                      isDefault: raw.transportUID != nil && raw.transportUID == defaultUID)
        })
    }

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
        guard let deviceID = defaultInputDeviceID() else { return nil }
        return transportUID(deviceID)
    }

    /// Aktuelle DeviceID des Systemstandard-Eingangs. Nur gelesen, niemals
    /// geschrieben; die Auswahl wird spaeter ausschliesslich auf der AUHAL gesetzt.
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return nil }
        return deviceID
    }

    // MARK: Aufloesung UID -> DeviceID

    /// UID → aktuelle AudioDeviceID (UIDs sind stabil, IDs nicht).
    static func deviceID(forTransportUID uid: String) -> AudioDeviceID? {
        scan().first(where: { $0.transportUID == uid })?.deviceID
    }

    /// Wunsch-UID oder explizit das aktuelle Default-Input-Geraet. Eine nicht
    /// mehr vorhandene Wunsch-UID faellt kontrolliert auf den Standard zurueck.
    static func inputDeviceID(preferredUID: String?) -> AudioDeviceID? {
        if let preferredUID {
            if let selected = deviceID(forTransportUID: preferredUID) {
                return selected
            }
            DebugLog.log("STASI-AUDIO: Wunsch-Mikrofon nicht gefunden (\(preferredUID)) – nutze Standard")
        }
        return defaultInputDeviceID()
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
