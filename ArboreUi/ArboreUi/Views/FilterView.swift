import SwiftUI

// MARK: - Vocabulaires du filtre

/// Besoin de lumière demandé par l'utilisateur, en valeur close.
///
/// C'était une `String` : le libellé localisé lui-même, qu'il fallait ensuite
/// reconnaître par sous-chaînes dans cinq langues pour savoir lequel des trois
/// boutons avait été pressé. Un libellé retouché dans un `.strings` désarmait
/// le filtre en silence.
enum PlantLightNeed: String, CaseIterable, Hashable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return L10n.t("FILTER_LIGHT_LOW")
        case .medium: return L10n.t("FILTER_LIGHT_MEDIUM")
        case .high: return L10n.t("FILTER_LIGHT_HIGH")
        }
    }
}

/// Fréquence d'arrosage demandée, en valeur close.
enum PlantWateringNeed: String, CaseIterable, Hashable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return L10n.t("FILTER_WATER_LOW")
        case .medium: return L10n.t("FILTER_WATER_MEDIUM")
        case .high: return L10n.t("FILTER_WATER_HIGH")
        }
    }
}

extension Plant.CareDifficulty {
    var filterLabel: String {
        switch self {
        case .easy: return L10n.t("FILTER_DIFFICULTY_EASY")
        case .moderate: return L10n.t("FILTER_DIFFICULTY_MEDIUM")
        case .demanding: return L10n.t("FILTER_DIFFICULTY_HARD")
        }
    }
}

// MARK: - Modèle de filtres

/// Le filtre du catalogue, sans langue (#792).
///
/// Il en avait une, et c'était un trou béant. Sa première ligne était
///
///     guard let translation = plant.translations[locale] else { return true }
///
/// — donc **une plante sans traduction dans la langue du lecteur traversait
/// TOUS les filtres**. Au 2026-11-08, 877 fiches sur 1021 n'ont que l'anglais :
/// pour un utilisateur français, chacune passait le filtre lumière et le filtre
/// arrosage sans être évaluée. Le filtre ne se trompait pas, il ne s'appliquait
/// pas, et rien ne le signalait.
///
/// Cette ligne ne se répare pas, elle disparaît : la soixantaine de lignes de
/// sous-chaînes sur les champs **traduits** `sun.lightType` et
/// `water.frequency`, sous un commentaire qui disait « correspondance
/// flexible », est remplacée par la lecture de deux faits chiffrés du profil
/// botanique. Un filtre qui lit `botanicalProfile` n'a pas de langue —
/// `directSunHours` et `wateringIntervalDays` sont les mêmes pour tous les
/// lecteurs.
struct PlantFilters: Equatable {
    var light: PlantLightNeed?
    var water: PlantWateringNeed?
    var difficulty: Plant.CareDifficulty?

    var isActive: Bool {
        light != nil || water != nil || difficulty != nil
    }

    /// **Un critère sans fait n'exclut pas.**
    ///
    /// C'est la règle de #485, et elle vaut pour les trois axes : une plante
    /// dont on ignore l'exposition n'est pas masquée. Un filtre qui cache ce
    /// qu'il ne sait pas juger ment à l'utilisateur — et c'est aussi la seule
    /// lecture qui n'invente rien, puisque l'incertitude est la nôtre et non
    /// celle de la plante.
    func matches(_ plant: Plant) -> Bool {
        if let light, !light.admits(plant.botanicalProfile?.directSunHours) {
            return false
        }

        if let water, !water.admits(plant.botanicalProfile?.wateringIntervalDays) {
            return false
        }

        // La difficulté se résout via `Plant.careDifficulty()`, partagée avec
        // le questionnaire, et `nil` y signifie « inconnu » et non « ne
        // correspond pas » (#485).
        if let difficulty, let actual = plant.careDifficulty(), actual != difficulty {
            return false
        }

        return true
    }
}

