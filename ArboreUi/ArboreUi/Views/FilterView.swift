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
                    
                    // Section Lumière
                    FilterSection(
                        title: NSLocalizedString("FILTER_LIGHT_TITLE", value: "Luminosité", comment: "Light section"),
                        icon: "sun.max.fill",
                        options: lightOptions,
                        selectedOption: $tempFilters.lightType
                    )
                    
                    // Section Arrosage
                    FilterSection(
                        title: NSLocalizedString("FILTER_WATER_TITLE", value: "Arrosage", comment: "Water section"),
                        icon: "drop.fill",
                        options: waterOptions,
                        selectedOption: $tempFilters.waterFrequency
                    )
                    
                    // Section Difficulté
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
            .background(themeManager.backgroundColor.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("FILTER_TITLE", value: "Filtres", comment: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(themeManager.textColor)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetFilters) {
                        Text(NSLocalizedString("FILTER_RESET", value: "Réinitialiser", comment: "Reset"))
                            .foregroundColor(themeManager.adjust(Color(hex: "#263826")))
                            .fontWeight(.medium)
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
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.textColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(themeManager.cardBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(themeManager.adjust(Color(hex: "#263826")), lineWidth: 2)
                                )
                        )
                }
                
                Button(action: applyFilters) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                        Text(NSLocalizedString("FILTER_APPLY", value: "Appliquer", comment: "Apply"))
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        themeManager.adjust(Color(hex: "#3F6212")),
                                        themeManager.adjust(Color(hex: "#4A7615"))
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(themeManager.backgroundColor)
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
            // En-tête de section
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.adjust(Color(hex: "#3F6212")))
                
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.textColor)
            }
            
            // Options
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : themeManager.textColor)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isSelected 
                            ? LinearGradient(
                                colors: [
                                    themeManager.adjust(Color(hex: "#3F6212")),
                                    themeManager.adjust(Color(hex: "#4A7615"))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [themeManager.cardBackgroundColor, themeManager.cardBackgroundColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected 
                                    ? Color.clear 
                                    : themeManager.textColor.opacity(0.15),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: isSelected 
                    ? Color.black.opacity(0.15) 
                    : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
