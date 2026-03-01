//
//  TranslationManager.swift
//  boringNotch
//
//  Translates selected/clipboard text. Auto-detects CN<->EN direction.
//

import AppKit
import NaturalLanguage
import SwiftUI

struct TranslationResult {
    var sourceText: String = ""
    var translatedText: String = ""
    var sourceLang: String = ""
    var targetLang: String = ""
    var isLoading: Bool = false
    var error: String? = nil
}

@MainActor
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()

    @Published var result = TranslationResult()
    @Published var showTranslation = false

    private let maxChunkSize = 450

    private init() {}

    func translateSelectedText() {
        Task {
            let text = await captureText()

            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                result = TranslationResult(error: "No text found. Select text first, then press the shortcut.")
                showTranslation = true
                return
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let detected = detectLanguage(trimmed)
            let isChinese = detected == "zh" || detected == "zh-Hans" || detected == "zh-Hant"
            let sourceLang = isChinese ? "zh" : (detected ?? "en")
            let targetLang = isChinese ? "en" : "zh"

            result = TranslationResult(
                sourceText: trimmed,
                sourceLang: displayName(for: sourceLang),
                targetLang: displayName(for: targetLang),
                isLoading: true
            )
            showTranslation = true

            let translated = await performChunkedTranslation(text: trimmed, from: sourceLang, to: targetLang)
            result.translatedText = translated
            result.isLoading = false
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showTranslation = false
        }
    }

    // MARK: - Text Capture

    private func captureText() async -> String? {
        if let axText = getSelectedTextViaAX(), !axText.isEmpty {
            return axText
        }

        let before = NSPasteboard.general.changeCount
        simulateCopy()
        try? await Task.sleep(for: .milliseconds(200))
        let after = NSPasteboard.general.changeCount

        if after != before, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            return text
        }

        if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
            return clip
        }

        return nil
    }

    private func getSelectedTextViaAX() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success else {
            return nil
        }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func simulateCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Language

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func displayName(for code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "zh-Hant": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "es": return "Español"
        default: return code.uppercased()
        }
    }

    // MARK: - Chunked Translation

    private func performChunkedTranslation(text: String, from source: String, to target: String) async -> String {
        let chunks = splitIntoChunks(text, maxLength: maxChunkSize)
        var translatedChunks: [String] = []

        for chunk in chunks {
            let translated = await performTranslation(text: chunk, from: source, to: target)
            translatedChunks.append(translated)
        }

        return translatedChunks.joined()
    }

    private func splitIntoChunks(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var remaining = text

        while !remaining.isEmpty {
            if remaining.count <= maxLength {
                chunks.append(remaining)
                break
            }

            let endIndex = remaining.index(remaining.startIndex, offsetBy: maxLength)
            let searchRange = remaining.startIndex..<endIndex

            // Try to split at sentence boundaries first
            var splitIndex = endIndex
            let sentenceEnders: [Character] = [".", "。", "!", "！", "?", "？", "\n"]
            for char in sentenceEnders {
                if let idx = remaining[searchRange].lastIndex(of: char) {
                    let candidate = remaining.index(after: idx)
                    if candidate > remaining.startIndex {
                        splitIndex = candidate
                        break
                    }
                }
            }

            // Fall back to space if no sentence boundary found
            if splitIndex == endIndex, let spaceIdx = remaining[searchRange].lastIndex(of: " ") {
                splitIndex = remaining.index(after: spaceIdx)
            }

            chunks.append(String(remaining[remaining.startIndex..<splitIndex]))
            remaining = String(remaining[splitIndex...])
        }

        return chunks
    }

    private func performTranslation(text: String, from source: String, to target: String) async -> String {
        let s = langCode(source)
        let t = langCode(target)
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(s)|\(t)") else {
            return text
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rd = json["responseData"] as? [String: Any],
               let translated = rd["translatedText"] as? String {
                return translated
            }
        } catch {}
        return text
    }

    private func langCode(_ code: String) -> String {
        switch code {
        case "zh", "zh-Hans", "zh-Hant": return "zh-CN"
        default: return code
        }
    }
}
