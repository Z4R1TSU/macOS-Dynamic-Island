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
    private var accessedURLs: Set<URL> = []

    var pinnedFolders: [URL] {
        get {
            Defaults[.pinnedClipFolders].compactMap { path in
                let expanded = NSString(string: path).expandingTildeInPath
                return URL(fileURLWithPath: expanded)
            }
        }
        set {
            Defaults[.pinnedClipFolders] = newValue.map { url in
                url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
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
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        currentDirectory = desktopURL

        if Defaults[.pinnedClipFolders].isEmpty {
            Defaults[.pinnedClipFolders] = ["~/Desktop"]
        }

        restoreBookmarks()
        promptForDesktopAccessIfNeeded()
        loadDirectory()
    }

    private func promptForDesktopAccessIfNeeded() {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")

        let store = loadBookmarkStore()
        let hasDesktopBookmark = store.keys.contains(where: { path in
            URL(fileURLWithPath: path).standardized == desktopURL.standardized
        })
        if hasDesktopBookmark { return }

        let fm = FileManager.default
        let canRead = fm.isReadableFile(atPath: desktopURL.path)
        if canRead {
            let testContents = try? fm.contentsOfDirectory(atPath: desktopURL.path)
            if testContents != nil && !(testContents?.isEmpty ?? true) {
                saveBookmark(for: desktopURL)
                return
            }
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = desktopURL
        panel.prompt = "Grant Access"
        panel.message = "DynaClip needs access to your Desktop folder to display files."
        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            currentDirectory = url.standardized
            let tilded = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            var pinned = Defaults[.pinnedClipFolders]
            if !pinned.contains(tilded) {
                pinned.insert(tilded, at: 0)
                Defaults[.pinnedClipFolders] = pinned
            }
        }
    }

    func loadDirectory() {
        let fm = FileManager.default
        let dir = currentDirectory.standardized

        let bookmarkURL = resolveBookmarkedURL(for: dir)
        let didAccess = bookmarkURL?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { bookmarkURL?.stopAccessingSecurityScopedResource() } }

        do {
            let urls = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
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

    /// Finds the closest ancestor bookmark URL for a given directory, so that
    /// `startAccessingSecurityScopedResource()` grants access to subdirectories too.
    private func resolveBookmarkedURL(for dir: URL) -> URL? {
        if accessedURLs.contains(dir.standardized) { return dir }

        let store = loadBookmarkStore()
        var candidate: URL?
        for (path, data) in store {
            let storedURL = URL(fileURLWithPath: path).standardized
            if dir.standardized.path.hasPrefix(storedURL.path) {
                if candidate == nil || storedURL.path.count > candidate!.path.count {
                    var isStale = false
                    if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                               relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        candidate = resolved
                    }
                }
            }
        }
        return candidate
    }

    func navigate(to url: URL) {
        navigationStack.append(currentDirectory)
        forwardStack.removeAll()
        currentDirectory = url.standardized
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
            saveBookmark(for: url)

            var current = pinnedFolders
            let standardized = url.standardized
            if !current.contains(where: { $0.standardized == standardized }) {
                current.append(url)
                pinnedFolders = current
            }
            navigate(to: url)
        }
    }

    func removePinnedFolder(_ url: URL) {
        var current = pinnedFolders
        current.removeAll { $0.standardized == url.standardized }
        if current.isEmpty {
            let desktopPath = NSString(string: "~/Desktop").expandingTildeInPath
            current = [URL(fileURLWithPath: desktopPath)]
        }
        pinnedFolders = current
        removeBookmark(for: url)
        if currentDirectory.standardized == url.standardized {
            navigate(to: current.first!)
        }
    }

    func copyFilesToClipFolder(_ urls: [URL], destination: URL? = nil) {
        let target = destination ?? currentDirectory
        let fm = FileManager.default
        let bookmarkURL = resolveBookmarkedURL(for: target.standardized)
        let didAccess = bookmarkURL?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { bookmarkURL?.stopAccessingSecurityScopedResource() } }
        for url in urls {
            let dest = target.appendingPathComponent(url.lastPathComponent)
            try? fm.copyItem(at: url, to: dest)
        }
        if target.standardized == currentDirectory.standardized {
            loadDirectory()
        }
    }

    // MARK: - Security-Scoped Bookmarks

    private var bookmarkStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("boringNotch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("FolderBookmarks.plist")
    }

    private func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var store = loadBookmarkStore()
        store[url.path] = data
        saveBookmarkStore(store)
    }

    private func removeBookmark(for url: URL) {
        var store = loadBookmarkStore()
        store.removeValue(forKey: url.path)
        saveBookmarkStore(store)
    }

    private func restoreBookmarks() {
        let store = loadBookmarkStore()
        for (_, data) in store {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.insert(url)
            }
        }
    }

    private func loadBookmarkStore() -> [String: Data] {
        guard let data = try? Data(contentsOf: bookmarkStoreURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data] else {
            return [:]
        }
        return dict
    }

    private func saveBookmarkStore(_ store: [String: Data]) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: store,
            format: .binary,
            options: 0
        ) else { return }
        try? data.write(to: bookmarkStoreURL)
    }
}
