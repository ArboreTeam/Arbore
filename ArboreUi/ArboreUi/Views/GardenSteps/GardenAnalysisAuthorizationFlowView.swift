import AVFoundation
import SwiftUI
import UIKit

/// Explique l'usage de la caméra avant la demande système, puis ouvre
/// immédiatement le scan. La localisation est volontairement absente de ce
/// point du parcours : elle n'est pas nécessaire à la mesure de l'espace.
struct GardenAnalysisAuthorizationFlowView: View {
    let onReady: () -> Void
    let onCancel: () -> Void

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequesting = false
    @State private var didConfigure = false
    @State private var didComplete = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.gardenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(ArboreDesign.Colors.softSurface, in: Circle())
                    }

                    Spacer()
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(ArboreDesign.Colors.softGreenBackground)
                        .frame(width: 112, height: 112)

                    Image(systemName: cameraIsDenied ? "camera.fill" : "camera.viewfinder")
                        .font(.system(size: 45, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                }

                Text(L10n.t("GARDEN_PERMISSION_CAMERA_EYEBROW").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .padding(.top, 26)

                Text(
                    L10n.t(
                        cameraIsDenied
                            ? "GARDEN_PERMISSION_CAMERA_DENIED_TITLE"
                            : "GARDEN_PERMISSION_CAMERA_TITLE"
                    )
                )
                .font(.system(size: 29, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                Text(
                    L10n.t(
                        cameraIsDenied
                            ? "GARDEN_PERMISSION_CAMERA_DENIED_DESCRIPTION"
                            : "GARDEN_PERMISSION_CAMERA_DESCRIPTION"
                    )
                )
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

                Label(
                    L10n.t(
                        cameraIsDenied
                            ? "GARDEN_PERMISSION_CAMERA_DENIED_NOTE"
                            : "GARDEN_PERMISSION_CAMERA_PRIVACY"
                    ),
                    systemImage: cameraIsDenied ? "gearshape.fill" : "lock.shield.fill"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ArboreDesign.Colors.softSurface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .padding(.top, 24)

                Spacer()

                Button(action: primaryAction) {
                    HStack(spacing: 9) {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(
                                L10n.t(
                                    cameraIsDenied
                                        ? "COMMON_OPEN_SETTINGS"
                                        : "GARDEN_PERMISSION_CAMERA_ALLOW"
                                )
                            )
                            Image(systemName: cameraIsDenied ? "gearshape.fill" : "camera.fill")
                        }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        ArboreDesign.Colors.primaryGreen.opacity(isRequesting ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .onAppear(perform: configureInitialState)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshAfterSettings()
        }
    }

    private var cameraIsDenied: Bool {
        cameraStatus == .denied || cameraStatus == .restricted
    }

    private func configureInitialState() {
        guard !didConfigure else { return }
        didConfigure = true
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        // Une permission déjà accordée ne doit jamais créer une étape de plus.
        if cameraStatus == .authorized {
            complete()
        }
    }

    private func primaryAction() {
        if cameraIsDenied {
            openSettings()
        } else {
            requestCameraAccess()
        }
    }

    private func requestCameraAccess() {
        if cameraStatus == .authorized {
            complete()
            return
        }

        isRequesting = true
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isRequesting = false
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

            if granted {
                complete()
            }
        }
    }

    private func refreshAfterSettings() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .authorized {
            complete()
        }
    }

    private func complete() {
        guard !didComplete else { return }
        didComplete = true
        onReady()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
