import SwiftUI

// MARK: - Modèle de filtres
struct PlantFilters: Equatable {
    var lightType: String?
    var waterFrequency: String?
    var difficulty: String?
    
    var isActive: Bool {
        lightType != nil || waterFrequency != nil || difficulty != nil
    }
    
    func matches(plant: Plant, locale: String) -> Bool {
        guard let translation = plant.translations[locale] else { return true }
        
        // Filtre lumière
        if let selectedLight = lightType {
            let plantLight = translation.sun?.lightType?.lowercased() ?? ""
            let normalizedSelected = selectedLight.lowercased()
            
            // Correspondance flexible
            if normalizedSelected.contains("faible") || normalizedSelected.contains("low") {
                if !plantLight.contains("faible") && !plantLight.contains("low") && !plantLight.contains("ombre") && !plantLight.contains("shade") {
                    return false
                }
            } else if normalizedSelected.contains("modér") || normalizedSelected.contains("medium") {
                if !plantLight.contains("modér") && !plantLight.contains("medium") && !plantLight.contains("indirect") {
                    return false
                }
            } else if normalizedSelected.contains("forte") || normalizedSelected.contains("high") {
                if !plantLight.contains("direct") && !plantLight.contains("forte") && !plantLight.contains("high") && !plantLight.contains("soleil") && !plantLight.contains("sun") {
                    return false
                }
            }
        }
        
        // Filtre arrosage
        if let selectedWater = waterFrequency {
            let plantWater = translation.water?.frequency?.lowercased() ?? ""
            let normalizedSelected = selectedWater.lowercased()
            
            if normalizedSelected.contains("peu") || normalizedSelected.contains("low") {
                if !plantWater.contains("peu") && !plantWater.contains("low") && !plantWater.contains("rare") {
                    return false
                }
            } else if normalizedSelected.contains("moyen") || normalizedSelected.contains("medium") {
                if !plantWater.contains("moyen") && !plantWater.contains("medium") && !plantWater.contains("modér") {
                    return false
                }
            } else if normalizedSelected.contains("souvent") || normalizedSelected.contains("high") {
                if !plantWater.contains("souvent") && !plantWater.contains("fréquent") && !plantWater.contains("high") && !plantWater.contains("regular") {
                    return false
                }
            }
        }
        
        // Filtre difficulté
        if let selectedDiff = difficulty {
            let plantCare = translation.care?.difficulty?.lowercased() ?? ""
            let normalizedSelected = selectedDiff.lowercased()
            
            if normalizedSelected.contains("facile") || normalizedSelected.contains("easy") {
                if !plantCare.contains("facile") && !plantCare.contains("easy") && !plantCare.contains("simple") {
                    return false
                }
            } else if normalizedSelected.contains("intermé") || normalizedSelected.contains("medium") {
                if !plantCare.contains("intermé") && !plantCare.contains("medium") && !plantCare.contains("modér") {
                    return false
                }
            } else if normalizedSelected.contains("exigeant") || normalizedSelected.contains("hard") {
                if !plantCare.contains("exigeant") && !plantCare.contains("difficile") && !plantCare.contains("hard") && !plantCare.contains("expert") {
                    return false
                }
            }
        }
        
        return true
    }
}

struct FilterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    @Binding var filters: PlantFilters
    
    @State private var tempFilters: PlantFilters
    
    init(filters: Binding<PlantFilters>) {
        self._filters = filters
        self._tempFilters = State(initialValue: filters.wrappedValue)
    }
    
    let lightOptions = [
        NSLocalizedString("FILTER_LIGHT_LOW", value: "Faible", comment: "Low light"),
        NSLocalizedString("FILTER_LIGHT_MEDIUM", value: "Modérée", comment: "Medium light"),
        NSLocalizedString("FILTER_LIGHT_HIGH", value: "Forte", comment: "High light")
    ]
    
    let waterOptions = [
        NSLocalizedString("FILTER_WATER_LOW", value: "Peu", comment: "Low water"),
        NSLocalizedString("FILTER_WATER_MEDIUM", value: "Moyen", comment: "Medium water"),
        NSLocalizedString("FILTER_WATER_HIGH", value: "Souvent", comment: "High water")
    ]
    
    let difficultyOptions = [
        NSLocalizedString("FILTER_DIFFICULTY_EASY", value: "Facile", comment: "Easy"),
        NSLocalizedString("FILTER_DIFFICULTY_MEDIUM", value: "Intermédiaire", comment: "Medium"),
        NSLocalizedString("FILTER_DIFFICULTY_HARD", value: "Exigeante", comment: "Hard")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    FilterSection(
                        title: NSLocalizedString("FILTER_LIGHT_TITLE", value: "Luminosité", comment: "Light section"),
                        icon: "sun.max.fill",
                        options: lightOptions,
                        selectedOption: $tempFilters.lightType
                    )
                    
                    FilterSection(
                        title: NSLocalizedString("FILTER_WATER_TITLE", value: "Arrosage", comment: "Water section"),
                        icon: "drop.fill",
                        options: waterOptions,
                        selectedOption: $tempFilters.waterFrequency
                    )
                    
                    FilterSection(
                        title: NSLocalizedString("FILTER_DIFFICULTY_TITLE", value: "Difficulté d'entretien", comment: "Difficulty section"),
                        icon: "star.fill",
                        options: difficultyOptions,
                        selectedOption: $tempFilters.difficulty
                    )
                    
                    Spacer(minLength: 80)
                }
                .padding(20)
            }
            .background(ArboreDesign.Colors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("FILTER_TITLE", value: "Filtres", comment: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetFilters) {
                        Text(NSLocalizedString("FILTER_RESET", value: "Réinitialiser", comment: "Reset"))
                            .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
    }
    
    // MARK: - Barre d'action en bas
    
    var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text(NSLocalizedString("FILTER_CANCEL", value: "Annuler", comment: "Cancel"))
                        .font(ArboreDesign.Typography.button)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                                .fill(ArboreDesign.Colors.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                                        .stroke(ArboreDesign.Colors.primaryGreen, lineWidth: 1.4)
                                )
                        )
                }
                
                Button(action: applyFilters) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                        Text(NSLocalizedString("FILTER_APPLY", value: "Appliquer", comment: "Apply"))
                    }
                    .font(ArboreDesign.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .fill(ArboreDesign.Colors.primaryGreen)
                    )
                    .shadow(color: ArboreDesign.Colors.shadow, radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(ArboreDesign.Colors.background)
        }
    }
    
    // MARK: - Actions
    
    func applyFilters() {
        filters = tempFilters
        dismiss()
    }
    
    func resetFilters() {
        tempFilters = PlantFilters()
    }
}

// MARK: - Section de filtres

struct FilterSection: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let icon: String
    let options: [String]
    @Binding var selectedOption: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                
                Text(title)
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
            }
            
            VStack(spacing: 12) {
                ForEach(options, id: \.self) { option in
                    FilterOptionButton(
                        title: option,
                        isSelected: selectedOption == option,
                        action: {
                            if selectedOption == option {
                                selectedOption = nil
                            } else {
                                selectedOption = option
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Bouton d'option de filtre

struct FilterOptionButton: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(ArboreDesign.Typography.body.weight(.medium))
                    .foregroundColor(isSelected ? .white : ArboreDesign.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .fill(isSelected ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(isSelected ? Color.clear : ArboreDesign.Colors.border, lineWidth: 1)
                    )
            )
            .shadow(color: isSelected ? ArboreDesign.Colors.shadow : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
