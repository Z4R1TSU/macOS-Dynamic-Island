//
//  UserNotificationManager.swift
//  boringNotch
//
//  Monitors macOS notification banners and intercepts them
//  to display within the notch area.
//

import AppKit
import Combine
import Defaults
import SwiftUI

struct NotchNotification: Identifiable {
    let id = UUID()
    var appName: String
    var appBundleIdentifier: String
    var appIcon: NSImage?
    var title: String
    var body: String
    var time: Date
}

@MainActor
final class UserNotificationManager: ObservableObject {
    static let shared = UserNotificationManager()

    @Published var currentNotification: NotchNotification?
    @Published var showNotification: Bool = false

    private var pollTimer: Timer?
    private var seenWindowIDs: Set<CGWindowID> = []
    private var dismissTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?

    private init() {
        settingsCancellable = Defaults.publisher(.enableNotifications)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.startMonitoring()
                    } else {
                        self?.stopMonitoring()
                    }
                }
            }

        if Defaults[.enableNotifications] {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForNotificationBanners()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        seenWindowIDs.removeAll()
    }

    private func checkForNotificationBanners() {
        guard Defaults[.enableNotifications] else { return }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

        var currentOnScreenIDs = Set<CGWindowID>()

        for info in windowList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            currentOnScreenIDs.insert(windowID)

            let isNotificationUI = ownerName == "NotificationCenter"
                || ownerName == "com.apple.notificationcenterui"
                || ownerName == "UserNotificationCenter"

            if isNotificationUI,
               let layer = info[kCGWindowLayer as String] as? Int,
               layer > 0,
               !seenWindowIDs.contains(windowID) {
                seenWindowIDs.insert(windowID)
                processNotificationBanner(pid: pid)
            }
        }

        seenWindowIDs = seenWindowIDs.intersection(currentOnScreenIDs)
    }

    // MARK: - Accessibility Extraction

    private func processNotificationBanner(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return }

        for window in windows {
            var texts: [String] = []
            extractTexts(from: window, into: &texts, depth: 0)

            guard texts.count >= 2 else { continue }

            let appName: String
            let title: String
            let body: String

            if texts.count >= 3 {
                appName = texts[0]
                title = texts[1]
                body = texts[2...].joined(separator: "\n")
            } else {
                appName = texts[0]
                title = texts[0]
                body = texts[1]
            }

            let bundleID = bundleIdentifier(forProcessID: pid) ?? ""
            let icon = appIconForNotification(appName: appName, bundleID: bundleID, pid: pid)

            let notification = NotchNotification(
                appName: appName,
                appBundleIdentifier: bundleID,
                appIcon: icon,
                title: title,
                body: body,
                time: Date()
            )

            presentNotification(notification)
            dismissSystemBanner(window: window)
            return
        }
    }

    private func extractTexts(from element: AXUIElement, into texts: inout [String], depth: Int) {
        guard depth < 10 else { return }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }

        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let text = titleRef as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !texts.contains(text) {
            texts.append(text)
        }

        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let text = descRef as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !texts.contains(text) {
            texts.append(text)
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                extractTexts(from: child, into: &texts, depth: depth + 1)
            }
        }
    }

    private func bundleIdentifier(forProcessID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func appIconForNotification(appName: String, bundleID: String, pid: pid_t) -> NSImage? {
        if !bundleID.isEmpty, let icon = AppIconAsNSImage(for: bundleID) {
            return icon
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.icon
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    // MARK: - Display

    private func presentNotification(_ notification: NotchNotification) {
        withAnimation(.smooth) {
            self.currentNotification = notification
            self.showNotification = true
        }

        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true, type: .notification, duration: 5.0
        )

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth) {
                    self.showNotification = false
                    self.currentNotification = nil
                }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.smooth) {
            showNotification = false
            currentNotification = nil
        }
    }

    // MARK: - Banner Suppression

    private func dismissSystemBanner(window: AXUIElement) {
        AXUIElementPerformAction(window, kAXPressAction as CFString)

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
                if let role = roleRef as? String, role == kAXButtonRole {
                    var subroleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef)
                    if let subrole = subroleRef as? String, subrole == kAXCloseButtonSubrole {
                        AXUIElementPerformAction(child, kAXPressAction as CFString)
                    }
                }
            }
        }
    }
}