extension PlantLightNeed {
    /// Bornes 3 h et 6 h de lumière directe.
    ///
    /// Elles ne sont pas inventées ici : ce sont celles que
    /// `PlantSuitabilityEvaluator.appendSunlightCriterion` applique déjà au
    /// jardin de l'utilisateur. Un seul jeu de bornes pour les deux côtés,
    /// sinon le catalogue et le questionnaire se contrediraient.
    func admits(_ heures: PlantRangeFact?) -> Bool {
        guard let heures, heures.hasValue else { return true }
        let minimum = heures.minimum ?? 0
        let maximum = heures.maximum ?? 24

        switch self {
        case .low: return minimum <= 3
        case .medium: return minimum <= 6 && maximum >= 3
        case .high: return maximum >= 6
        }
    }
}

extension PlantWateringNeed {
    /// Bornes d'intervalle entre deux arrosages, en jours.
    ///
    /// Trois seaux pour trois boutons : « souvent » au plus 3 jours,
    /// « modéré » de 4 à 9, « peu » à partir de 10. Les bornes sont DÉCLARÉES
    /// ici, visibles et discutables, plutôt que dispersées dans des listes de
    /// mots-clés par langue où elles n'existaient pas du tout.
    func admits(_ intervalle: PlantRangeFact?) -> Bool {
        guard let intervalle, intervalle.hasValue else { return true }
        let minimum = intervalle.minimum ?? 0
        let maximum = intervalle.maximum ?? .greatestFiniteMagnitude

        switch self {
        case .high: return minimum <= 3
        case .medium: return minimum <= 9 && maximum >= 4
        case .low: return maximum >= 10
        }
    }
}

struct FilterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    @Binding var filters: PlantFilters
    
    @State private var tempFilters: PlantFilters

    /// Catalogue affiché, pour n'offrir que les niveaux d'entretien auxquels les
    /// données peuvent répondre (#485).
    private let plants: [Plant]

    init(filters: Binding<PlantFilters>, plants: [Plant] = []) {
        self._filters = filters
        self._tempFilters = State(initialValue: filters.wrappedValue)
        self.plants = plants
    }
    
    let lightOptions = PlantLightNeed.allCases

    let waterOptions = PlantWateringNeed.allCases


    /// Niveaux d'entretien réellement proposables, mesurés sur le catalogue (#485).
    ///
    /// Proposer un choix auquel aucune donnée ne peut répondre est pire que ne
    /// pas le proposer : « Intermédiaire » ne renverrait ni les faciles ni les
    /// exigeantes, mais exactement les fiches SANS donnée — un sous-ensemble
    /// arbitraire présenté comme une réponse.
    ///
    /// Ce jour est arrivé : les 123 fiches portent une difficulté depuis #485,
    /// dont 21 intermédiaires. Le niveau apparaît donc de lui-même, sans qu'une
    /// ligne ait changé ici — c'était l'intérêt de dériver les options de la
    /// donnée plutôt que de les coder en dur.
    var difficultyOptions: [Plant.CareDifficulty] {
        let niveaux = Set(plants.compactMap { $0.careDifficulty() })

        var options: [Plant.CareDifficulty] = [.easy]
        if niveaux.contains(.moderate) {
            options.append(.moderate)
        }
        options.append(.demanding)
        return options
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    FilterSection(
                        title: L10n.t("FILTER_LIGHT_TITLE"),
                        icon: "sun.max.fill",
                        options: lightOptions,
                        label: \.label,
                        selectedOption: $tempFilters.light
                    )

                    FilterSection(
                        title: L10n.t("FILTER_WATER_TITLE"),
                        icon: "drop.fill",
                        options: waterOptions,
                        label: \.label,
                        selectedOption: $tempFilters.water
                    )

                    FilterSection(
                        title: L10n.t("FILTER_DIFFICULTY_TITLE"),
                        icon: "star.fill",
                        options: difficultyOptions,
                        label: \.filterLabel,
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

/// Section de filtre sur un vocabulaire FERMÉ.
///
/// Elle portait des `String` — les libellés localisés eux-mêmes — ce qui
/// obligeait le filtre à les reconnaître ensuite par sous-chaînes. Le libellé
/// n'est plus que de l'affichage ; la valeur qui circule est close (#792).
struct FilterSection<Option: Hashable>: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let icon: String
    let options: [Option]
    let label: KeyPath<Option, String>
    @Binding var selectedOption: Option?

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
                        title: option[keyPath: label],
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
