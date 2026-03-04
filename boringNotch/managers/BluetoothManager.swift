//
//  BluetoothManager.swift
//  boringNotch
//
//  Monitors Bluetooth device connections and shows sneak peek notifications.
//

import IOBluetooth
import SwiftUI
import Defaults

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published var lastDeviceName: String = ""
    @Published var lastDeviceConnected: Bool = true
    @Published var lastDeviceIcon: String = "wave.3.right"

    private var connectNotification: IOBluetoothUserNotification?
    private var deviceNotifications: [IOBluetoothUserNotification] = []

    private override init() {
        super.init()
    }

    func startMonitoring() {
        guard Defaults[.enableBluetoothNotifications] else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil
        for n in deviceNotifications { n.unregister() }
        deviceNotifications.removeAll()
    }

    // Public method to manually trigger connection sequence (e.g. from VolumeManager on audio route change)
    @MainActor
    func triggerConnectionSequence(name: String, icon: String = "headphones") {
        // Avoid duplicate triggers if we already processed this via IOBluetooth notification
        guard !BoringViewCoordinator.shared.isBluetoothConnecting else { return }
        
        // Set flag to suppress volume HUD
        BoringViewCoordinator.shared.isBluetoothConnecting = true
        
        self.lastDeviceName = name
        self.lastDeviceConnected = true
        self.lastDeviceIcon = icon
        
        // Show bluetooth HUD
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .bluetooth,
            duration: 2.5
        )
        
        Task {
            // Wait for 2.5 seconds (HUD duration)
            try? await Task.sleep(for: .milliseconds(2500))
            
            // Reset flag
            BoringViewCoordinator.shared.isBluetoothConnecting = false
            
            // After bluetooth HUD is done, trigger volume HUD
            // This ensures user sees the new volume level after connection
            let currentVol = VolumeManager.shared.rawVolume
            let currentMuted = VolumeManager.shared.isMuted
            
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .volume,
                duration: 2.5,
                value: CGFloat(currentMuted ? 0 : currentVol)
            )
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Unknown Device"
        let icon = iconForDevice(device)
        
        Task { @MainActor in
            triggerConnectionSequence(name: name, icon: icon)
        }

        let disconnectNotif = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        if let n = disconnectNotif {
            deviceNotifications.append(n)
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Unknown Device"
        let icon = iconForDevice(device)

        Task { @MainActor in
            self.lastDeviceName = name
            self.lastDeviceConnected = false
            self.lastDeviceIcon = icon

            // Optionally show disconnect status?
            // BoringViewCoordinator.shared.toggleSneakPeek(
            //    status: true,
            //    type: .bluetooth,
            //    duration: 2.5
            // )
        }
    }

    private func iconForDevice(_ device: IOBluetoothDevice) -> String {
        let classOfDevice = device.classOfDevice
        let majorClass = (classOfDevice >> 8) & 0x1F

        switch majorClass {
        case 0x05: // Peripheral (mouse, keyboard, etc.)
            let minorClass = (classOfDevice >> 2) & 0x3F
            switch minorClass {
            case 0x01: return "keyboard"
            case 0x02: return "computermouse"
            case 0x03: return "keyboard" // combo
            default: return "gamecontroller"
            }
        case 0x04: // Audio/Video
            return "airpods"
        case 0x01: // Computer
            return "desktopcomputer"
        case 0x02: // Phone
            return "iphone"
        default:
            return "wave.3.right"
        }
    }
}
