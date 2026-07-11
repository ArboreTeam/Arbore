import SwiftUI

struct SafetyStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void
    
    private func toggleSafety(_ option: SafetyOption) {
        if option == .none {
            state.safetySelections = [.none]
        } else {
            state.safetySelections.remove(.none)
            if state.safetySelections.contains(option) {
                state.safetySelections.remove(option)
            } else {
                state.safetySelections.insert(option)
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_SAFETY_TITLE"))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(L10n.t("WIZARD_SAFETY_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // 🔽 plus de Spacer ici
                
                // Liste des options
                VStack(spacing: 16) {
                    ForEach(SafetyOption.allCases) { option in
                        ImprovedSelectableCard(
                            isSelected: state.safetySelections.contains(option),
                            systemImage: option.iconName,
                            title: option.title
                        ) {
                            toggleSafety(option)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()    // on garde celui-ci pour pousser les boutons en bas
                
                // Boutons
                VStack(spacing: 12) {
                    Button(action: onNext) {
                        HStack {
                            Text(L10n.t("COMMON_CONTINUE"))
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))
                    
                    Button(L10n.t("COMMON_BACK")) { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
