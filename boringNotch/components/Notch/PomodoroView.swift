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
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(useLiquidGlass ? 0.15 : 0.1), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: pomodoro.progress)
                    .stroke(pomodoro.stateColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoro.progress)

                VStack(spacing: 0) {
                    Text(pomodoro.formattedTime)
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .adaptiveText(isGlass: useLiquidGlass)
                    Text(pomodoro.stateLabel)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(pomodoro.stateColor)
                        .conditionalModifier(useLiquidGlass) { $0.shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5) }
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                if pomodoro.completedPomodoros > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(pomodoro.completedPomodoros, 6), id: \.self) { _ in
                            Circle()
                                .fill(Color.red.opacity(0.6))
                                .frame(width: 4, height: 4)
                        }
                        if pomodoro.completedPomodoros > 6 {
                            Text("+\(pomodoro.completedPomodoros - 6)")
                                .font(.system(size: 7))
                                .foregroundStyle(useLiquidGlass ? .white.opacity(0.6) : .gray)
                        }
                    }
                }

                HStack(spacing: 4) {
                    if pomodoro.state == .idle {
                        Button {
                            pomodoro.startWork()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.red.opacity(0.8)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button {
                            pomodoro.togglePause()
                        } label: {
                            Image(systemName: pomodoro.state == .paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.white.opacity(useLiquidGlass ? 0.18 : 0.15)))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            pomodoro.reset()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.white.opacity(useLiquidGlass ? 0.18 : 0.15)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PomodoroExpandedClosedView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pomodoro.stateColor)
                Text(pomodoro.sneakPeekMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)

            Rectangle()
                .fill(.clear)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 4) {
                Text("\(pomodoro.completedPomodoros)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
        }
    }
}

struct PomodoroClosedView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        if pomodoro.state != .idle {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(pomodoro.stateColor)

                Text(pomodoro.formattedTime)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .shimmerGradientForeground()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth(duration: 0.4), value: pomodoro.formattedTime)
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    /// Left half for flanking layout: timer icon
    var leftContent: some View {
        Image(systemName: "timer")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(pomodoro.stateColor)
    }

    /// Right half for flanking layout: time text — gradient shimmer + countdown digit transition
    var rightContent: some View {
        Text(pomodoro.formattedTime)
            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
            .shimmerGradientForeground()
            .contentTransition(.numericText(countsDown: true))
            .animation(.smooth(duration: 0.4), value: pomodoro.formattedTime)
            .lineLimit(1)
            .fixedSize()
    }
}
