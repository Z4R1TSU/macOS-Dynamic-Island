//
//  DynaClipView.swift
//  boringNotch
//
//  Mini Finder file browser for the notch.
//

import AppKit
import Defaults
import SwiftUI

struct DynaClipView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var clipManager = DynaClipManager.shared
    @Default(.useLiquidGlass) var useLiquidGlass
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().background(Color.white.opacity(0.1))
            fileGrid
            Divider().background(Color.white.opacity(0.1))
            bottomToolbar
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(clipManager.pinnedFolders, id: \.absoluteString) { folder in
                    let isActive = clipManager.currentDirectory.standardized == folder.standardized

                    Button {
                        clipManager.navigate(to: folder)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isActive ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(folder.lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isActive
                                      ? Color.white.opacity(useLiquidGlass ? 0.15 : 0.1)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(isActive ? .white : .gray)
                    .contextMenu {
                        if folder.lastPathComponent != "Desktop" {
                            Button("Remove Tab") {
                                clipManager.removePinnedFolder(folder)
                            }
                        }
                    }
                }

                Button {
                    clipManager.addPinnedFolder()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private var fileGrid: some View {
        ScrollView {
            let displayItems = clipManager.filteredItems
            if displayItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray.opacity(0.5))
                    Text(clipManager.searchQuery.isEmpty ? "Empty folder" : "No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(displayItems) { item in
                        fileCell(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func fileCell(_ item: DynaClipItem) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24)
        }
        .frame(width: 72)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.isDirectory {
                clipManager.navigate(to: item.url)
            } else {
                clipManager.openFile(item.url)
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            Button { clipManager.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(clipManager.canGoBack ? .white : .gray.opacity(0.4))
            .disabled(!clipManager.canGoBack)

            Button { clipManager.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(clipManager.canGoForward ? .white : .gray.opacity(0.4))
            .disabled(!clipManager.canGoForward)

            Text(clipManager.breadcrumb)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            if showSearch {
                TextField("Search", text: $clipManager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 100)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showSearch.toggle()
                    if !showSearch { clipManager.searchQuery = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(.gray)

            Button {
                clipManager.isGridView.toggle()
            } label: {
                Image(systemName: clipManager.isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
