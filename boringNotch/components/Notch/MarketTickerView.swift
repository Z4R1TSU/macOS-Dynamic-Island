//
//  MarketTickerView.swift
//  boringNotch
//
//  Displays real-time crypto, stock, and commodity prices in the open notch.
//

import Defaults
import SwiftUI

struct MarketTickerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var marketManager = MarketManager.shared
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            tickerGrid
            footer
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
        .onAppear { marketManager.startMonitoring() }
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    BoringViewCoordinator.shared.currentView = .home
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

            Text("Markets")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                marketManager.fetchAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var tickerGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                spacing: 6
            ) {
                ForEach(marketManager.assets) { asset in
                    AssetCardView(asset: asset, useLiquidGlass: useLiquidGlass)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var footer: some View {
        HStack {
            Text("Updated \(formatTime(marketManager.lastUpdated))")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.5))
            Spacer()
            Text("Auto-refresh 30s")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

private struct AssetCardView: View {
    let asset: MarketAsset
    let useLiquidGlass: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(asset.symbol)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                typeIcon
            }

            if asset.isLoaded {
                Text(asset.formattedPrice)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 3) {
                    Image(systemName: asset.change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(asset.formattedChange)
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(asset.changeColor)

                Text("Vol \(asset.formattedVolume)")
                    .font(.system(size: 8, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(white: 0.5))
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(useLiquidGlass ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private var typeIcon: some View {
        let (icon, color): (String, Color) = {
            switch asset.type {
            case .crypto: return ("bitcoinsign.circle.fill", .orange)
            case .stock: return ("chart.line.uptrend.xyaxis", .blue)
            case .commodity: return ("laurel.leading", .yellow)
            }
        }()
        Image(systemName: icon)
            .font(.system(size: 8))
            .foregroundStyle(color.opacity(0.7))
    }
}

struct MarketClosedIndicatorView: View {
    @ObservedObject var marketManager = MarketManager.shared

    var body: some View {
        if let btc = marketManager.assets.first(where: { $0.symbol == "BTC" }), btc.isLoaded {
            HStack(spacing: 3) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                Text(btc.formattedPrice)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Image(systemName: btc.change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(btc.changeColor)
            }
        }
    }
}
