//
//  NotificationBannerView.swift
//  boringNotch
//
//  Displays intercepted macOS notifications within the notch area.
//

import SwiftUI
import Defaults

struct NotificationBannerView: View {
    @ObservedObject var notificationManager = UserNotificationManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        if let notification = notificationManager.currentNotification {
            HStack(spacing: 10) {
                if let icon = notification.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notification.appName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.gray)
                        Spacer()
                        Text("now")
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.7))
                    }

                    Text(notification.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct NotificationClosedView: View {
    @ObservedObject var notificationManager = UserNotificationManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        if let notification = notificationManager.currentNotification {
            HStack(spacing: 8) {
                if let icon = notification.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: max(0, vm.effectiveClosedNotchHeight - 12),
                            height: max(0, vm.effectiveClosedNotchHeight - 12)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(notification.body)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12) + 60,
                    alignment: .leading
                )
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
