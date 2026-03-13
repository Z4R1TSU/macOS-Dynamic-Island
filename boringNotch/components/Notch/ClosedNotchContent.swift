//
//  ClosedNotchContent.swift
//  boringNotch
//
//  Extracted closed-state notch content views.
//

import Defaults
import SwiftUI

// MARK: - Closed Widget Visibility Helpers

@MainActor
func closedWidgetShowPomodoro() -> Bool {
    Defaults[.closedNotchShowPomodoro] && Defaults[.enablePomodoro] && PomodoroManager.shared.state != .idle
}

@MainActor
func closedWidgetShowMarket() -> Bool {
    Defaults[.closedNotchShowMarket] && Defaults[.enableMarketTicker]
}

@MainActor
func closedWidgetShowLyrics() -> Bool {
    Defaults[.closedNotchShowLyrics] && Defaults[.enableLyrics]
}

@MainActor
func hasAnyClosedWidgetContent() -> Bool {
    closedWidgetShowPomodoro() || closedWidgetShowMarket() || closedWidgetShowLyrics()
}

// MARK: - ClosedNotchWidgetBar (no music — widgets flank the notch cutout)

struct ClosedNotchWidgetBar: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var pomodoroManager = PomodoroManager.shared
    @ObservedObject private var marketManager = MarketManager.shared
    @State private var marketDisplayIndex: Int = 0
    @State private var cycleTimer: Timer?

    private var loadedAssets: [MarketAsset] {
        marketManager.assets.filter(\.isLoaded)
    }

    private var currentMarketAsset: MarketAsset? {
        let assets = loadedAssets
        guard !assets.isEmpty else { return nil }
        return assets[marketDisplayIndex % assets.count]
    }

    var body: some View {
        let showPom = closedWidgetShowPomodoro()
        let showMkt = closedWidgetShowMarket()
        let widgetCount = (showPom ? 1 : 0) + (showMkt ? 1 : 0)

        if widgetCount == 0 {
            Rectangle().fill(.clear)
                .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
        } else if widgetCount == 1 {
            singleWidgetFlankingLayout(showPom: showPom, showMkt: showMkt)
                .onAppear { if showMkt { startCycling() } }
                .onDisappear { stopCycling() }
        } else {
            twoWidgetFlankingLayout
                .onAppear { startCycling() }
                .onDisappear { stopCycling() }
        }
    }

    /// Single widget: left (icon+symbol) | notch gap | right (price+arrow)
    @ViewBuilder
    private func singleWidgetFlankingLayout(showPom: Bool, showMkt: Bool) -> some View {
        HStack(spacing: 0) {
            Group {
                if showPom {
                    PomodoroClosedView().leftContent
                } else if showMkt, let asset = currentMarketAsset {
                    marketLeftLabel(asset: asset)
                }
            }
            .padding(.trailing, 8)

            Rectangle().fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Group {
                if showPom {
                    PomodoroClosedView().rightContent
                } else if showMkt, let asset = currentMarketAsset {
                    marketRightPrice(asset: asset)
                }
            }
            .padding(.leading, 8)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    /// Two widgets: pomodoro (left) | notch gap | market (right)
    private var twoWidgetFlankingLayout: some View {
        HStack(spacing: 0) {
            PomodoroClosedView()
                .padding(.trailing, 10)

            Rectangle().fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            if let asset = currentMarketAsset {
                marketPill(asset: asset)
                    .padding(.leading, 10)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    /// Left side: icon + symbol (pure text, no arrows)
    @ViewBuilder
    private func marketLeftLabel(asset: MarketAsset) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
            Text(asset.symbol)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .fixedSize()
        .id("left-\(asset.id)")
        .transition(.opacity.animation(.smooth(duration: 0.3)))
    }

    /// Right side: price + change arrow — gradient shimmer + digit-by-digit transition
    @ViewBuilder
    private func marketRightPrice(asset: MarketAsset) -> some View {
        HStack(spacing: 4) {
            Text(asset.compactPrice)
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .shimmerGradientForeground()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: asset.compactPrice)
            Image(systemName: asset.change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(asset.changeColor)
        }
        .fixedSize()
        .id("right-\(asset.id)")
        .transition(.opacity.animation(.smooth(duration: 0.3)))
    }

    /// Market pill (two-widget mode): icon + symbol + price + arrow
    @ViewBuilder
    private func marketPill(asset: MarketAsset) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray)
            Text(asset.symbol)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.gray)
            Text(asset.compactPrice)
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .shimmerGradientForeground()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: asset.compactPrice)
            Image(systemName: asset.change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(asset.changeColor)
        }
        .fixedSize()
        .id(asset.id)
        .transition(.opacity.animation(.smooth(duration: 0.3)))
    }

    private func startCycling() {
        stopCycling()
        let count = loadedAssets.count
        guard count > 1 else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                let c = loadedAssets.count
                guard c > 0 else { return }
                withAnimation(.smooth(duration: 0.4)) {
                    marketDisplayIndex = (marketDisplayIndex + 1) % c
                }
            }
        }
    }

    private func stopCycling() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }
}

