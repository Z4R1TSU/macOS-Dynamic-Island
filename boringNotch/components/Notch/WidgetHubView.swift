//
//  WidgetHubView.swift
//  boringNotch
//
//  Widget management page. Lists all available widgets with toggle and config.
//

import Defaults
import SwiftUI

struct WidgetHubView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.useLiquidGlass) var useLiquidGlass
    @Default(.enableMarketTicker) var enableMarketTicker
    @Default(.showCalendar) var showCalendar
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.closedNotchShowMarket) var closedNotchShowMarket
    @Default(.closedNotchShowPomodoro) var closedNotchShowPomodoro

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    widgetCard(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .orange,
                        title: "Markets",
                        subtitle: "Crypto, stocks & gold prices",
                        enabled: $enableMarketTicker,
                        showInClosed: $closedNotchShowMarket
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            coordinator.currentView = .market
                        }
                    }

                    widgetCard(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Calendar & Weather",
                        subtitle: "Events, time & weather info",
                        enabled: $showCalendar,
                        showInClosed: .constant(false),
                        hasDetail: false
                    )

                    widgetCard(
                        icon: "timer",
                        iconColor: .red,
                        title: "Pomodoro Timer",
                        subtitle: "Focus & break timer",
                        enabled: $enablePomodoro,
                        showInClosed: $closedNotchShowPomodoro,
                        hasDetail: false
                    )

                    widgetCard(
                        icon: "music.note",
                        iconColor: .pink,
                        title: "Music",
                        subtitle: "Now playing controls & lyrics",
                        enabled: .constant(true),
                        showInClosed: .constant(false),
                        hasDetail: false,
                        alwaysOn: true
                    )
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

    private var header: some View {
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

            Text("Widgets")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func widgetCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        enabled: Binding<Bool>,
        showInClosed: Binding<Bool>,
        hasDetail: Bool = true,
        alwaysOn: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(iconColor)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }

                Spacer()

                if !alwaysOn {
                    Toggle("", isOn: enabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if enabled.wrappedValue && !alwaysOn {
                Divider().background(Color.white.opacity(0.06))

                HStack {
                    if hasDetail {
                        Button {
                            onTap?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10))
                                Text("Configure")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Closed notch")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.5))
                        Toggle("", isOn: showInClosed)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(useLiquidGlass ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        )
    }
}
