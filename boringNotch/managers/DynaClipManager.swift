//
//  DynaClipManager.swift
//  boringNotch
//
//  Mini Finder file browser manager. Lists directory contents,
//  navigates folders, and manages pinned folder tabs.
//

import AppKit
import Defaults
import SwiftUI

struct DynaClipItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let icon: NSImage
    let isDirectory: Bool

    static func == (lhs: DynaClipItem, rhs: DynaClipItem) -> Bool {
        lhs.url == rhs.url
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

@MainActor
class DynaClipManager: ObservableObject {
    static let shared = DynaClipManager()

    @Published var currentDirectory: URL
    @Published var items: [DynaClipItem] = []
    @Published var searchQuery: String = ""
    @Published var isGridView: Bool = true

    private var navigationStack: [URL] = []
    private var forwardStack: [URL] = []

    var pinnedFolders: [URL] {
        get {
            Defaults[.pinnedClipFolders].compactMap { path in
                let expanded = NSString(string: path).expandingTildeInPath
                return URL(fileURLWithPath: expanded)
            }
        }
        set {
            Defaults[.pinnedClipFolders] = newValue.map { $0.path }
            objectWillChange.send()
        }
    }

    var filteredItems: [DynaClipItem] {
        if searchQuery.isEmpty { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var canGoBack: Bool { !navigationStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var breadcrumb: String {
        currentDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private init() {
        let desktopPath = NSString(string: "~/Desktop").expandingTildeInPath
        currentDirectory = URL(fileURLWithPath: desktopPath)

        // Ensure Desktop is pinned by default
        if Defaults[.pinnedClipFolders].isEmpty {
            Defaults[.pinnedClipFolders] = ["~/Desktop"]
        }

        loadDirectory()
    }

    func loadDirectory() {
        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey, .effectiveIconKey], options: [.skipsHiddenFiles])
            items = urls.sorted { lhs, rhs in
                let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if lhsDir != rhsDir { return lhsDir }
                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }.map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                return DynaClipItem(id: url.absoluteString, url: url, name: url.lastPathComponent, icon: icon, isDirectory: isDir)
            }
        } catch {
            items = []
        }
    }

    func navigate(to url: URL) {
        navigationStack.append(currentDirectory)
        forwardStack.removeAll()
        currentDirectory = url
        searchQuery = ""
        loadDirectory()
    }

    func goBack() {
        guard let prev = navigationStack.popLast() else { return }
        forwardStack.append(currentDirectory)
        currentDirectory = prev
        searchQuery = ""
        loadDirectory()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        navigationStack.append(currentDirectory)
        currentDirectory = next
        searchQuery = ""
        loadDirectory()
    }

    func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func addPinnedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            var current = pinnedFolders
            if !current.contains(url) {
                current.append(url)
                pinnedFolders = current
            }
            navigate(to: url)
        }
    }

    func removePinnedFolder(_ url: URL) {
        var current = pinnedFolders
        current.removeAll { $0 == url }
        if current.isEmpty {
            let desktopPath = NSString(string: "~/Desktop").expandingTildeInPath
            current = [URL(fileURLWithPath: desktopPath)]
        }
        pinnedFolders = current
        if currentDirectory == url {
            navigate(to: current.first!)
        }
    }

    func copyFilesToClipFolder(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            let dest = currentDirectory.appendingPathComponent(url.lastPathComponent)
            try? fm.copyItem(at: url, to: dest)
        }
        loadDirectory()
    }
}
