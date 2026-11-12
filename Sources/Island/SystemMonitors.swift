import AppKit
import CoreAudio
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Battery

/// Battery level and charger state, with callbacks for the moments worth an alert.
@MainActor
final class PowerMonitor: ObservableObject {
    enum Event { case pluggedIn, unplugged, low }

    @Published private(set) var percent: Int?
    @Published private(set) var onACPower = false
    var onEvent: ((Event) -> Void)?

    static let lowThreshold = 20
    private var hasRead = false
    private var warnedLow = false

    func start() {
        read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.read() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func read() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }

        var newPercent: Int?
        var newOnAC = onACPower
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            if let current = info[kIOPSCurrentCapacityKey] as? Int,
               let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 {
                newPercent = Int((Double(current) / Double(max) * 100).rounded())
            }
            newOnAC = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }

        let wasOnAC = onACPower
        percent = newPercent
        onACPower = newOnAC

        defer { hasRead = true }
        guard hasRead, let level = newPercent else { return } // no alerts for the state at launch
        if newOnAC != wasOnAC {
            onEvent?(newOnAC ? .pluggedIn : .unplugged)
        }
        if newOnAC || level > Self.lowThreshold {
            warnedLow = false
        } else if !warnedLow {
            warnedLow = true
            onEvent?(.low)
        }
    }
}

// MARK: - Audio output (headphones, AirPods, speakers)

/// Reports when the Mac's sound output switches to another device, e.g. AirPods connecting.
@MainActor
final class AudioOutputMonitor {
    var onChange: ((String) -> Void)?
    private var lastName: String?

    func start() {
        lastName = Self.currentOutputName()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, let name = Self.currentOutputName(), name != self.lastName else { return }
                self.lastName = name
                self.onChange?(name)
            }
        }
    }

    nonisolated static func currentOutputName() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }

        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, $0)
        }
        guard status == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

// MARK: - Keep awake

/// Stops the display (and so the Mac) from sleeping while switched on.
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    private var assertion: IOPMAssertionID = 0

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Island: Keep Awake" as CFString, &assertion)
            isOn = result == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isOn = false
        }
    }

    func toggle() { set(!isOn) }
}
