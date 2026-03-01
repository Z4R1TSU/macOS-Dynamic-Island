//
//  PomodoroManager.swift
//  boringNotch
//
//  Pomodoro timer with work/break cycles and notification support.
//

import Defaults
import SwiftUI
import UserNotifications

enum PomodoroState: String {
    case idle, working, onBreak, paused
}

@MainActor
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var state: PomodoroState = .idle
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var completedPomodoros: Int = 0

    private var timer: Timer?

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var stateLabel: String {
        switch state {
        case .idle: return "Ready"
        case .working: return "Focus"
        case .onBreak: return "Break"
        case .paused: return "Paused"
        }
    }

    var stateColor: Color {
        switch state {
        case .idle: return .gray
        case .working: return .red
        case .onBreak: return .green
        case .paused: return .orange
        }
    }

    private init() {}

    func startWork() {
        let minutes = Defaults[.pomodoroWorkMinutes]
        totalSeconds = minutes * 60
        remainingSeconds = totalSeconds
        state = .working
        startTimer()
    }

    func startBreak() {
        let minutes = Defaults[.pomodoroBreakMinutes]
        totalSeconds = minutes * 60
        remainingSeconds = totalSeconds
        state = .onBreak
        startTimer()
    }

    func togglePause() {
        if state == .paused {
            state = .working
            startTimer()
        } else if state == .working || state == .onBreak {
            state = .paused
            timer?.invalidate()
            timer = nil
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1

        if remainingSeconds <= 0 {
            timer?.invalidate()
            timer = nil

            if state == .working {
                completedPomodoros += 1
                sendNotification(title: "Focus Complete!", body: "Time for a break. You've done \(completedPomodoros) pomodoro\(completedPomodoros == 1 ? "" : "s").")
                startBreak()
            } else if state == .onBreak {
                sendNotification(title: "Break Over!", body: "Ready for another focus session?")
                state = .idle
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
