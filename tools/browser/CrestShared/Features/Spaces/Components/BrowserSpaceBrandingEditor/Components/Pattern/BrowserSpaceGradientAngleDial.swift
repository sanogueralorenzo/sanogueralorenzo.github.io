import SwiftUI

struct BrowserSpaceGradientAngleDial: View {
    @Binding var angle: Double
    let color: Color

    @FocusState private var isKeyboardFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .fill(CrestColor.chromeSurface)
                Circle()
                    .strokeBorder(
                        CrestColor.subtleBorder,
                        lineWidth: CrestLayout.hairline
                    )

                Capsule()
                    .fill(color)
                    .frame(
                        width: diameter * BrowserSpaceForgeMetrics.gradientNeedleLengthRatio,
                        height: max(
                            BrowserSpaceForgeMetrics.gradientNeedleMinimumThickness,
                            diameter * BrowserSpaceForgeMetrics.gradientNeedleThicknessRatio
                        )
                    )
                    .offset(
                        x: diameter * BrowserSpaceForgeMetrics.gradientNeedleOffsetRatio
                    )
                    .rotationEffect(.degrees(angle))

                Circle()
                    .fill(CrestColor.textPrimary)
                    .frame(
                        width: max(
                            BrowserSpaceForgeMetrics.gradientCenterMinimumDiameter,
                            diameter * BrowserSpaceForgeMetrics.gradientCenterDiameterRatio
                        ))
            }
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        isKeyboardFocused = true
                        setAngle(for: value.location, in: diameter)
                    }
            )
        }
        .overlay {
            Circle()
                .stroke(
                    isKeyboardFocused ? Color.accentColor : .clear,
                    lineWidth: BrowserSpaceForgeMetrics.gradientFocusRingWidth
                )
                .padding(BrowserSpaceForgeMetrics.gradientFocusRingInset)
                .accessibilityHidden(true)
        }
        .focusable()
        .focused($isKeyboardFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            switch press.key {
            case .rightArrow, .upArrow:
                adjust(.increment)
            case .leftArrow, .downArrow:
                adjust(.decrement)
            default:
                return .ignored
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Gradient rotation")
        .accessibilityValue(Text("\(Int(angle.rounded())) degrees"))
        .accessibilityHint("Use the arrow keys or drag to rotate the gradient line")
        .accessibilityIdentifier("space-branding-gradient-angle")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjust(.increment)
            case .decrement:
                adjust(.decrement)
            @unknown default:
                break
            }
        }
    }

    private func setAngle(for location: CGPoint, in diameter: CGFloat) {
        let center = diameter / 2
        let radians = atan2(location.y - center, location.x - center)
        let degrees = Double(radians) * BrowserSpaceForgeMetrics.radiansToDegrees / .pi
        let remainder = degrees.truncatingRemainder(
            dividingBy: BrowserSpaceForgeMetrics.angleCircleDegrees
        )
        angle =
            remainder >= 0
            ? remainder
            : remainder + BrowserSpaceForgeMetrics.angleCircleDegrees
    }

    private func adjust(
        _ direction: BrowserSpaceGradientAngleAdjustmentDirection
    ) {
        angle = direction.adjusted(angle)
    }
}

#if DEBUG
    #Preview("Interactive angle") {
        @Previewable @State var angle = 45.0
        BrowserSpaceGradientAngleDial(angle: $angle, color: .indigo).padding()
    }
#endif
