//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var isLoadingArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    // Add state to track if we've already shown "No lyrics found" for the current song
    @Published var hasShownNoLyrics: Bool = false
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        // Always prefer NowPlaying for auto-detection of any playing app
        let controllerType: MediaControllerType = .nowPlaying

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else {
            // Fallback chain: try user preference, then Apple Music
            let fallbackType = Defaults[.mediaController]
            if fallbackType != .nowPlaying, let controller = createController(for: fallbackType) {
                setActiveController(controller)
            } else if let fallbackController = createController(for: .appleMusic) {
                setActiveController(fallbackController)
            }
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
            }
            // Update idle state separately (might trigger async tasks)
            self.updateIdleState(state: state.isPlaying)

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.isLoadingArtwork = false
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                if !self.usingAppIconForArtwork {
                    self.isLoadingArtwork = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.isLoadingArtwork else { return }
                    if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                        self.usingAppIconForArtwork = true
                        self.isLoadingArtwork = false
                        self.updateAlbumArt(newAlbumArt: appIconImage)
                    }
                }
            } else if (titleChanged || artistChanged || albumChanged) && !artworkChanged {
                self.isLoadingArtwork = true
                self.calculateAverageColor()
            }

            if artworkChanged {
                self.artworkData = state.artwork
            } else if state.artwork == nil {
                self.artworkData = nil
            }

            // Always update last artwork values on content change so the next
            // diff comparison works correctly even when artwork arrives later.
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist, album: state.album, duration: state.duration)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String, album: String, duration: Double) {
        // Reset hasShownNoLyrics when fetching new song
        if title != songTitle || artist != artistName {
             DispatchQueue.main.async {
                 self.hasShownNoLyrics = false
             }
        }
        
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
            }
            return
        }

        // Prefer native Apple Music lyrics when available
        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist, album: album, duration: duration)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue, !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {
                    // fall through to web lookup
                }
                await self.fetchLyricsFromWeb(title: title, artist: artist, album: album, duration: duration)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist, album: album, duration: duration)
            }
        }
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String, album: String, duration: Double) async {
        guard let result = await LyricsManager.shared.fetchLyrics(title: title, artist: artist, album: album, duration: duration) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            self.syncedLyrics = []
            return
        }
        
        self.currentLyrics = result.plainLyrics
        self.isFetchingLyrics = false
        if !result.syncedLyrics.isEmpty {
            self.syncedLyrics = self.parseLRC(result.syncedLyrics)
        } else {
            self.syncedLyrics = []
        }
    }

    // MARK: - Synced lyrics helpers
    
    private static let lrcRegex: NSRegularExpression? = {
        // Match [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
        // Allow 1-3 digits for fractional seconds
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        guard let regex = Self.lrcRegex else { return [] }
        
        let lines = lrc.split(separator: "\n")
        var globalOffset: Double = 0
        
        // Check for global offset tag [offset: +/-ms]
        for lineSub in lines {
            let line = String(lineSub).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[offset:") {
                if let endIdx = line.firstIndex(of: "]") {
                    let startIdx = line.index(line.startIndex, offsetBy: 8) // "[offset:".count
                    let offsetStr = String(line[startIdx..<endIdx])
                    if let val = Double(offsetStr) {
                        // Offset is in milliseconds. Positive value shifts timestamps later.
                        globalOffset = val / 1000.0
                    }
                }
            }
        }
        
        lines.forEach { lineSub in
            let line = String(lineSub)
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                
                var fractional: Double = 0
                if csRange.location != NSNotFound {
                    let fracStr = nsLine.substring(with: csRange)
                    if let val = Double(fracStr) {
                        // Adjust divisor based on number of digits
                        // 2 digits (standard) -> 100 (hundredths)
                        // 3 digits -> 1000 (milliseconds)
                        // 1 digit -> 10 (tenths)
                        let divisor = pow(10.0, Double(fracStr.count))
                        fractional = val / divisor
                    }
                }
                
                let time = minutes * 60 + seconds + fractional + globalOffset
                let textStart = match.range.location + match.range.length
                let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append((time, text))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        
        // Add a small positive offset to elapsed time to ensure better sync
        // Often system latency causes visual lyrics to lag slightly behind audio
        let compensatedElapsed = elapsed + 0.25
        
        // Binary search for last line with time <= elapsed
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = -1
        
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= compensatedElapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        // If before first lyric, show nothing or maybe title?
        // Let's stick to showing nothing if it's really early, or the first line if close enough?
        // Existing logic returned syncedLyrics[0] if idx was 0 (default).
        // If idx is -1 (nothing found), it means we are before the first timestamp.
        
        if idx == -1 {
            // Before first line: return a special marker or empty?
            // The UI will handle "PRELUDE_MARKER" to show music notes
            return "PRELUDE_MARKER"
        }
        
        return syncedLyrics[idx].text
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.isLoadingArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        // Cancel any existing idle task first
        debounceIdleTask?.cancel()
        
        if state {
            // Playing
            isPlayerIdle = false
        } else {
            // Paused
            debounceIdleTask = Task { [weak self] in
                // Wait for a few seconds before marking as idle/collapsing
                try? await Task.sleep(for: .seconds(5)) 
                guard let self = self else { return }
                
                // Only collapse if still paused
                if !self.isPlaying {
                    await MainActor.run {
                        withAnimation(.smooth) {
                            self.isPlayerIdle = true
                            
                            // Also ensure the expanding view is closed if it was music
                            if self.coordinator.expandingView.type == .music && self.coordinator.expandingView.show {
                                self.coordinator.toggleExpandingView(status: false, type: .music)
                            }
                        }
                    }
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            self.calculateAverageColor()
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        // Music sneak peek / expanding view on song change is disabled.
        // Other sneak peek types (volume, brightness, etc.) remain active.
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
            forceUpdate()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
            // Slight delay to allow system to process the skip
            try? await Task.sleep(for: .milliseconds(150))
            forceUpdate()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
            try? await Task.sleep(for: .milliseconds(150))
            forceUpdate()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
            // Immediately update UI state locally if possible, but force fetch is safer
            try? await Task.sleep(for: .milliseconds(100))
            forceUpdate()
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
// MARK: - Lyrics Manager Implementation

struct LyricsResult {
    let plainLyrics: String
    let syncedLyrics: String
    let source: String
}

protocol LyricsProvider {
    var name: String { get }
    var priority: Int { get } // Higher is better
    func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult?
}

class LyricsManager {
    static let shared = LyricsManager()
    
    private let providers: [LyricsProvider] = [
        QQMusicLyricsProvider(),
        NetEaseLyricsProvider(),
        LRCLibLyricsProvider()
    ]
    
    func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        // Create tasks for all providers
        let tasks = providers.map { provider in
            Task {
                await provider.fetchLyrics(title: title, artist: artist, album: album, duration: duration)
            }
        }
        
        // Wait for all tasks to complete
        var results: [LyricsResult] = []
        for task in tasks {
            if let result = await task.value {
                results.append(result)
            }
        }
        
        // Sort results by provider priority
        // We can map back to provider priority based on source name or just store priority in result
        // Let's rely on the provider order or add priority to result.
        // But since providers list is static, we can look up priority.
        
        let sortedResults = results.sorted { r1, r2 in
            let p1 = providers.first(where: { $0.name == r1.source })?.priority ?? 0
            let p2 = providers.first(where: { $0.name == r2.source })?.priority ?? 0
            return p1 > p2
        }
        
        return sortedResults.first
    }
    
    // Helper to normalize strings for comparison
    static func normalize(_ string: String) -> String {
        string.folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Providers

class QQMusicLyricsProvider: LyricsProvider {
    var name: String { "QQMusic" }
    var priority: Int { 7 }
    
    func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        let cleanTitle = LyricsManager.normalize(title)
        let cleanArtist = LyricsManager.normalize(artist)
        
        // QQ Music Search
        // URL: https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w={keyword}&t=0&n=5&p=1&format=json
        guard let encodedQuery = "\(cleanTitle) \(cleanArtist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=\(encodedQuery)&t=0&n=5&p=1&format=json") else {
            return nil
        }
        
        var request = URLRequest(url: searchUrl)
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Referer")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let songObj = dataObj["song"] as? [String: Any],
                  let list = songObj["list"] as? [[String: Any]],
                  !list.isEmpty else {
                return nil
            }
            
            // Find best match
            let bestMatch = findBestMatch(candidates: list, album: album, duration: duration)
            guard let songmid = bestMatch["songmid"] as? String else { return nil }
            
            // Fetch Lyrics
            // URL: https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid={songmid}&format=json&nobase64=1
            guard let lyricsUrl = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songmid)&format=json&nobase64=1") else {
                return nil
            }
            
            var lyricsRequest = URLRequest(url: lyricsUrl)
            lyricsRequest.setValue("https://y.qq.com", forHTTPHeaderField: "Referer")
            
            let (lyricsData, _) = try await URLSession.shared.data(for: lyricsRequest)
            guard let lyricsJson = try JSONSerialization.jsonObject(with: lyricsData) as? [String: Any],
                  let lyric = lyricsJson["lyric"] as? String else {
                return nil
            }
            
            // QQ Music lyrics often contain HTML entities like &#10; or are just plain text
            // In the curl test, it returned clean text, but let's be safe.
            // Also it returns full LRC content.
            
            // Sometimes it returns trans (translation) as well.
            let trans = lyricsJson["trans"] as? String ?? ""
            
            return LyricsResult(plainLyrics: lyric, syncedLyrics: lyric, source: name)
            
        } catch {
            return nil
        }
    }
    
    private func findBestMatch(candidates: [[String: Any]], album: String, duration: Double) -> [String: Any] {
        // Filter by duration if available (QQ Music 'interval' is in seconds)
        let validCandidates = candidates.filter { candidate in
            guard duration > 0, let interval = candidate["interval"] as? Int else { return true }
            return abs(Double(interval) - duration) < 5.0
        }
        
        if validCandidates.isEmpty {
            // If no duration match, fallback to all candidates (maybe duration is wrong)
            return candidates.first!
        }
        
        // Try to match album
        if !album.isEmpty, let albumMatch = validCandidates.first(where: { candidate in
            guard let albumName = candidate["albumname"] as? String else { return false }
            return albumName.localizedCaseInsensitiveContains(album) || album.localizedCaseInsensitiveContains(albumName)
        }) {
            return albumMatch
        }
        
        return validCandidates.first!
    }
}

class NetEaseLyricsProvider: LyricsProvider {
    var name: String { "NetEase" }
    var priority: Int { 10 }
    
    func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        let cleanTitle = LyricsManager.normalize(title)
        let cleanArtist = LyricsManager.normalize(artist)
        
        // NetEase Search
        // URL: http://music.163.com/api/search/get/web?s={keyword}&type=1&offset=0&total=true&limit=5
        guard let encodedQuery = "\(cleanTitle) \(cleanArtist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "http://music.163.com/api/search/get/web?s=\(encodedQuery)&type=1&offset=0&total=true&limit=5") else {
            return nil
        }
        
        var request = URLRequest(url: searchUrl)
        request.setValue("http://music.163.com", forHTTPHeaderField: "Referer")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]],
                  !songs.isEmpty else {
                return nil
            }
            
            // Find best match
            let bestMatch = findBestMatch(candidates: songs, album: album, duration: duration)
            guard let id = bestMatch["id"] as? Int else { return nil }
            
            // Fetch Lyrics
            // URL: http://music.163.com/api/song/lyric?os=pc&id={id}&lv=-1&kv=-1&tv=-1
            guard let lyricsUrl = URL(string: "http://music.163.com/api/song/lyric?os=pc&id=\(id)&lv=-1&kv=-1&tv=-1") else {
                return nil
            }
            
            var lyricsRequest = URLRequest(url: lyricsUrl)
            lyricsRequest.setValue("http://music.163.com", forHTTPHeaderField: "Referer")
            
            let (lyricsData, _) = try await URLSession.shared.data(for: lyricsRequest)
            guard let lyricsJson = try JSONSerialization.jsonObject(with: lyricsData) as? [String: Any],
                  let lrc = lyricsJson["lrc"] as? [String: Any],
                  let lyric = lrc["lyric"] as? String else {
                return nil
            }
            
            return LyricsResult(plainLyrics: lyric, syncedLyrics: lyric, source: name)
            
        } catch {
            return nil
        }
    }
    
    private func findBestMatch(candidates: [[String: Any]], album: String, duration: Double) -> [String: Any] {
        // Filter by duration if available (NetEase 'duration' is in milliseconds)
        let validCandidates = candidates.filter { candidate in
            guard duration > 0, let trackDuration = candidate["duration"] as? Int else { return true }
            return abs(Double(trackDuration)/1000.0 - duration) < 5.0
        }
        
        if validCandidates.isEmpty {
            return candidates.first!
        }
        
        // Try to match album
        if !album.isEmpty, let albumMatch = validCandidates.first(where: { candidate in
            guard let albumObj = candidate["album"] as? [String: Any],
                  let albumName = albumObj["name"] as? String else { return false }
            return albumName.localizedCaseInsensitiveContains(album) || album.localizedCaseInsensitiveContains(albumName)
        }) {
            return albumMatch
        }
        
        return validCandidates.first!
    }
}

