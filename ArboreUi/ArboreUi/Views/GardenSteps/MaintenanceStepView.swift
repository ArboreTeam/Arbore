import SwiftUI

struct MaintenanceStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_MAINTENANCE_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(L10n.t("WIZARD_MAINTENANCE_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(MaintenanceLevel.allCases) { level in
                            ImprovedSelectableCard(
                                isSelected: state.maintenance == level,
                                systemImage: level.iconName,
                                title: level.title,
                                subtitle: level.subtitle
                            ) {
                                state.maintenance = level
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(L10n.t("COMMON_CONTINUE")) { onNext() }
                        .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.maintenance != nil))
                        .disabled(state.maintenance == nil)
                    
                    Button(L10n.t("COMMON_BACK")) { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
