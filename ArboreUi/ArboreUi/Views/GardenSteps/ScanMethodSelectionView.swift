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
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_SCAN_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("WIZARD_SCAN_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    gardenMeasureCard
                    roomScanCard
                }
            }
            .padding(.horizontal, 24)
        } actions: {
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
    }

    // MARK: - Cartes

    /// Mesure “plan 2D” avec ton ARMeasureModel
    private var gardenMeasureCard: some View {
        ImprovedSelectableCard(
            isSelected: state.scanMethod == .gardenPerimeter,
            icon: "icon3d_triangular_ruler",
            title: L10n.t("WIZARD_SCAN_PERIMETER_TITLE"),
            subtitle: L10n.t("WIZARD_SCAN_PERIMETER_SUBTITLE")
        ) {
            state.scanMethod = .gardenPerimeter
        }
    }

    /// Scan LiDAR 3D (RoomPlan)
    private var roomScanCard: some View {
        let isSupported = RoomCaptureSession.isSupported

        return ImprovedSelectableCard(
            isSelected: state.scanMethod == .roomScan,
            icon: "icon3d_phone",
            title: L10n.t("WIZARD_SCAN_ROOM_TITLE"),
            subtitle: isSupported
                ? L10n.t("WIZARD_SCAN_ROOM_SUBTITLE")
                : L10n.t("WIZARD_SCAN_ROOM_UNSUPPORTED")
        ) {
            if isSupported {
                state.scanMethod = .roomScan
            }
        }
        .opacity(isSupported ? 1.0 : 0.4)
    }
}
