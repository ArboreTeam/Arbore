import CoreMotion
import SwiftUI
import UIKit

/// Étape très courte affichée au-dessus de la caméra une fois les dimensions
/// prises. Elle ne concerne pas les jardins extérieurs.
struct GardenExposureCaptureOverlay: View {
    let spaceType: GardenSpaceType
    let onCapture: (Double?) -> Void

    @StateObject private var motion = GardenExposureMotionController()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Text(L10n.t("GARDEN_EXPOSURE_EYEBROW").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(ArboreDesign.Colors.secondaryGreen)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 18)

                Spacer()

                ZStack {
                    Circle()
                        .fill(.black.opacity(0.22))
                        .frame(width: 104, height: 104)

                    Circle()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, dash: [8, 7]))
                        .frame(width: 86, height: 86)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.28), radius: 12)

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 46, height: 46)
                            .background(ArboreDesign.Colors.primaryGreen, in: Circle())

                        Text(title)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(L10n.t("GARDEN_EXPOSURE_DESCRIPTION"))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onCapture(motion.magneticYawRadians)
                    } label: {
                        HStack(spacing: 9) {
                            Text(L10n.t("GARDEN_EXPOSURE_CAPTURE"))
                            Image(systemName: "checkmark")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            ArboreDesign.Colors.primaryGreen,
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private var title: String {
        switch spaceType {
        case .interior:
            return L10n.t("GARDEN_EXPOSURE_INTERIOR_TITLE")
        case .balcony:
            return L10n.t("GARDEN_EXPOSURE_BALCONY_TITLE")
        case .terrace:
            return L10n.t("GARDEN_EXPOSURE_TERRACE_TITLE")
        case .garden:
            return ""
        }
    }
}

@MainActor
private final class GardenExposureMotionController: ObservableObject {
    @Published private(set) var magneticYawRadians: Double?

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let reference: CMAttitudeReferenceFrame = available.contains(.xMagneticNorthZVertical)
            ? .xMagneticNorthZVertical
            : .xArbitraryCorrectedZVertical

        manager.deviceMotionUpdateInterval = 0.12
        manager.showsDeviceMovementDisplay = true
        manager.startDeviceMotionUpdates(using: reference, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.magneticYawRadians = reference == .xMagneticNorthZVertical
                ? motion.attitude.yaw
                : nil
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
