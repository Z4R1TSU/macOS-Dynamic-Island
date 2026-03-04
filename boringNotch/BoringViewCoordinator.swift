//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case notification
    case pomodoro
    case bluetooth
    case lock
    case unlock
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var notchIsOpen: Bool = false
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            // Always start MediaKeyInterceptor if possible, regardless of hudReplacement preference
            // This allows us to detect media keys and trigger our HUD manually if we want,
            // or at least have the capability. 
            // However, MediaKeyInterceptor logic usually suppresses system HUD if active.
            // If hudReplacement is OFF, we probably want system HUD to show?
            // User request: "When executing system operation... automatically trigger visual feedback in notch".
            // This implies we WANT to show our HUD.
            // If hudReplacement is OFF, the system HUD shows up. If we also show ours, we have double HUDs.
            // Maybe user WANTS double HUDs or wants ours to replace system HUD implicitly?
            // "When not enabling HUD replacement, modifying volume still doesn't show".
            // This means we are relying on `MediaKeyInterceptor` to detect keys.
            // If `hudReplacement` is false, `MediaKeyInterceptor` is stopped (lines 163-167).
            // So we never get the callbacks.
            
            // We need to enable MediaKeyInterceptor to get the events.
            // BUT MediaKeyInterceptor might swallow the event preventing system HUD.
            // Let's look at MediaKeyInterceptor.
            
            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    Defaults[.hudReplacement] = false
                } else {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            } else {
                 // Try to start it anyway to catch events, but we need to make sure we don't block system HUD
                 // if user didn't ask to replace it.
                 // But `MediaKeyInterceptor` implementation uses an event tap that consumes events if we handle them.
                 // If we handle them to show our HUD, we consume them.
                 // So "Show Notch HUD" implies "Consume Event" implies "Replace System HUD".
                 // Unless we can re-post the event?
                 // MediaKeyInterceptor returns `nil` (consumes) or `Unmanaged` (passes through).
                 
                 // If the user wants to see the notch HUD *without* replacing system HUD (i.e. double HUD),
                 // we would need to pass the event through.
                 // But `MediaKeyInterceptor` logic is currently: "If handleEvent returns true (handled), return nil".
                 
                 // Let's start it anyway so at least we get the events.
                 // We might need to adjust MediaKeyInterceptor to NOT consume events if hudReplacement is false.
                 await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            }
        }
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 2.5, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        
        if type == .notification && !Defaults[.enableNotifications] {
            return
        }
        
        // If screen is locked, only allow lock/unlock type
        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.isScreenLocked {
            if type != .lock && type != .unlock {
                return
            }
        }
        
        // If showing lock icon, force update regardless of current state
        if type == .lock {
            // Cancel any existing hide tasks
            sneakPeekTask?.cancel()
            sneakPeekTask = nil
        }
        
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.25)) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                // If type is .lock, do NOT schedule hide
                if sneakPeek.type != .lock {
                    scheduleSneakPeekHide(after: sneakPeekDuration)
                } else {
                    // For lock type, cancel any existing timer
                    sneakPeekTask?.cancel()
                }
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }
    
    // Flag to indicate if bluetooth connection sequence is active
    // When true, volume changes should be suppressed or delayed
    var isBluetoothConnecting: Bool = false

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.25)) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    func showEmpty() {
        currentView = .home
    }
}
