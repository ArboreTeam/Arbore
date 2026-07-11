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
                    Text(L10n.t("WIZARD_SCAN_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("WIZARD_SCAN_SUBTITLE"))
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
                            Text(L10n.t("WIZARD_SCAN_START"))
                            Image(systemName: "arkit")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.scanMethod != nil))
                    .disabled(state.scanMethod == nil)

                    Button(L10n.t("COMMON_BACK")) {
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
            title: L10n.t("WIZARD_SCAN_PERIMETER_TITLE"),
            subtitle: L10n.t("WIZARD_SCAN_PERIMETER_SUBTITLE"),
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
            title: L10n.t("WIZARD_SCAN_ROOM_TITLE"),
            subtitle: isSupported
                ? L10n.t("WIZARD_SCAN_ROOM_SUBTITLE")
                : L10n.t("WIZARD_SCAN_ROOM_UNSUPPORTED"),
            gradient: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")]
        ) {
            if isSupported {
                state.scanMethod = .roomScan
            }
        }
        .opacity(isSupported ? 1.0 : 0.4)
    }
}
