import SwiftUI
import RoomPlan

struct WizardSummaryStepView: View {
    // MARK: - Properties
    @ObservedObject var state: GardenWizardState

    // --- Callbacks (Actions remontées au Parent) ---
    let onBack: () -> Void
    let onStartAR: () -> Void
    let onStartLiDAR: () -> Void
    let onFinishWizard: () -> Void

    // ✅ Nouveau: affichage "Sauvegarde..."
    let isSaving: Bool

    @State private var showLidarAlert = false
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Styles & Colors
    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : .secondary
    }

    private var infoCardBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.04)
    }

    private var iconChipBackground: Color {
        colorScheme == .dark
        ? Color.gardenAccent.opacity(0.18)
        : Color.gardenPrimary.opacity(0.12)
    }

    private var iconColor: Color {
        colorScheme == .dark ? Color.gardenAccent : Color.gardenPrimary
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // --- HEADER ---
                VStack(spacing: 12) {
                    Text("Mesurons votre espace")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("Pour créer des plans précis et des visualisations réalistes, nous devons connaître les dimensions de votre jardin.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(subtitleColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineSpacing(3)
                }

                // --- BENEFITS LIST ---
                VStack(spacing: 12) {
                    BenefitRow(
                        systemImage: "ruler",
                        title: "Proportions précises",
                        cardBackground: infoCardBackground,
                        chipBackground: iconChipBackground,
                        iconColor: iconColor
                    )

                    BenefitRow(
                        systemImage: "leaf",
                        title: "Placement réaliste des plantes",
                        cardBackground: infoCardBackground,
                        chipBackground: iconChipBackground,
                        iconColor: iconColor
                    )

                    BenefitRow(
                        systemImage: "viewfinder",
                        title: "Visualisation AR fidèle",
                        cardBackground: infoCardBackground,
                        chipBackground: iconChipBackground,
                        iconColor: iconColor
                    )
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        // --- FOOTER ---
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {

                Text(isSaving ? "Sauvegarde du jardin..." : "Durée : ~30 secondes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.top, 2)

                // BOUTON PRINCIPAL
                Button(action: {
                    // 1) Sauvegarde (le parent déclenche la requête)
                    onFinishWizard()

                    // 2) On décide quelle caméra lancer
                    switch state.scanMethod {
                    case .some(.gardenPerimeter):
                        onStartAR()

                    case .some(.roomScan):
                        if RoomCaptureSession.isSupported {
                            onStartLiDAR()
                        } else {
                            showLidarAlert = true
                        }

                    case .none:
                        if RoomCaptureSession.isSupported {
                            onStartLiDAR()
                        } else {
                            onStartAR()
                        }
                    }
                }) {
                    HStack {
                        Text(isSaving ? "Sauvegarde..." : "Scanner mon espace en AR")
                        Image(systemName: isSaving ? "arrow.triangle.2.circlepath" : "camera.fill")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))
                // Option: bloque double-tap pendant save
                .disabled(isSaving)

                Button("Retour") { onBack() }
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0.0),
                        Color.gardenBackground.opacity(0.9),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .alert("Scan 3D indisponible", isPresented: $showLidarAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
            Cette méthode utilise le scanner LiDAR.
            Ton appareil ne dispose pas de LiDAR (ex : iPhone Pro / iPad Pro uniquement).

            Tu peux continuer avec la méthode de mesure classique !
            """)
        }
    }
}

// MARK: - Subviews

private struct BenefitRow: View {
    let systemImage: String
    let title: String

    let cardBackground: Color
    let chipBackground: Color
    let iconColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chipBackground)
                    .frame(width: 44, height: 44)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
    }
}
