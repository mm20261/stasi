import CoreAudio
import Foundation

// MARK: - Mikrofon-Auswahl (v4)
// Popover-Geräteliste + Auswahl fuer die input-only AUHAL. Das
// System-Standardgeraet selbst bleibt unangetastet.

enum MicrophoneTransport: Equatable, Sendable {
    case builtIn
    case wired
    case bluetooth
    case virtual
    case unknown(UInt32)
}

/// Ein Eintrag der Mikrofon-Liste.
struct MicDevice: Equatable, Identifiable {
    /// Stabile Transport-UID (überlebt Reboots, im Gegensatz zur DeviceID).
    let uid: String
    let name: String
    /// Aktives macOS-Eingabegerät → Label „STANDARD“.
    let isDefault: Bool
    let transport: MicrophoneTransport
    let inputChannels: Int
    let isSupportedForSpeech: Bool
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

    /// Ohne explizite Auswahl werden geeignete eingebaute oder kabelgebundene
    /// Mikrofone vor Bluetooth-Geraeten bevorzugt. Innerhalb dieser Gruppe bleibt
    /// das macOS-Standardgeraet massgeblich.
    static func automaticDefault(from devices: [MicDevice]) -> MicDevice? {
        let supported = devices.filter(\.isSupportedForSpeech)
        let preferredTransports = supported.filter {
            $0.transport == .builtIn || $0.transport == .wired
        }
        if let systemDefault = preferredTransports.first(where: \.isDefault) {
            return systemDefault
        }
        if let builtIn = preferredTransports.first(where: { $0.transport == .builtIn }) {
            return builtIn
        }
        if let wired = preferredTransports.first(where: { $0.transport == .wired }) {
            return wired
        }
        return supported.first(where: \.isDefault) ?? supported.first
    }

    /// Eine explizit gespeicherte, weiterhin geeignete UID gewinnt auch dann,
    /// wenn sie Bluetooth verwendet. Nur fehlende/ungeeignete UIDs fallen auf
    /// die automatische, Bluetooth-meidende Auswahl zurueck.
    static func resolve(preferredUID: String?, devices: [MicDevice]) -> MicDevice? {
        if let preferredUID,
           let preferred = devices.first(where: {
               $0.uid == preferredUID && $0.isSupportedForSpeech
           }) {
            return preferred
        }
        return automaticDefault(from: devices)
    }
}

// MARK: CoreAudio-Erkennung

enum MicrophoneScanner {
    struct RawDevice {
        let deviceID: AudioDeviceID
        let name: String
        let transportUID: String?
        let transport: MicrophoneTransport
        let inputChannels: Int
        let isSupportedForSpeech: Bool
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// UI-fertiger Katalog inklusive echtem Systemstandard-Gerät.
    static func devices() -> [MicDevice] {
        let defaultUID = defaultInputTransportUID()
        return MicrophoneCatalog.catalog(from: scan().map { raw in
            MicDevice(uid: raw.transportUID ?? raw.name,
                      name: raw.name,
                      isDefault: raw.transportUID != nil && raw.transportUID == defaultUID,
                      transport: raw.transport,
                      inputChannels: raw.inputChannels,
                      isSupportedForSpeech: raw.isSupportedForSpeech)
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
                             transport: transportType(id),
                             inputChannels: channels,
                             isSupportedForSpeech: channels > 0)
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

    /// Wunsch-UID oder eine Bluetooth-meidende automatische Auswahl. Eine
    /// explizit gespeicherte geeignete Bluetooth-UID bleibt dabei respektiert.
    static func inputDeviceID(preferredUID: String?) -> AudioDeviceID? {
        let rawDevices = scan()
        let defaultID = defaultInputDeviceID()
        let devices = rawDevices.map { raw in
            MicDevice(uid: raw.transportUID ?? raw.name,
                      name: raw.name,
                      isDefault: raw.deviceID == defaultID,
                      transport: raw.transport,
                      inputChannels: raw.inputChannels,
                      isSupportedForSpeech: raw.isSupportedForSpeech)
        }
        guard let selected = MicrophoneCatalog.resolve(preferredUID: preferredUID,
                                                       devices: devices)
        else { return nil }
        if let preferredUID, selected.uid != preferredUID {
            DebugLog.log("STASI-AUDIO: Wunsch-Mikrofon nicht gefunden oder ungeeignet "
                         + "(\(preferredUID)) – nutze \(selected.name)")
        }
        return rawDevices.first(where: {
            ($0.transportUID ?? $0.name) == selected.uid
        })?.deviceID
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

    private static func transportType(_ id: AudioDeviceID) -> MicrophoneTransport {
        var rawValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rawValue) == noErr else {
            return .unknown(0)
        }
        return microphoneTransport(from: rawValue)
    }

    static func microphoneTransport(from rawValue: UInt32) -> MicrophoneTransport {
        switch rawValue {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeThunderbolt:
            return .wired
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .unknown(rawValue)
        }
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
        let list = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return inputChannelCount(from: list)
    }

    static func inputChannelCount(from audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> Int {
        UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }
}
