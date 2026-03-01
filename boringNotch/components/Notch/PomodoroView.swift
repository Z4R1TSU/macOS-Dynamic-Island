//
//  PomodoroView.swift
//  boringNotch
//
//  Compact pomodoro timer for the home view and closed notch indicator.
//

import Defaults
import SwiftUI

struct PomodoroCompactView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: pomodoro.progress)
                    .stroke(pomodoro.stateColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoro.progress)

                VStack(spacing: 1) {
                    Text(pomodoro.formattedTime)
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(pomodoro.stateLabel)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(pomodoro.stateColor)
                }
            }
            .frame(width: 60, height: 60)

            HStack(spacing: 8) {
                if pomodoro.state == .idle {
                    Button {
                        pomodoro.startWork()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.red.opacity(0.8)))
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button {
                        pomodoro.togglePause()
                    } label: {
                        Image(systemName: pomodoro.state == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        pomodoro.reset()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if pomodoro.completedPomodoros > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<min(pomodoro.completedPomodoros, 8), id: \.self) { _ in
                        Circle()
                            .fill(Color.red.opacity(0.6))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PomodoroClosedView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        if pomodoro.state != .idle {
            HStack(spacing: 3) {
                Circle()
                    .fill(pomodoro.stateColor)
                    .frame(width: 5, height: 5)
                Text(pomodoro.formattedTime)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}