// MARK: - BoringFaceAnimation

struct BoringFaceAnimation: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }
}

// MARK: - MusicLiveActivity

struct MusicLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared

    var albumArtNamespace: Namespace.ID
    var gestureProgress: CGFloat = 0

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.closedNotchShowLyrics) var closedNotchShowLyrics
    
    private var totalWidth: CGFloat {
        let albumArtWidth = max(0, vm.effectiveClosedNotchHeight - 12)
        let centerWidth = vm.closedNotchSize.width - cornerRadiusInsets.closed.top
        let visualizerWidth = max(0, vm.effectiveClosedNotchHeight - 12)
        return albumArtWidth + centerWidth + visualizerWidth + 10
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                    )
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                    .opacity(musicManager.isLoadingArtwork ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: musicManager.isLoadingArtwork)

                Rectangle()
                    .fill(.black)
                    .overlay(
                        HStack(alignment: .top) {
                            if coordinator.expandingView.show
                                && coordinator.expandingView.type == .music
                            {
                                MarqueeText(
                                    .constant(musicManager.songTitle),
                                    textColor: Color(nsColor: musicManager.avgColor),
                                    minDuration: 0.4,
                                    frameWidth: 100
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                                Spacer(minLength: vm.closedNotchSize.width)
                                Text(musicManager.artistName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(
                                        Color(nsColor: musicManager.avgColor)
                                    )
                                    .opacity(
                                        (coordinator.expandingView.show
                                            && coordinator.expandingView.type == .music
                                            && Defaults[.sneakPeekStyles] == .inline)
                                            ? 1 : 0
                                    )
                            }
                        }
                    )
                    .frame(
                        width: (coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                            && Defaults[.sneakPeekStyles] == .inline)
                            ? 380
                            : vm.closedNotchSize.width
                                + -cornerRadiusInsets.closed.top
                    )

                HStack {
                    if useMusicVisualizer {
                        Rectangle()
                            .fill(
                                Color(nsColor: musicManager.avgColor).gradient
                            )
                            .frame(width: 50, alignment: .center)
                            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                            .mask {
                                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                    .frame(width: 16, height: 12)
                            }
                    } else {
                        LottieAnimationContainer()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(
                    width: max(
                        0,
                        vm.effectiveClosedNotchHeight - 12
                            + gestureProgress / 2
                    ),
                    height: max(
                        0,
                        vm.effectiveClosedNotchHeight - 12
                    ),
                    alignment: .center
                )
            }
            .frame(
                height: vm.effectiveClosedNotchHeight,
                alignment: .center
            )
            
            if closedNotchShowLyrics {
                ClosedNotchLyricsView()
                    .frame(width: totalWidth)
            }
        }
    }
}

// MARK: - ClosedNotchLyricsView

struct ClosedNotchLyricsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.playerColorTinting) var playerColorTinting
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let currentElapsed: Double = musicManager.estimatedPlaybackPosition(at: timeline.date)
            let line: String = {
                if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                if !musicManager.syncedLyrics.isEmpty {
                    return musicManager.lyricLine(at: currentElapsed)
                }
                let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
            }()
            
            let isPersian = line.unicodeScalars.contains { scalar in
                let v = scalar.value
                return v >= 0x0600 && v <= 0x06FF
            }
            
            let lyricColor: Color = {
                if playerColorTinting {
                    return Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.5)
                        .opacity(0.85)
                }
                return .gray.opacity(0.85)
            }()
            
            GeometryReader { geometry in
                ZStack {
                    MarqueeText(
                        .constant(line),
                        font: .system(size: 11, weight: .medium),
                        nsFont: .body,
                        textColor: lyricColor,
                        minDuration: 1.2,
                        frameWidth: geometry.size.width,
                        alignment: .center
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: 11) : .system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.2), value: line)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 8)
    }
}
