//
//  Settings.swift
//  AudioAnchor
//
//  Created by Wataru Nagasawa on 2021/09/07.
//

import Foundation
import LaunchAtLogin

struct Settings {
    static var isDisabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: .isDisabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .isDisabled)
        }
    }

    static var isLaunchAtLoginEnabled: Bool {
        get {
            LaunchAtLogin.isEnabled
        }
        set {
            LaunchAtLogin.isEnabled = newValue
        }
    }

    /// Default on: undo macOS's switch to a newly connected device.
    static var keepsCurrentOnConnect: Bool {
        get {
            UserDefaults.standard.object(forKey: .keepsCurrentOnConnect) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .keepsCurrentOnConnect)
        }
    }

    static var anchoredDeviceName: String? {
        get {
            UserDefaults.standard.string(forKey: .anchoredDeviceName)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .anchoredDeviceName)
        }
    }
}

fileprivate extension String {
    static let isDisabled = "isDisabled"
    static let anchoredDeviceName = "anchoredDeviceName"
    static let keepsCurrentOnConnect = "keepsCurrentOnConnect"
}
