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
            if normalizedSelected.contains("faible") || normalizedSelected.contains("low") || normalizedSelected.contains("schwach") || normalizedSelected.contains("niedrig") || normalizedSelected.contains("baja") {
                if !plantLight.contains("faible") && !plantLight.contains("low") && !plantLight.contains("ombre") && !plantLight.contains("shade") && !plantLight.contains("schwach") && !plantLight.contains("schatten") && !plantLight.contains("baja") && !plantLight.contains("sombra") {
                    return false
                }
            } else if normalizedSelected.contains("modér") || normalizedSelected.contains("medium") || normalizedSelected.contains("mittel") || normalizedSelected.contains("moderat") || normalizedSelected.contains("moderada") {
                if !plantLight.contains("modér") && !plantLight.contains("medium") && !plantLight.contains("indirect") && !plantLight.contains("mittel") && !plantLight.contains("moderat") && !plantLight.contains("indirekt") && !plantLight.contains("moderada") && !plantLight.contains("indirecta") {
                    return false
                }
            } else if normalizedSelected.contains("forte") || normalizedSelected.contains("high") || normalizedSelected.contains("stark") || normalizedSelected.contains("hoch") || normalizedSelected.contains("alta") {
                if !plantLight.contains("direct") && !plantLight.contains("forte") && !plantLight.contains("high") && !plantLight.contains("soleil") && !plantLight.contains("sun") && !plantLight.contains("direkt") && !plantLight.contains("stark") && !plantLight.contains("hoch") && !plantLight.contains("sonne") && !plantLight.contains("alta") && !plantLight.contains("sol") {
                    return false
                }
            }
        }
        
        // Filtre arrosage
        if let selectedWater = waterFrequency {
            let plantWater = translation.water?.frequency?.lowercased() ?? ""
            let normalizedSelected = selectedWater.lowercased()
            
            if normalizedSelected.contains("peu") || normalizedSelected.contains("low") || normalizedSelected.contains("wenig") || normalizedSelected.contains("bajo") || normalizedSelected.contains("poco") {
                if !plantWater.contains("peu") && !plantWater.contains("low") && !plantWater.contains("rare") && !plantWater.contains("wenig") && !plantWater.contains("selten") && !plantWater.contains("bajo") && !plantWater.contains("poco") {
                    return false
                }
            } else if normalizedSelected.contains("moyen") || normalizedSelected.contains("medium") || normalizedSelected.contains("mittel") || normalizedSelected.contains("moderado") {
                if !plantWater.contains("moyen") && !plantWater.contains("medium") && !plantWater.contains("modér") && !plantWater.contains("mittel") && !plantWater.contains("moderat") && !plantWater.contains("moderado") {
                    return false
                }
            } else if normalizedSelected.contains("souvent") || normalizedSelected.contains("high") || normalizedSelected.contains("häufig") || normalizedSelected.contains("haeufig") || normalizedSelected.contains("oft") || normalizedSelected.contains("frecuente") {
                if !plantWater.contains("souvent") && !plantWater.contains("fréquent") && !plantWater.contains("high") && !plantWater.contains("regular") && !plantWater.contains("häufig") && !plantWater.contains("haeufig") && !plantWater.contains("oft") && !plantWater.contains("frecuente") {
                    return false
                }
            }
        }
        
        // Filtre difficulté (#485)
        //
        // Ce bloc excluait AUTREFOIS toutes les plantes : il lisait
        // `care.difficulty`, un champ que le backend ne sérialisait pas, donc
        // toujours vide. Aucun mot-clé ne correspondait jamais, et chaque plante
        // tombait dans un `return false`. Sélectionner une difficulté vidait la
        // liste.
        //
        // La résolution est désormais partagée avec le wizard
        // (`Plant.careDifficulty`), et surtout elle distingue « inconnu » de
        // « ne correspond pas » : une plante dont on ignore l'entretien n'est
        // PAS masquée. Un filtre qui cache ce qu'il ne sait pas juger ment à
        // l'utilisateur.
        if let selectedDiff = difficulty {
            let normalizedSelected = selectedDiff.lowercased()

            let wanted: Plant.CareDifficulty?
            if ["facile", "easy", "einfach", "fácil", "facil"].contains(where: normalizedSelected.contains) {
                wanted = .easy
            } else if ["intermé", "medium", "mittel", "intermedio"].contains(where: normalizedSelected.contains) {
                wanted = .moderate
            } else if ["exigeant", "hard", "anspruchsvoll", "dificil", "difícil"].contains(where: normalizedSelected.contains) {
                wanted = .demanding
            } else {
                wanted = nil
            }

            if let wanted = wanted, let actual = plant.careDifficulty(locale: locale) {
                if actual != wanted { return false }
            }
            // `actual == nil` → donnée absente, on n'exclut pas.
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
        L10n.t("FILTER_LIGHT_LOW"),
        L10n.t("FILTER_LIGHT_MEDIUM"),
        L10n.t("FILTER_LIGHT_HIGH")
    ]
    
    let waterOptions = [
        L10n.t("FILTER_WATER_LOW"),
        L10n.t("FILTER_WATER_MEDIUM"),
        L10n.t("FILTER_WATER_HIGH")
    ]
    
    let difficultyOptions = [
        L10n.t("FILTER_DIFFICULTY_EASY"),
        L10n.t("FILTER_DIFFICULTY_MEDIUM"),
        L10n.t("FILTER_DIFFICULTY_HARD")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    FilterSection(
                        title: L10n.t("FILTER_LIGHT_TITLE"),
                        icon: "sun.max.fill",
                        options: lightOptions,
                        selectedOption: $tempFilters.lightType
                    )
                    
                    FilterSection(
                        title: L10n.t("FILTER_WATER_TITLE"),
                        icon: "drop.fill",
                        options: waterOptions,
                        selectedOption: $tempFilters.waterFrequency
                    )
                    
                    FilterSection(
                        title: L10n.t("FILTER_DIFFICULTY_TITLE"),
                        icon: "star.fill",
                        options: difficultyOptions,
                        selectedOption: $tempFilters.difficulty
                    )
                    
                    Spacer(minLength: 80)
                }
                .padding(20)
            }
            .background(ArboreDesign.Colors.background.ignoresSafeArea())
            .navigationTitle(L10n.t("FILTER_TITLE"))
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
                        Text(L10n.t("FILTER_RESET"))
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
                    Text(L10n.t("FILTER_CANCEL"))
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
                        Text(L10n.t("FILTER_APPLY"))
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
