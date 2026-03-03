//
//  MarketManager.swift
//  boringNotch
//
//  Real-time market data for crypto, gold, and stocks via free APIs.
//  Crypto: Binance (no key). Stocks/commodities: Yahoo Finance (no key).
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

    /// Binance trading pair symbol (e.g. "BTCUSDT"), only for crypto
    var binanceSymbol: String? {
        guard type == .crypto else { return nil }
        return symbol.uppercased() + "USDT"
    }

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

    var compactPrice: String {
        if price >= 100_000 {
            return String(format: "$%.0fK", price / 1_000)
        } else if price >= 10_000 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.1f", price)
        } else {
            return String(format: "$%.3f", price)
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
        refreshTimer?.invalidate()
        refreshTimer = nil
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
                let cryptoAssets = assets.filter { $0.type == .crypto }
                if !cryptoAssets.isEmpty {
                    group.addTask { await self.fetchCryptoBinance(assets: cryptoAssets) }
                }
                let yahooIDs = assets.filter { $0.type == .stock || $0.type == .commodity }.map(\.id)
                for ticker in yahooIDs {
                    group.addTask { await self.fetchYahoo(ticker: ticker) }
                }
            }
            lastUpdated = Date()
        }
    }

    // MARK: - Binance (crypto, free, no key, reliable)

    private func fetchCryptoBinance(assets cryptoAssets: [MarketAsset]) async {
        let symbols = cryptoAssets.compactMap(\.binanceSymbol)
        let symbolsJSON = "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        guard let encoded = symbolsJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbols=\(encoded)")
        else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let tickers = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

            for ticker in tickers {
                guard let pairSymbol = ticker["symbol"] as? String,
                      let priceStr = ticker["lastPrice"] as? String,
                      let price = Double(priceStr),
                      let changeStr = ticker["priceChangePercent"] as? String,
                      let change = Double(changeStr),
                      let volStr = ticker["quoteVolume"] as? String,
                      let vol = Double(volStr)
                else { continue }

                if let idx = self.assets.firstIndex(where: { $0.binanceSymbol == pairSymbol }) {
                    self.assets[idx].price = price
                    self.assets[idx].change24h = change
                    self.assets[idx].volume24h = vol
                    self.assets[idx].isLoaded = true
                }
            }
        } catch {
            NSLog("Binance API error: \(error.localizedDescription)")
        }
    }

    // MARK: - Yahoo Finance (stocks & commodities, no key)

    private func fetchYahoo(ticker: String) async {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=1d"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

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
        } catch {
            NSLog("Yahoo Finance error for \(ticker): \(error.localizedDescription)")
        }
    }
}
