//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    private var roundedTop: Bool

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil,
        roundedTop: Bool = false
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 11
        self.roundedTop = roundedTop
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if roundedTop {
            let indentedRect = CGRect(
                x: rect.minX + topCornerRadius,
                y: rect.minY,
                width: rect.width - 2 * topCornerRadius,
                height: rect.height
            )
            
            // Start at Top edge, right of Top-Left corner
            path.move(to: CGPoint(x: indentedRect.minX + bottomCornerRadius, y: indentedRect.minY))
            
            // Top-Left Corner (Curve Left-Down)
            path.addQuadCurve(
                to: CGPoint(x: indentedRect.minX, y: indentedRect.minY + bottomCornerRadius),
                control: CGPoint(x: indentedRect.minX, y: indentedRect.minY)
            )
            
            // Left Edge (Down)
            path.addLine(to: CGPoint(x: indentedRect.minX, y: indentedRect.maxY - bottomCornerRadius))
            
            // Bottom-Left Corner (Curve Down-Right)
            path.addQuadCurve(
                to: CGPoint(x: indentedRect.minX + bottomCornerRadius, y: indentedRect.maxY),
                control: CGPoint(x: indentedRect.minX, y: indentedRect.maxY)
            )
            
            // Bottom Edge (Right)
            path.addLine(to: CGPoint(x: indentedRect.maxX - bottomCornerRadius, y: indentedRect.maxY))
            
            // Bottom-Right Corner (Curve Right-Up)
            path.addQuadCurve(
                to: CGPoint(x: indentedRect.maxX, y: indentedRect.maxY - bottomCornerRadius),
                control: CGPoint(x: indentedRect.maxX, y: indentedRect.maxY)
            )
            
            // Right Edge (Up)
            path.addLine(to: CGPoint(x: indentedRect.maxX, y: indentedRect.minY + bottomCornerRadius))
            
            // Top-Right Corner (Curve Up-Left)
            path.addQuadCurve(
                to: CGPoint(x: indentedRect.maxX - bottomCornerRadius, y: indentedRect.minY),
                control: CGPoint(x: indentedRect.maxX, y: indentedRect.minY)
            )
            
            path.closeSubpath()
        } else {
            path.move(
                to: CGPoint(
                    x: rect.minX,
                    y: rect.minY
                )
            )

            path.addQuadCurve(
                to: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.minY + topCornerRadius
                ),
                control: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.minY
                )
            )

            path.addLine(
                to: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.maxY - bottomCornerRadius
                )
            )

            path.addQuadCurve(
                to: CGPoint(
                    x: rect.minX + topCornerRadius + bottomCornerRadius,
                    y: rect.maxY
                ),
                control: CGPoint(
                    x: rect.minX + topCornerRadius,
                    y: rect.maxY
                )
            )

            path.addLine(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius - bottomCornerRadius,
                    y: rect.maxY
                )
            )

            path.addQuadCurve(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.maxY - bottomCornerRadius
                ),
                control: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.maxY
                )
            )

            path.addLine(
                to: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.minY + topCornerRadius
                )
            )

            path.addQuadCurve(
                to: CGPoint(
                    x: rect.maxX,
                    y: rect.minY
                ),
                control: CGPoint(
                    x: rect.maxX - topCornerRadius,
                    y: rect.minY
                )
            )

            path.addLine(
                to: CGPoint(
                    x: rect.minX,
                    y: rect.minY
                )
            )
            
            path.closeSubpath()
        }

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
