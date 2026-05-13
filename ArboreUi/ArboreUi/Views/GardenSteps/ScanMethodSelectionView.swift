import SwiftUI
import RoomPlan   // On en aura besoin plus tard pour griser l’option LiDAR

struct ScanMethodStepView: View {
    @ObservedObject var state: GardenWizardState

    /// Déclenché par le CTA primaire. Le parent ouvre une fullScreenCover AR
    /// (ARViewContainerMesure ou LiDARScanWizardView selon `state.scanMethod`)
    /// qui trace, sauvegarde la boundary, fait un `POST /gardens` et renvoie
    /// le `gardenId` créé via son propre callback. Le wizard avance ensuite
    /// vers `aiSuggestion`.
    let onStartScan: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.gardenBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                // Titre
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment veux-tu scanner\ncet espace ?")
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Choisis la méthode la plus adaptée à ton type d’espace.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 15)

                // Cartes de choix
                ScrollView {
                    VStack(spacing: 16) {
                        gardenMeasureCard
                        roomScanCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .padding(.top, 20)
                }

                Spacer()

                // Boutons bas
                VStack(spacing: 12) {
                    Button {
                        onStartScan()
                    } label: {
                        HStack {
                            Text("Démarrer le scan")
                            Image(systemName: "arkit")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.scanMethod != nil))
                    .disabled(state.scanMethod == nil)

                    Button("Retour") {
                        onBack()
                    }
                    .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Cartes

    /// Mesure “plan 2D” avec ton ARMeasureModel
    private var gardenMeasureCard: some View {
        ImprovedSelectableCard(
            isSelected: state.scanMethod == .gardenPerimeter,
            systemImage: "ruler",
            title: "Tracer mon jardin au sol",
            subtitle: "Place des points au sol pour dessiner le plan de ton jardin, puis ajoute des zones de plantation.",
            gradient: [Color(hex: "#4A7C59"), Color(hex: "#2C5530")]
        ) {
            state.scanMethod = .gardenPerimeter
        }
    }

    /// Scan LiDAR 3D (RoomPlan)
    private var roomScanCard: some View {
        let isSupported = RoomCaptureSession.isSupported

        return ImprovedSelectableCard(
            isSelected: state.scanMethod == .roomScan,
            systemImage: "cube.transparent",
            title: "Scanner la pièce en 3D",
            subtitle: isSupported
                ? "Utilise le scanner 3D pour capturer ton intérieur ou ton balcon et visualiser les plantes dans l’espace."
                : "Disponible uniquement sur certains iPhone / iPad avec LiDAR.",
            gradient: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")]
        ) {
            if isSupported {
                state.scanMethod = .roomScan
            }
        }
        .opacity(isSupported ? 1.0 : 0.4)
    }
}
