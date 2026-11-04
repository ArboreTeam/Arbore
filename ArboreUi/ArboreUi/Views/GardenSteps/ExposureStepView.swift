import SwiftUI

struct ExposureStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_EXPOSURE_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("WIZARD_EXPOSURE_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    ForEach(SunExposure.allCases) { exposure in
                        ImprovedSelectableCard(
                            isSelected: state.exposure == exposure,
                            icon: exposure.iconName,
                            title: exposure.title,
                            subtitle: exposure.subtitle
                        ) {
                            state.exposure = exposure
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        } actions: {
            Button(action: onNext) {
                HStack {
                    Text(L10n.t("COMMON_CONTINUE"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.exposure != nil))
            .disabled(state.exposure == nil)

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
    }
}
