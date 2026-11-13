import AppKit
import CoreAudio
import Darwin
import TraceCore

/// Finds the apps that are playing sound or using the microphone right now.
///
/// macOS keeps an audio object for every process that talks to the audio
/// system and says whether its output or input is running. Reading that
/// needs no permission and reveals nothing about what is being played or said.
enum AudioMonitor {
    struct Activity: Hashable {
        let bundleID: String
        let appName: String
        let layer: Layer
    }

    private static var owners: [pid_t: (bundleID: String, name: String)?] = [:]

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    /// The app a process belongs to. Helper processes (a browser's renderer,
    /// a chat app's call service) live inside their app's bundle, so the
    /// outermost `.app` in the path is the app the user knows.
    private static func owner(of pid: pid_t) -> (bundleID: String, name: String)? {
        if let cached = owners[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        var found: (bundleID: String, name: String)?
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            // Input methods and system services keep the microphone or the
            // speaker open without it being something the user is doing.
            let skipped = path.contains("/Input Methods/") || path.hasPrefix("/System/Library/")
                || path.hasPrefix("/usr/") || path.hasPrefix("/Library/Apple/")
            if !skipped, let range = path.range(of: ".app/") ?? path.range(of: ".app", options: [.anchored, .backwards]) {
                let bundlePath = String(path[..<range.lowerBound]) + ".app"
                if let bundle = Bundle(path: bundlePath), let id = bundle.bundleIdentifier {
                    let name = FileManager.default.displayName(atPath: bundlePath).replacingOccurrences(of: ".app", with: "")
                    found = (id, name)
                }
            }
        }
        if owners.count > 500 { owners.removeAll() }
        owners[pid] = found
        return found
    }

    /// Call from one queue only.
    static func current() -> Set<Activity> {
        var result: Set<Activity> = []
        for object in processObjects() {
            let output = value(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            let input = value(object, kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1
            guard output || input, let pid = value(object, kAudioProcessPropertyPID, as: pid_t.self),
                  let owner = owner(of: pid), owner.bundleID != Bundle.main.bundleIdentifier else { continue }
            if input { result.insert(Activity(bundleID: owner.bundleID, appName: owner.name, layer: .mic)) }
            if output { result.insert(Activity(bundleID: owner.bundleID, appName: owner.name, layer: .audio)) }
        }
        return result
    }
}
