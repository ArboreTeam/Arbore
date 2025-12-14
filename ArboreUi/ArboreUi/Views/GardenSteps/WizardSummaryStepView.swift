import SwiftUI
import RoomPlan

struct WizardSummaryStepView: View {
    @ObservedObject var state: GardenWizardState
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var goToGardenMeasure = false
    @State private var goToRoomScan = false
    @State private var showLidarAlert = false

    @Environment(\.colorScheme) private var colorScheme

    // Même style de “card” que tes autres écrans
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
        // proche du "black/20" du HTML
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.04)
    }

    private var iconChipBackground: Color {
        // proche du "primary/20"
        colorScheme == .dark
            ? Color.gardenAccent.opacity(0.18)
            : Color.gardenPrimary.opacity(0.12)
    }

    private var iconColor: Color {
        colorScheme == .dark ? Color.gardenAccent : Color.gardenPrimary
    }

    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // --- HEADER (comme ton HTML) ---
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

            // NAVIGATION LINKS CACHÉS (inchangé)
            NavigationLink(
                destination: GardenMeasureView(),
                isActive: $goToGardenMeasure,
                label: { EmptyView() }
            )
            .hidden()

            NavigationLink(
                destination: RoomScanListView(),
                isActive: $goToRoomScan,
                label: { EmptyView() }
            )
            .hidden()
        }
        // Footer boutons + dégradé (structure identique)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {

                Text("Durée : ~30 secondes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.top, 2)

                Button(action: {
                    onFinish()

                    switch state.scanMethod {
                    case .some(.gardenPerimeter):
                        goToGardenMeasure = true

                    case .some(.roomScan):
                        if RoomCaptureSession.isSupported {
                            goToRoomScan = true
                        } else {
                            showLidarAlert = true
                        }

                    case .none:
                        if RoomCaptureSession.isSupported {
                            goToRoomScan = true
                        } else {
                            goToGardenMeasure = true
                        }
                    }
                }) {
                    HStack {
                        Text("Scanner mon espace en AR")
                        Image(systemName: "camera.fill")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))

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

// MARK: - Benefit Row

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
