//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineHUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    
    private var sideWidth: CGFloat {
        if type == .bluetooth || type == .unlock || type == .lock {
            return 40 - (hoverAnimation ? 0 : 6) + gestureProgress / 2
        }
        return 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                Image(systemName: SpeakerSymbol(value))
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Image(systemName: BrightnessSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .backlight:
                            Image(systemName: value > 0.5 ? "light.max" : "light.min")
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .bluetooth:
                            Image(systemName: icon.isEmpty ? "airpods" : icon)
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .lock:
                            Image(systemName: "lock.fill")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .unlock:
                            Image(systemName: "lock.open.fill")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        default:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                if type == .bluetooth {
                    // No text for bluetooth, just icon
                } else if type == .unlock || type == .lock {
                    // No text for unlock/lock, just icon
                }
            }
            .frame(width: sideWidth, height: vm.notchSize.height - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)
            
            HStack {
                if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else if type == .bluetooth {
                     // Nothing on the right for bluetooth, or maybe battery level if available?
                     // For now just keep it empty or balanced
                } else if type == .unlock || type == .lock {
                    // Nothing on the right for unlock/lock
                } else {
                        HStack {
                        DraggableProgressBar(value: $value, onChange: { v in
                            if type == .volume {
                                VolumeManager.shared.setAbsolute(Float32(v))
                            } else if type == .brightness {
                                BrightnessManager.shared.setAbsolute(value: Float32(v))
                            }
                        })
                        if (type == .volume && value.isZero) {
                            // Mute icon removed to avoid duplication
                        } else if Defaults[.showClosedNotchHUDPercentage] {
                            Text("\(Int(value * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(.trailing, 4)
            .frame(width: sideWidth, height: vm.closedNotchSize.height - (hoverAnimation ? 0 : 12), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return "Brightness"
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel())
}
