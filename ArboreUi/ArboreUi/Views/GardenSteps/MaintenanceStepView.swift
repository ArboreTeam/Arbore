import SwiftUI

struct MaintenanceStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_MAINTENANCE_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    // Le cœur reste hors de la chaîne traduite : c'est un
                    // symbole, pas du texte, et il garde la couleur de marque.
                    Text("\(L10n.t("WIZARD_MAINTENANCE_SUBTITLE")) \(Text(Image(systemName: "heart")).foregroundStyle(Color.gardenPrimary))")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 16) {
                    ForEach(MaintenanceLevel.allCases) { level in
                        ImprovedSelectableCard(
                            isSelected: state.maintenance == level,
                            icon: level.iconName,
                            title: level.title,
                            subtitle: level.subtitle
                        ) {
                            state.maintenance = level
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        } actions: {
            Button(L10n.t("COMMON_CONTINUE")) { onNext() }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.maintenance != nil))
                .disabled(state.maintenance == nil)

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
    }
}
