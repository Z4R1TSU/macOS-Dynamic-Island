//
//  DynamicDropView.swift
//  boringNotch
//
//  Three drop targets: AirDrop, DynaClip (with folder picker), Drop (shelf staging).
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct DynamicDropView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var clipManager = DynaClipManager.shared
    @Default(.useLiquidGlass) var useLiquidGlass

    @State private var airdropTargeted = false
    @State private var clipTargeted = false
    @State private var shelfTargeted = false
    @State private var droppedMessage: String?
    @State private var showFolderPicker = false
    @State private var pendingClipProviders: [NSItemProvider] = []

    private let supportedTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    var body: some View {
        VStack(spacing: 0) {
            if let msg = droppedMessage {
                confirmationBanner(msg)
            } else if showFolderPicker {
                folderPickerView
            } else {
                dropTargetsRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Targets Row

    private var dropTargetsRow: some View {
        HStack(spacing: 10) {
            DropTargetCard(
                icon: "antenna.radiowaves.left.and.right",
                label: "AirDrop",
                isTargeted: airdropTargeted,
                useLiquidGlass: useLiquidGlass,
                supportedTypes: supportedTypes,
                isTargetedBinding: $airdropTargeted
            ) { providers in
                handleAirDrop(providers)
            }

            DropTargetCard(
                icon: "folder.fill",
                label: "DynaClip",
                isTargeted: clipTargeted,
                useLiquidGlass: useLiquidGlass,
                supportedTypes: supportedTypes,
                isTargetedBinding: $clipTargeted
            ) { providers in
                handleClipDrop(providers)
            }

            DropTargetCard(
                icon: "tray.and.arrow.down.fill",
                label: "Drop",
                isTargeted: shelfTargeted,
                useLiquidGlass: useLiquidGlass,
                supportedTypes: supportedTypes,
                isTargetedBinding: $shelfTargeted
            ) { providers in
                handleShelfDrop(providers)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Folder Picker (shown after DynaClip drop)

    private var folderPickerView: some View {
        VStack(spacing: 8) {
            Text("Save to folder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(clipManager.pinnedFolders, id: \.self) { folder in
                        Button {
                            saveToFolder(folder)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(folder.lastPathComponent)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .frame(width: 72, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(useLiquidGlass ? 0.12 : 0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        pickCustomFolder()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Other…")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Confirmation

    private func confirmationBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Drop Handlers

    private func handleAirDrop(_ providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        extractURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: urls)
            }
            showConfirmation("Sent via AirDrop")
        }
        return true
    }

    private func handleClipDrop(_ providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        pendingClipProviders = providers
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showFolderPicker = true
        }
        return true
    }

    private func handleShelfDrop(_ providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        showConfirmation("Added to Drop")
        return true
    }

    // MARK: - Folder Actions

    private func saveToFolder(_ folder: URL) {
        extractURLs(from: pendingClipProviders) { urls in
            guard !urls.isEmpty else { return }
            let fm = FileManager.default
            for url in urls {
                let dest = folder.appendingPathComponent(url.lastPathComponent)
                try? fm.copyItem(at: url, to: dest)
            }
            clipManager.loadDirectory()
            showConfirmation("Saved to \(folder.lastPathComponent)")
        }
        pendingClipProviders = []
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.level = .screenSaver + 1
        if panel.runModal() == .OK, let url = panel.url {
            saveToFolder(url)
        }
    }

    // MARK: - Helpers

    private func extractURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let fileURL = await provider.extractFileURL() {
                    urls.append(fileURL)
                } else if let url = await provider.extractURL(), url.isFileURL {
                    urls.append(url)
                }
            }
            await MainActor.run {
                completion(urls)
            }
        }
    }

    private func showConfirmation(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            droppedMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                vm.close()
            }
        }
    }
}

// MARK: - Drop Target Card (extracted subview for performance)

private struct DropTargetCard: View {
    let icon: String
    let label: String
    let isTargeted: Bool
    let useLiquidGlass: Bool
    let supportedTypes: [UTType]
    @Binding var isTargetedBinding: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isTargeted ? .white : .gray)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isTargeted ? .white : .gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted
                      ? Color.white.opacity(useLiquidGlass ? 0.2 : 0.15)
                      : Color.white.opacity(useLiquidGlass ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isTargeted ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .onDrop(of: supportedTypes, isTargeted: $isTargetedBinding) { providers in
            onDrop(providers)
        }
    }
}
