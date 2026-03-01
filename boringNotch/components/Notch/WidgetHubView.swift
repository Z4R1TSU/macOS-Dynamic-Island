//
//  WidgetHubView.swift
//  boringNotch
//
//  Widget management — settings-style list with detail configuration pages.
//

import Defaults
import SwiftUI

enum WidgetPage: Hashable {
    case list
    case markets
    case calendar
    case pomodoro
    case translation
    case music
}

struct WidgetHubView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.useLiquidGlass) var useLiquidGlass
    @State private var page: WidgetPage = .list

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .list:
                widgetListPage
            case .markets:
                WidgetDetailMarkets(page: $page)
            case .calendar:
                WidgetDetailCalendar(page: $page)
            case .pomodoro:
                WidgetDetailPomodoro(page: $page)
            case .translation:
                WidgetDetailTranslation(page: $page)
            case .music:
                WidgetDetailMusic(page: $page)
            }
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }

    // MARK: - List Page

    private var widgetListPage: some View {
        VStack(spacing: 0) {
            widgetListHeader
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    widgetSection("Finance & Data") {
                        widgetRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Markets",
                            subtitle: "Crypto, stocks & gold prices"
                        ) { navigateTo(.markets) }
                    }

                    widgetSection("Productivity") {
                        widgetRow(
                            icon: "calendar",
                            title: "Calendar & Weather",
                            subtitle: "Events, time & weather info"
                        ) { navigateTo(.calendar) }

                        widgetRow(
                            icon: "timer",
                            title: "Pomodoro Timer",
                            subtitle: "Focus & break work cycles"
                        ) { navigateTo(.pomodoro) }

                        widgetRow(
                            icon: "textformat.abc",
                            title: "Translation",
                            subtitle: "Translate text between languages"
                        ) { navigateTo(.translation) }
                    }

                    widgetSection("Built-in") {
                        dynaClipRow
                    }

                    widgetSection("Media") {
                        widgetRow(
                            icon: "music.note",
                            title: "Music",
                            subtitle: "Now playing controls & display"
                        ) { navigateTo(.music) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private var widgetListHeader: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    coordinator.currentView = .home
                    vm.notchSize = openNotchSize
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(useLiquidGlass ? .white.opacity(0.7) : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text("Widgets")
                .font(.system(size: 13, weight: .semibold))
                .adaptiveText(isGlass: useLiquidGlass)

            Spacer()

            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func widgetSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(useLiquidGlass ? .white.opacity(0.5) : .gray.opacity(0.7))
                .padding(.leading, 4)

            VStack(spacing: 1) {
                content()
            }
            .background(useLiquidGlass ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func widgetRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .conditionalModifier(useLiquidGlass) { $0.glassIcon() }
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .adaptiveText(isGlass: useLiquidGlass)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(useLiquidGlass ? .white.opacity(0.65) : .gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var dynaClipRow: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                coordinator.currentView = .clip
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .conditionalModifier(useLiquidGlass) { $0.glassIcon() }
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DynaClip")
                        .font(.system(size: 12, weight: .semibold))
                        .adaptiveText(isGlass: useLiquidGlass)
                    Text("Mini file browser — always available")
                        .font(.system(size: 10))
                        .foregroundStyle(useLiquidGlass ? .white.opacity(0.65) : .gray)
                }

                Spacer()

                Text("Built-in")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(useLiquidGlass ? 0.1 : 0.06))
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func navigateTo(_ target: WidgetPage) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            page = target
        }
    }
}

// MARK: - Detail Header

private struct WidgetDetailHeader: View {
    let title: String
    @Binding var page: WidgetPage
    @Default(.useLiquidGlass) private var useLiquidGlass

    var body: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    page = .list
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Widgets")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(useLiquidGlass ? .white.opacity(0.7) : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .adaptiveText(isGlass: useLiquidGlass)

            Spacer()

            Color.clear.frame(width: 56, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Detail: Markets

private struct WidgetDetailMarkets: View {
    @Binding var page: WidgetPage
    @Default(.enableMarketTicker) var enableMarketTicker
    @Default(.closedNotchShowMarket) var closedNotchShowMarket
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(spacing: 0) {
            WidgetDetailHeader(title: "Markets", page: $page)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    detailSection {
                        detailDescription(
                            "Real-time prices for Bitcoin, Ethereum, Solana, Gold, AAPL and S&P 500. Data refreshes every 30 seconds automatically."
                        )
                    }
                    detailSection {
                        detailToggle(title: "Enable Markets", isOn: $enableMarketTicker)
                        detailToggle(title: "Show in closed notch", isOn: $closedNotchShowMarket)
                    }
                    if enableMarketTicker {
                        detailSection {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    BoringViewCoordinator.shared.currentView = .market
                                }
                            } label: {
                                HStack {
                                    Text("Open Market View")
                                        .font(.system(size: 12, weight: .medium))
                                        .adaptiveText(isGlass: useLiquidGlass)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(useLiquidGlass ? .white.opacity(0.6) : .gray)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Detail: Calendar

private struct WidgetDetailCalendar: View {
    @Binding var page: WidgetPage
    @Default(.showCalendar) var showCalendar
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(spacing: 0) {
            WidgetDetailHeader(title: "Calendar & Weather", page: $page)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    detailSection {
                        detailDescription(
                            "Shows the current date, time, upcoming calendar events, and live weather conditions. Weather includes temperature and rain particle effects when applicable."
                        )
                    }
                    detailSection {
                        detailToggle(title: "Enable Calendar", isOn: $showCalendar)
                    }
                    detailSection {
                        detailHint("Calendar and weather appear on the Home tab when enabled. Weather uses your current location.")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Detail: Pomodoro

private struct WidgetDetailPomodoro: View {
    @Binding var page: WidgetPage
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.pomodoroWorkMinutes) var pomodoroWorkMinutes
    @Default(.pomodoroBreakMinutes) var pomodoroBreakMinutes
    @Default(.closedNotchShowPomodoro) var closedNotchShowPomodoro
    @Default(.useLiquidGlass) var useLiquidGlass
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        VStack(spacing: 0) {
            WidgetDetailHeader(title: "Pomodoro Timer", page: $page)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    detailSection {
                        detailDescription(
                            "A focus timer using the Pomodoro Technique. Work in focused intervals, then take short breaks. Tracks completed sessions and sends notifications when intervals end."
                        )
                    }
                    detailSection {
                        detailToggle(title: "Enable Pomodoro", isOn: $enablePomodoro)
                        detailToggle(title: "Show in closed notch", isOn: $closedNotchShowPomodoro)
                    }
                    if enablePomodoro {
                        detailSection {
                            detailStepper(
                                title: "Focus duration",
                                value: $pomodoroWorkMinutes,
                                unit: "min",
                                range: 1...120
                            )
                            detailStepper(
                                title: "Break duration",
                                value: $pomodoroBreakMinutes,
                                unit: "min",
                                range: 1...60
                            )
                        }

                        detailSection {
                            pomodoroControls
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var pomodoroControls: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pomodoro.stateLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .adaptiveText(isGlass: useLiquidGlass)
                    if pomodoro.state != .idle {
                        Text(pomodoro.formattedTime)
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundStyle(pomodoro.stateColor)
                            .conditionalModifier(useLiquidGlass) { $0.shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5) }
                    }
                }
                Spacer()
                Text("\(pomodoro.completedPomodoros) done")
                    .font(.system(size: 11))
                    .foregroundStyle(useLiquidGlass ? .white.opacity(0.65) : .gray)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if pomodoro.state != .idle {
                ProgressView(value: pomodoro.progress)
                    .tint(pomodoro.stateColor)
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 10) {
                if pomodoro.state == .idle {
                    pomodoroButton("Start Focus", color: .red) {
                        pomodoro.startWork()
                    }
                } else {
                    pomodoroButton(
                        pomodoro.state == .paused ? "Resume" : "Pause",
                        color: .orange
                    ) {
                        pomodoro.togglePause()
                    }
                    pomodoroButton("Reset", color: .gray) {
                        pomodoro.reset()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func pomodoroButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.3))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Detail: Translation

private struct WidgetDetailTranslation: View {
    @Binding var page: WidgetPage
    @Default(.enableTranslation) var enableTranslation
    @Default(.useLiquidGlass) var useLiquidGlass
    @ObservedObject var translationManager = TranslationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            WidgetDetailHeader(title: "Translation", page: $page)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    detailSection {
                        detailDescription(
                            "Translate text between languages using Google Translate. Auto-detects the source language — Chinese text translates to English, other languages translate to Chinese."
                        )
                    }
                    detailSection {
                        detailToggle(title: "Enable Translation", isOn: $enableTranslation)
                    }
                    if enableTranslation {
                        detailSection {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quick Translate")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)

                                HStack(spacing: 6) {
                                    TextField("Type or paste text...", text: $translationManager.inputText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.white.opacity(0.08))
                                        )
                                        .onSubmit {
                                            translateAndOpen()
                                        }

                                    Button {
                                        translateAndOpen()
                                    } label: {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.cyan)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(translationManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                            }
                        }
                        detailSection {
                            detailHint("Shortcut: Fn + T translates selected text. Or type text above and press Return / tap the arrow.")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func translateAndOpen() {
        translationManager.translateCustomText()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            BoringViewCoordinator.shared.currentView = .translation
        }
    }
}

// MARK: - Detail: Music

private struct WidgetDetailMusic: View {
    @Binding var page: WidgetPage
    @Default(.enableSneakPeek) var enableSneakPeek
    @Default(.enableLyrics) var enableLyrics
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(spacing: 0) {
            WidgetDetailHeader(title: "Music", page: $page)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    detailSection {
                        detailDescription(
                            "Displays currently playing music with album art, playback controls, and an audio visualizer. Supports Apple Music, Spotify, and all apps that use macOS Now Playing."
                        )
                    }
                    detailSection {
                        detailHint("Music is always enabled. It appears automatically when any app starts playing audio.")
                    }
                    detailSection {
                        detailToggle(title: "Song Peek", subtitle: "Brief notification on track change", isOn: $enableSneakPeek)
                        detailToggle(title: "Lyrics", subtitle: "Show synced lyrics", isOn: $enableLyrics)
                        detailToggle(title: "Visualizer", subtitle: "Audio spectrum animation", isOn: $useMusicVisualizer)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Shared Detail Helpers

@ViewBuilder
private func detailSection(@ViewBuilder content: () -> some View) -> some View {
    let isGlass = Defaults[.useLiquidGlass]
    VStack(spacing: 1) {
        content()
    }
    .background(Color.white.opacity(isGlass ? 0.12 : 0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
}

@ViewBuilder
private func detailToggle(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
    let isGlass = Defaults[.useLiquidGlass]
    HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .adaptiveText(isGlass: isGlass)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isGlass ? .white.opacity(0.65) : .gray)
            }
        }
        Spacer()
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
}

@ViewBuilder
private func detailDescription(_ text: String) -> some View {
    let isGlass = Defaults[.useLiquidGlass]
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(isGlass ? 0.8 : 0.75))
        .conditionalModifier(isGlass) { $0.shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5) }
        .lineSpacing(2)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
}

@ViewBuilder
private func detailHint(_ text: String) -> some View {
    let isGlass = Defaults[.useLiquidGlass]
    HStack(spacing: 6) {
        Image(systemName: "info.circle")
            .font(.system(size: 10))
            .foregroundStyle(.cyan.opacity(0.7))
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(isGlass ? .white.opacity(0.65) : .gray)
            .conditionalModifier(isGlass) { $0.shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5) }
            .lineSpacing(2)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
}

@ViewBuilder
private func detailStepper(title: String, value: Binding<Int>, unit: String, range: ClosedRange<Int>) -> some View {
    let isGlass = Defaults[.useLiquidGlass]
    HStack(spacing: 10) {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .adaptiveText(isGlass: isGlass)
        Spacer()
        HStack(spacing: 6) {
            Button {
                if value.wrappedValue > range.lowerBound {
                    value.wrappedValue -= 1
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isGlass ? .white.opacity(0.7) : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Text("\(value.wrappedValue) \(unit)")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .adaptiveText(isGlass: isGlass)
                .frame(minWidth: 42)

            Button {
                if value.wrappedValue < range.upperBound {
                    value.wrappedValue += 1
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isGlass ? .white.opacity(0.7) : .gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
}
