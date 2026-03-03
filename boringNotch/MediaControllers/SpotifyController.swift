//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class SpotifyController: MediaControllerProtocol {
    func setFavorite(_ favorite: Bool) async {
        //Placeholder
    }
    
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { false }

    private var notificationTask: Task<Void, Never>?
    
    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await notification in notifications {
                await self?.handleSpotifyNotification(notification)
            }
        }
    }

    private func handleSpotifyNotification(_ notification: Notification) async {
        guard let userInfo = notification.userInfo else {
            await updatePlaybackInfo()
            return
        }

        let playerState = userInfo["Player State"] as? String ?? "Stopped"
        let trackName = userInfo["Name"] as? String ?? ""
        let artistName = userInfo["Artist"] as? String ?? ""
        let albumName = userInfo["Album"] as? String ?? ""
        let duration = (userInfo["Duration"] as? Double ?? 0) / 1000.0
        let playbackPosition = userInfo["Playback Position"] as? Double ?? 0
        let isPlaying = playerState == "Playing"
        
        // If the track changed, we update immediately to show correct info
        // and avoid showing old song data while waiting for AppleScript
        if trackName != playbackState.title || artistName != playbackState.artist || isPlaying != playbackState.isPlaying {
             var newState = playbackState
             newState.isPlaying = isPlaying
             newState.title = trackName
             newState.artist = artistName
             newState.album = albumName
             newState.duration = duration
             newState.currentTime = playbackPosition
             newState.lastUpdated = Date()
             
             // Reset artwork if track changed
             if trackName != playbackState.title {
                 newState.artwork = nil
                 lastArtworkURL = nil
                 artworkFetchTask?.cancel()
             }
             
             self.playbackState = newState
        }
        
        // Fetch full info (including artwork URL) via AppleScript
        // We delay slightly to allow Spotify internal state to catch up with notification
        try? await Task.sleep(for: .milliseconds(100))
        await updatePlaybackInfo()
        
        // Retry if artwork is missing or title mismatch (likely due to stale AS data)
        if playbackState.artwork == nil && !trackName.isEmpty {
             try? await Task.sleep(for: .milliseconds(500))
             await updatePlaybackInfo()
        }
    }
    
    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }
    
    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }
    
    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 10 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        // Check for stale data from AppleScript if we recently updated from notification
        if abs(playbackState.lastUpdated.timeIntervalSinceNow) < 2.0 && (currentTrack != playbackState.title || isPlaying != playbackState.isPlaying) {
            return
        }
        
        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )

        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        playbackState = state

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()
            
            // Update lastArtworkURL to mark this request as current
            lastArtworkURL = artworkURL

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        // Ensure we are still tracking the same artwork URL
                        if self.lastArtworkURL == artworkURL {
                            var updatedState = self.playbackState
                            updatedState.artwork = data
                            self.playbackState = updatedState
                            self.artworkFetchTask = nil
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }
    
// MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
}
