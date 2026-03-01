//
//  MarketManager.swift
//  boringNotch
//
//  Real-time market data for crypto, gold, and stocks via free APIs.
//  Crypto: CoinGecko (no key). Stocks/commodities: Yahoo Finance (informal).
//

import Combine
import Foundation
import SwiftUI

struct MarketAsset: Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String
    var price: Double = 0
    var change24h: Double = 0
    var volume24h: Double = 0
    var isLoaded: Bool = false
    let type: AssetType

    enum AssetType: String {
        case crypto, stock, commodity
    }

    var changeColor: Color {
        change24h >= 0 ? .green : .red
    }

    var formattedPrice: String {
        if price >= 10000 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.2f", price)
        } else {
            return String(format: "$%.4f", price)
        }
    }

    var formattedChange: String {
        String(format: "%@%.2f%%", change24h >= 0 ? "+" : "", change24h)
    }

    var formattedVolume: String {
        if volume24h >= 1_000_000_000 {
            return String(format: "%.1fB", volume24h / 1_000_000_000)
        } else if volume24h >= 1_000_000 {
            return String(format: "%.1fM", volume24h / 1_000_000)
        } else if volume24h >= 1_000 {
            return String(format: "%.1fK", volume24h / 1_000)
        }
        return String(format: "%.0f", volume24h)
    }
}

@MainActor
class MarketManager: ObservableObject {
    static let shared = MarketManager()

    @Published var assets: [MarketAsset] = []
    @Published var lastUpdated = Date()

    private var refreshTimer: Timer?

    private let defaultAssets: [MarketAsset] = [
        MarketAsset(id: "bitcoin", symbol: "BTC", name: "Bitcoin", type: .crypto),
        MarketAsset(id: "ethereum", symbol: "ETH", name: "Ethereum", type: .crypto),
        MarketAsset(id: "solana", symbol: "SOL", name: "Solana", type: .crypto),
        MarketAsset(id: "GC=F", symbol: "GOLD", name: "Gold", type: .commodity),
        MarketAsset(id: "AAPL", symbol: "AAPL", name: "Apple", type: .stock),
        MarketAsset(id: "SPY", symbol: "SPY", name: "S&P 500", type: .stock),
    ]

    private init() {
        assets = defaultAssets
    }

    func startMonitoring() {
        fetchAll()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchAll()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func fetchAll() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                let cryptoIDs = assets.filter { $0.type == .crypto }.map(\.id)
                if !cryptoIDs.isEmpty {
                    group.addTask { await self.fetchCrypto(ids: cryptoIDs) }
                }
                let yahooIDs = assets.filter { $0.type == .stock || $0.type == .commodity }.map(\.id)
                for ticker in yahooIDs {
                    group.addTask { await self.fetchYahoo(ticker: ticker) }
                }
            }
            lastUpdated = Date()
        }
    }

    // MARK: - CoinGecko (crypto, free, no key)

    private func fetchCrypto(ids: [String]) async {
        let joined = ids.joined(separator: ",")
        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(joined)&vs_currencies=usd&include_24hr_change=true&include_24hr_vol=true"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            for (coinID, info) in json {
                guard let info = info as? [String: Any],
                      let price = info["usd"] as? Double else { continue }
                let change = info["usd_24h_change"] as? Double ?? 0
                let vol = info["usd_24h_vol"] as? Double ?? 0

                if let idx = assets.firstIndex(where: { $0.id == coinID }) {
                    assets[idx].price = price
                    assets[idx].change24h = change
                    assets[idx].volume24h = vol
                    assets[idx].isLoaded = true
                }
            }
        } catch {}
    }

    // MARK: - Yahoo Finance (stocks & commodities, no key)

    private func fetchYahoo(ticker: String) async {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=1d"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let result = results.first,
                  let meta = result["meta"] as? [String: Any],
                  let regularPrice = meta["regularMarketPrice"] as? Double,
                  let previousClose = meta["chartPreviousClose"] as? Double
            else { return }

            let change = previousClose > 0 ? ((regularPrice - previousClose) / previousClose) * 100 : 0
            let vol = meta["regularMarketVolume"] as? Double ?? 0

            if let idx = assets.firstIndex(where: { $0.id == ticker }) {
                assets[idx].price = regularPrice
                assets[idx].change24h = change
                assets[idx].volume24h = vol
                assets[idx].isLoaded = true
            }
        } catch {}
    }
}
