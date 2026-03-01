//
//  TranslationView.swift
//  boringNotch
//
//  Displays translation results inside the open notch.
//

import Defaults
import SwiftUI

struct TranslationView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var translationManager = TranslationManager.shared
    @Default(.useLiquidGlass) var useLiquidGlass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
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
                    translationManager.dismiss()
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

            if translationManager.result.error == nil {
                HStack(spacing: 6) {
                    Text(translationManager.result.sourceLang)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    Text(translationManager.result.targetLang)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text("Translation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            if !translationManager.result.translatedText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translationManager.result.translatedText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy translation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        if let error = translationManager.result.error {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "text.cursor")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Text("Select text and copy (⌘C), then press the shortcut")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    translationSection(
                        label: "ORIGINAL",
                        text: translationManager.result.sourceText,
                        style: .secondary
                    )

                    Divider().background(Color.white.opacity(0.1))

                    if translationManager.result.isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Translating...")
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                        }
                        .padding(.vertical, 8)
                    } else {
                        translationSection(
                            label: "TRANSLATION",
                            text: translationManager.result.translatedText,
                            style: .primary
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private enum TextStyle { case primary, secondary }

    private func translationSection(label: String, text: String, style: TextStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray.opacity(0.6))
            Text(text)
                .font(.system(size: style == .primary ? 13 : 12, weight: style == .primary ? .medium : .regular))
                .foregroundStyle(style == .primary ? .white : .white.opacity(0.75))
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
