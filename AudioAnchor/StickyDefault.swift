//
//  StickyDefault.swift
//  AudioAnchor
//
//  Keeps the current default device when macOS auto-selects a device that
//  was just connected (e.g. a USB speaker on a hub/dock taking over from the
//  MacBook speakers).
//

import Foundation
import SimplyCoreAudio
import os.log

let stickyLog = OSLog(subsystem: "dev.wata.AudioAnchor", category: "sticky")

/// Remembers which devices are newly connected, so a default-device change
/// can be classified as "macOS auto-switched to a device that just appeared".
final class DeviceArrivals {
    /// A default-device change to a device that appeared this recently counts
    /// as macOS's auto-switch (it lands within a few hundred ms). Kept short so
    /// a manual pick right after plugging in is honoured, not reverted.
    static let window: TimeInterval = 2

    private var knownUIDs: Set<String>
    private var arrivedAt = [String: Date]()

    init(devices: [AudioDevice]) {
        knownUIDs = Set(devices.compactMap(\.uid))
    }

    func update(added: [AudioDevice], removed: [AudioDevice]) {
        let now = Date()
        for uid in added.compactMap(\.uid) {
            knownUIDs.insert(uid)
            arrivedAt[uid] = now
        }
        for uid in removed.compactMap(\.uid) {
            knownUIDs.remove(uid)
            arrivedAt[uid] = nil
        }
    }

    /// True if the device is not yet in the list we have seen (the default
    /// change was announced before the device-list change) or appeared within
    /// `window` seconds.
    func isFresh(_ uid: String) -> Bool {
        if !knownUIDs.contains(uid) { return true }
        guard let date = arrivedAt[uid] else { return false }
        return Date().timeIntervalSince(date) < Self.window
    }
}

/// Tracks one default-device slot (output, system output, ...) and undoes
/// macOS's switch to a newly connected device.
///
/// A connecting device may take over when `isExempt` says so: the anchored
/// device, Bluetooth audio, and the persisted take-over list
/// (`Settings.takeoverDeviceUIDs`). With `learnsChoices`, that list follows
/// the user: picking a device by hand adds it, and switching away from a
/// device that is still connected removes it. A change caused by the previous
/// device disappearing is a forced fallback and teaches nothing, so
/// re-plugging the device you were using lets it take over again.
final class StickyDefault {
    private let label: String
    private let read: () -> AudioDevice?
    private let write: (AudioDevice) -> Void
    private let arrivals: DeviceArrivals
    /// Devices allowed to take over when they connect (e.g. the anchored one).
    private let isExempt: (AudioDevice) -> Bool
    private let learnsChoices: Bool
    private let isAnchored: (AudioDevice) -> Bool

    private var currentUID: String?
    private var reverts = [(uid: String, at: Date)]()

    init(label: String,
         arrivals: DeviceArrivals,
         read: @escaping () -> AudioDevice?,
         write: @escaping (AudioDevice) -> Void,
         isExempt: @escaping (AudioDevice) -> Bool,
         isAnchored: @escaping (AudioDevice) -> Bool,
         learnsChoices: Bool) {
        self.label = label
        self.arrivals = arrivals
        self.read = read
        self.write = write
        self.isExempt = isExempt
        self.isAnchored = isAnchored
        self.learnsChoices = learnsChoices
        currentUID = read()?.uid
    }

    /// Call on every default-device change and device-list change; it is
    /// idempotent when nothing moved.
    func reconcile() {
        guard let new = read(), let newUID = new.uid, newUID != currentUID else { return }
        let previous = currentUID.flatMap { AudioDevice.lookup(by: $0) }

        let fresh = arrivals.isFresh(newUID)
        if Settings.keepsCurrentOnConnect,
           fresh,
           !isExempt(new),
           let previous = previous,
           !tooManyReverts(of: newUID) {
            os_log("%{public}@: macOS switched to newly connected \"%{public}@\"; restoring \"%{public}@\"",
                   log: stickyLog, type: .default, label, new.name, previous.name)
            reverts.append((newUID, Date()))
            write(previous)
            return // currentUID stays on `previous`
        }

        if let previous = previous {
            os_log("%{public}@: default is now \"%{public}@\"%{public}@",
                   log: stickyLog, type: .default, label, new.name, fresh ? " (allowed to take over)" : "")
            // A pick made after the arrival window, not one forced by the
            // anchor, is the user's: remember it for the next connect.
            if learnsChoices, !fresh, !isAnchored(new), let previousUID = previous.uid {
                var allowed = Settings.takeoverDeviceUIDs
                allowed.remove(previousUID)
                allowed.insert(newUID)
                Settings.takeoverDeviceUIDs = allowed
            }
        } else {
            os_log("%{public}@: previous device gone, macOS fell back to \"%{public}@\"",
                   log: stickyLog, type: .default, label, new.name)
        }
        currentUID = newUID
    }

    /// Loop guard: if something keeps re-selecting the device, stop fighting.
    private func tooManyReverts(of uid: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-10)
        reverts.removeAll { $0.at < cutoff }
        let count = reverts.filter { $0.uid == uid }.count
        if count >= 3 {
            os_log("%{public}@: giving up restoring after %d reverts in 10 s",
                   log: stickyLog, type: .error, label, count)
            return true
        }
        return false
    }
}
