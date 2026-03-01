//
//  NotchSettingsView.swift
//  boringNotch
//
//  In-notch settings page with feature toggles.
//

import SwiftUI
import Defaults

struct NotchSettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hudReplacement) var hudReplacement
    @Default(.enableNotifications) var enableNotifications
    @Default(.useLiquidGlass) var useLiquidGlass
    @Default(.enableSneakPeek) var enableSneakPeek
    @Default(.showCalendar) var showCalendar
    @Default(.showMirror) var showMirror
    @Default(.enableLyrics) var enableLyrics
    @Default(.boringShelf) var boringShelf

    var body: some View {
        VStack(spacing: 0) {
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
                    .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open full settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    settingsSection("Features") {
                        settingsToggle(
                            icon: "speaker.wave.2.fill",
                            title: "Volume HUD",
                            subtitle: "Replace system volume indicator",
                            isOn: $hudReplacement
                        )
                        settingsToggle(
                            icon: "bell.fill",
                            title: "Notifications",
                            subtitle: "Show notifications in notch",
                            isOn: $enableNotifications
                        )
                        settingsToggle(
                            icon: "music.note",
                            title: "Song Peek",
                            subtitle: "Show track changes briefly",
                            isOn: $enableSneakPeek
                        )
                        settingsToggle(
                            icon: "text.quote",
                            title: "Lyrics",
                            subtitle: "Show synced lyrics",
                            isOn: $enableLyrics
                        )
                    }

                    settingsSection("Modules") {
                        settingsToggle(
                            icon: "calendar",
                            title: "Calendar",
                            subtitle: "Show upcoming events",
                            isOn: $showCalendar
                        )
                        settingsToggle(
                            icon: "camera.fill",
                            title: "Mirror",
                            subtitle: "Camera preview",
                            isOn: $showMirror
                        )
                        settingsToggle(
                            icon: "tray.fill",
                            title: "Shelf",
                            subtitle: "Drag & drop file shelf",
                            isOn: $boringShelf
                        )
                    }

                    settingsSection("Appearance") {
                        settingsToggle(
                            icon: "drop.fill",
                            title: "Liquid Glass",
                            subtitle: "Translucent glass effect",
                            isOn: $useLiquidGlass
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }

    // MARK: - Components

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
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
    private func settingsToggle(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isOn.wrappedValue ? .white : .gray)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: useLiquidGlass ? .black.opacity(0.3) : .clear, radius: 1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(useLiquidGlass ? .white.opacity(0.6) : .gray)
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
}