class LRCLibLyricsProvider: LyricsProvider {
    var name: String { "LRCLib" }
    var priority: Int { 5 }
    
    func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        let cleanTitle = LyricsManager.normalize(title)
        let cleanArtist = LyricsManager.normalize(artist)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !jsonArray.isEmpty else {
                return nil
            }
            
            // Find best match logic (reused from previous implementation)
            var selectedTrack: [String: Any]? = nil
            
            let validCandidates = jsonArray.filter { track in
                guard duration > 0, let trackDuration = track["duration"] as? Double else { return true }
                return abs(trackDuration - duration) < 3.0
            }
            
            if !validCandidates.isEmpty {
                if !album.isEmpty, let albumMatch = validCandidates.first(where: { track in
                    guard let trackAlbum = track["albumName"] as? String else { return false }
                    return trackAlbum.localizedCaseInsensitiveContains(album) || album.localizedCaseInsensitiveContains(trackAlbum)
                }) {
                    selectedTrack = albumMatch
                } else {
                    if let syncedMatch = validCandidates.first(where: { ($0["syncedLyrics"] as? String)?.isEmpty == false }) {
                        selectedTrack = syncedMatch
                    } else {
                        selectedTrack = validCandidates.first
                    }
                }
            } else {
                var minDiff: Double = Double.greatestFiniteMagnitude
                for track in jsonArray {
                    if let trackDuration = track["duration"] as? Double {
                        let diff = abs(trackDuration - duration)
                        if diff < minDiff {
                            minDiff = diff
                            selectedTrack = track
                        }
                    }
                }
                if selectedTrack == nil {
                    selectedTrack = jsonArray.first
                }
            }
            
            guard let finalTrack = selectedTrack else { return nil }
            
            let plain = (finalTrack["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let synced = (finalTrack["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = plain.isEmpty ? synced : plain
            
            if resolved.isEmpty { return nil }
            
            return LyricsResult(plainLyrics: resolved, syncedLyrics: synced, source: name)
            
        } catch {
            return nil
        }
    }
}
