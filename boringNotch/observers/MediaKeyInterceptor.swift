//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()
    
    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    // MARK: - Accessibility (via XPC)
    
    func requestAccessibilityAuthorization() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }
    
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }
    
    // MARK: - Event Tap
    
    func start(promptIfNeeded: Bool = false) async {
        guard eventTap == nil else { return }
        
        // Ensure HUD replacement is enabled or we force start it for passive listening
        // guard Defaults[.hudReplacement] else {
        //     stop()
        //     return
        // }
        
        // Check accessibility authorization
        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else { return }
            } else {
                return
            }
        }
        
        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleEvent(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Ensure the CGEvent has a valid type before converting to NSEvent
        guard cgEvent.type != .null else {
            return Unmanaged.passRetained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        
        // 0xA = key down, 0xB = key up. Only handle key down.
        guard stateByte == 0xA,
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        
        // Handle option key action (without shift)
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }
        
        // Handle normal key press
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        
        // If HUD replacement is enabled, consume the event (return nil)
        // If disabled, pass it through (return event) so system HUD shows too
        if Defaults[.hudReplacement] {
            return nil
        } else {
            return Unmanaged.passRetained(cgEvent)
        }
    }
    
    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }
    
    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                print("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            print("⚠️ [MediaKeyInterceptor] No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound from: \(url.path)")
        } else {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound (no url available for AVAudioPlayer)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        
        // If HUD replacement is disabled, we don't want to actually change the volume/brightness ourselves
        // because the system will do it when we pass the event through.
        // We only want to SHOW the HUD (visual feedback).
        // However, `handleKeyPress` currently calls VolumeManager.shared.increase/decrease which does BOTH (change + show).
        
        if Defaults[.hudReplacement] {
            switch keyType {
            case .soundUp:
                Task { @MainActor in
                    self.playFeedbackSound()
                    VolumeManager.shared.increase(stepDivisor: stepDivisor)
                }
            case .soundDown:
                Task { @MainActor in
                    self.playFeedbackSound()
                    VolumeManager.shared.decrease(stepDivisor: stepDivisor)
                }
            case .mute:
                Task { @MainActor in
                    VolumeManager.shared.toggleMuteAction()
                }
            case .brightnessUp, .keyboardBrightnessUp:
                let delta = step / stepDivisor
                adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
            case .brightnessDown, .keyboardBrightnessDown:
                let delta = -(step / stepDivisor)
                adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
            }
        } else {
            // HUD Replacement OFF: System handles the change. We just want to show the HUD.
            // But we need to know the NEW value to show it.
            // VolumeManager has a listener, so it will detect the change automatically and show HUD (since we fixed that).
            // So for Volume, we do NOTHING here.
            
            // For Brightness, we don't have a listener.
            // So we must manually show the HUD, but with what value?
            // We can read the current value and guess the new value, or wait a bit and read?
            // Or just show the current value + delta?
            // But system handles delta.
            
            // If we assume system behaves same as us (step 1/16), we can predict.
            // Let's try to just trigger a read-and-show for brightness.
            
            switch keyType {
            case .soundUp, .soundDown, .mute:
                // Do nothing, VolumeManager listener handles it.
                break
            case .brightnessUp, .brightnessDown:
                Task { @MainActor in
                    if command {
                        try? await Task.sleep(for: .milliseconds(100))
                        KeyboardBacklightManager.shared.refresh()
                        let v = await XPCHelperClient.shared.currentKeyboardBrightness() ?? KeyboardBacklightManager.shared.rawBrightness
                        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, duration: 2.5, value: CGFloat(v))
                    } else {
                        try? await Task.sleep(for: .milliseconds(100))
                        BrightnessManager.shared.refresh()
                        let v = await XPCHelperClient.shared.currentScreenBrightness() ?? BrightnessManager.shared.rawBrightness
                        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, duration: 2.5, value: CGFloat(v))
                    }
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    KeyboardBacklightManager.shared.refresh()
                    let v = await XPCHelperClient.shared.currentKeyboardBrightness() ?? KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, duration: 2.5, value: CGFloat(v))
                }
            }
        }
    }
    
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }
    
    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }
    
    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String
        
        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }
        
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
