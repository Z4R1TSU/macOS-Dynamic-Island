//
//  BluetoothExpandedView.swift
//  boringNotch
//
//  Expanding view for Bluetooth device connect/disconnect notifications.
//

import SwiftUI

struct BluetoothExpandedView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var bluetooth = BluetoothManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: bluetooth.lastDeviceIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text(bluetooth.lastDeviceConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)

            Rectangle()
                .fill(.clear)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(bluetooth.lastDeviceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
