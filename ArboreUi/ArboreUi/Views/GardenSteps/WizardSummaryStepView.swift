import SwiftUI
import RoomPlan

struct WizardSummaryStepView: View {
    // MARK: - Properties
    @ObservedObject var state: GardenWizardState
    
    // --- Callbacks (Actions remontées au Parent) ---
    // C'est grâce à ça que l'écran noir est corrigé :
    // On demande au parent de lancer la caméra, on ne le fait pas nous-mêmes.
    let onBack: () -> Void
    let onStartAR: () -> Void
    let onStartLiDAR: () -> Void
    let onFinishWizard: () -> Void
    
    @State private var showLidarAlert = false
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Styles & Colors
    // (Repris de ton code original pour conserver le design exact)
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white
    }
    
    private var cardShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.05)
    }
    
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
            // Fond
            Color.gardenBackground
                .ignoresSafeArea()

            // Contenu Principal
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

                // --- BENEFITS LIST (3 mini-cards) ---
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
        // --- FOOTER FLOTTANT ---
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {

                Text("Durée : ~30 secondes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.top, 2)

                // BOUTON PRINCIPAL : Scanner
                Button(action: {
                    // 1. On sauvegarde l'état
                    onFinishWizard()

                    // 2. On décide quelle caméra lancer
                    switch state.scanMethod {
                    case .some(.gardenPerimeter):
                        // On appelle le parent pour lancer l'AR
                        onStartAR()

                    case .some(.roomScan):
                        // On vérifie le LiDAR
                        if RoomCaptureSession.isSupported {
                            onStartLiDAR()
                        } else {
                            showLidarAlert = true
                        }

                    case .none:
                        // Choix par défaut intelligent
                        if RoomCaptureSession.isSupported {
                            onStartLiDAR()
                        } else {
                            onStartAR()
                        }
                    }
                }) {
                    HStack {
                        Text("Scanner mon espace en AR")
                        Image(systemName: "camera.fill")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))

                // BOUTON SECONDAIRE : Retour
                Button("Retour") { onBack() }
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            // Dégradé de fond pour le footer
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
        // ALERTE LIDAR
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

// MARK: - Subviews & Helpers

// Ligne de bénéfice (Petite carte avec icône)
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
