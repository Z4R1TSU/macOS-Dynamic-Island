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
    private var activeTimerInterval: TimeInterval?
    private var seenWindowIDs: Set<CGWindowID> = []
    private var recentPIDs: [pid_t: Date] = [:]
    private var dismissTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var isAccessibilityAuthorized: Bool = false
    private var startedAccessibilityMonitoring: Bool = false

    private var pollInterval: TimeInterval = 1.0
    private let idlePollInterval: TimeInterval = 1.0
    private let activePollInterval: TimeInterval = 0.2
    private let activeHoldDuration: TimeInterval = 4.0
    private var lastActiveAt: Date = .distantPast
    private let pidDebounceWindow: TimeInterval = 0.6

    private init() {
        settingsCancellable = Defaults.publisher(.enableNotifications)
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.reconcileMonitoring()
                }
            }

        accessibilityCancellable = NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    self.isAccessibilityAuthorized = (notification.userInfo?["granted"] as? Bool) ?? false
                    self.reconcileMonitoring()
                }
            }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            self.reconcileMonitoring()
        }

        reconcileMonitoring()
    }

    func startMonitoring() {
        guard Defaults[.enableNotifications], isAccessibilityAuthorized else {
            stopMonitoring()
            return
        }

        if pollTimer != nil, activeTimerInterval == pollInterval {
            return
        }

        pollTimer?.invalidate()
        pollTimer = nil

        activeTimerInterval = pollInterval
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollTick()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        activeTimerInterval = nil
        seenWindowIDs.removeAll()
    }

    private func reconcileMonitoring() {
        if Defaults[.enableNotifications], !XPCHelperClient.shared.isMonitoring {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization(every: 5.0)
            startedAccessibilityMonitoring = true
        } else if !Defaults[.enableNotifications], startedAccessibilityMonitoring {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
            startedAccessibilityMonitoring = false
        }

        if Defaults[.enableNotifications], isAccessibilityAuthorized {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func pollTick() {
        guard Defaults[.enableNotifications], isAccessibilityAuthorized else {
            stopMonitoring()
            return
        }

        let isActive = checkForNotificationBanners()
        let now = Date()

        if isActive {
            lastActiveAt = now
            updatePollInterval(activePollInterval)
        } else if now.timeIntervalSince(lastActiveAt) > activeHoldDuration {
            updatePollInterval(idlePollInterval)
        }
    }

    private func updatePollInterval(_ interval: TimeInterval) {
        guard pollInterval != interval else { return }
        pollInterval = interval
        startMonitoring()
    }

    @discardableResult
    private func checkForNotificationBanners() -> Bool {
        guard Defaults[.enableNotifications], isAccessibilityAuthorized else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return showNotification }

        var currentOnScreenIDs = Set<CGWindowID>()
        var foundNotificationUI = false

        for info in windowList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }

            let isNotificationUI = ownerName == "NotificationCenter"
                || ownerName == "com.apple.notificationcenterui"
                || ownerName == "UserNotificationCenter"

            if isNotificationUI,
               let layer = info[kCGWindowLayer as String] as? Int,
               layer > 0 {
                foundNotificationUI = true
                currentOnScreenIDs.insert(windowID)

                if !seenWindowIDs.contains(windowID) {
                    seenWindowIDs.insert(windowID)
                    if shouldProcess(pid: pid) {
                        processNotificationBanner(pid: pid)
                    }
                }
            }
        }

        seenWindowIDs = seenWindowIDs.intersection(currentOnScreenIDs)
        return foundNotificationUI || showNotification
    }

    private func shouldProcess(pid: pid_t) -> Bool {
        let now = Date()

        recentPIDs = recentPIDs.filter { now.timeIntervalSince($0.value) < 6.0 }

        if let last = recentPIDs[pid], now.timeIntervalSince(last) < pidDebounceWindow {
            return false
        }

        recentPIDs[pid] = now
        return true
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
