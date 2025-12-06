import SwiftUI

struct QuestionnaireView: View {

    // MARK: - Palette (même que Home)
    private let background = Color(hex: "#F9F9F7")
    private let primary = Color(hex: "#8DBA8E")
    private let textDark = Color(hex: "#333333")
    private let textSubtle = Color(hex: "#63886f")
    private let cardLight = Color.white

    // MARK: - États du questionnaire

    // 1. Type de jardin
    @State private var isIndoor: Bool = false
    @State private var isOutdoor: Bool = true

    // 2. Exposition
    @State private var selectedSunExposure: GardenInfo.SunExposure = .mixed

    // 3. Style
    @State private var selectedStyle: GardenPreferences.GardenStyle = .modern

    // 4. Entretien
    @State private var selectedMaintenance: GardenPreferences.MaintenanceLevel = .low

    // 5. Préférences diverses
    @State private var wantsFlowers: Bool = true
    @State private var wantsEdible: Bool = false
    @State private var hasChildren: Bool = false
    @State private var hasPets: Bool = false
    @State private var wantsEvergreen: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Contenu scrollable
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        header

                        gardenTypeSection

                        sunExposureSection

                        styleSection

                        maintenanceSection

                        preferencesSection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }

                // Bouton d’action en bas
                continueButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .background(
                        background
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .navigationTitle("Questionnaire")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Header

private extension QuestionnaireView {
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apprenons à connaître votre jardin")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(textDark)

            Text("Quelques questions rapides pour vous proposer des plantes adaptées.")
                .font(.system(size: 14))
                .foregroundColor(textSubtle)
        }
    }
}

// MARK: - Section type de jardin

private extension QuestionnaireView {
    var gardenTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Où se situe votre jardin ?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textDark)

            HStack(spacing: 10) {
                toggleChip(
                    title: "Intérieur",
                    isOn: Binding(
                        get: { isIndoor },
                        set: { newValue in
                            isIndoor = newValue
                            if !isIndoor && !isOutdoor {
                                isOutdoor = true
                            }
                        }
                    )
                )

                toggleChip(
                    title: "Extérieur",
                    isOn: Binding(
                        get: { isOutdoor },
                        set: { newValue in
                            isOutdoor = newValue
                            if !isIndoor && !isOutdoor {
                                isIndoor = true
                            }
                        }
                    )
                )

                toggleChip(
                    title: "Les deux",
                    isOn: Binding(
                        get: { isIndoor && isOutdoor },
                        set: { newValue in
                            isIndoor = newValue
                            isOutdoor = newValue
                        }
                    )
                )
            }
        }
        .padding(16)
        .background(cardLight)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Section exposition

private extension QuestionnaireView {
    var sunExposureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exposition au soleil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textDark)

            Text("Choisissez ce qui correspond le mieux à la majorité de la zone.")
                .font(.system(size: 13))
                .foregroundColor(textSubtle)

            WrapChipsView(
                items: GardenInfo.SunExposure.allCases,
                isSelected: { $0 == selectedSunExposure },
                label: { exposure in
                    Text(exposure.rawValue)
                },
                onTap: { exposure in
                    selectedSunExposure = exposure
                },
                primary: primary,
                textDark: textDark,
                textSubtle: textSubtle
            )
        }
        .padding(16)
        .background(cardLight)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Section style

private extension QuestionnaireView {
    var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style de jardin souhaité")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textDark)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GardenPreferences.GardenStyle.allCases, id: \.self) { style in
                        selectableCard(
                            title: style.rawValue,
                            isSelected: style == selectedStyle
                        ) {
                            selectedStyle = style
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(cardLight)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    func selectableCard(title: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? primary : textDark)

                Text(isSelected ? "Sélectionné" : "Appuyez pour choisir")
                    .font(.system(size: 12))
                    .foregroundColor(textSubtle.opacity(0.8))
            }
            .padding(12)
            .frame(minWidth: 140)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? primary.opacity(0.1) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? primary : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section entretien

private extension QuestionnaireView {
    var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Niveau d’entretien")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textDark)

            WrapChipsView(
                items: GardenPreferences.MaintenanceLevel.allCases,
                isSelected: { $0 == selectedMaintenance },
                label: { level in
                    Text(level.rawValue)
                },
                onTap: { level in
                    selectedMaintenance = level
                },
                primary: primary,
                textDark: textDark,
                textSubtle: textSubtle
            )
        }
        .padding(16)
        .background(cardLight)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Section préférences

private extension QuestionnaireView {
    var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Préférences")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textDark)

            VStack(alignment: .leading, spacing: 10) {
                toggleRow(title: "Je veux des fleurs", isOn: $wantsFlowers)
                toggleRow(title: "Je veux des plantes comestibles", isOn: $wantsEdible)
                toggleRow(title: "Il y a des enfants", isOn: $hasChildren)
                toggleRow(title: "Il y a des animaux", isOn: $hasPets)
                toggleRow(title: "Je veux des plantes persistantes (toute l’année)", isOn: $wantsEvergreen)
            }
        }
        .padding(16)
        .background(cardLight)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(textDark)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }
}

// MARK: - Bouton Continuer

private extension QuestionnaireView {
    var continueButton: some View {
        Button {
            // TODO:
            // 1. Construire GardenInfo + GardenPreferences à partir des réponses
            // 2. Les enregistrer dans le GardenProject courant
            // 3. Passer à l’étape suivante (scan / AR / résumé, etc.)
            dismiss()
        } label: {
            Text("Continuer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Helpers UI (chips)

/// Chip on/off simple (Intérieur / Extérieur / Les deux)
func toggleChip(title: String, isOn: Binding<Bool>) -> some View {
    Button {
        isOn.wrappedValue.toggle()
    } label: {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isOn.wrappedValue ? .white : Color(hex: "#8DBA8E"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isOn.wrappedValue
                ? Color(hex: "#8DBA8E")
                : Color(hex: "#E3EDE4")
            )
            .clipShape(Capsule())
    }
    .buttonStyle(.plain)
}

/// Wrapper générique pour des chips multi-lignes
struct WrapChipsView<Item: Hashable, Label: View>: View {
    let items: [Item]
    let isSelected: (Item) -> Bool
    let label: (Item) -> Label
    let onTap: (Item) -> Void
    let primary: Color
    let textDark: Color
    let textSubtle: Color

    var body: some View {
        FlexibleView(
            items: items,
            spacing: 8,
            alignment: .leading
        ) { item in
            Button {
                onTap(item)
            } label: {
                label(item)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isSelected(item) ? primary.opacity(0.15) : Color.white
                    )
                    .foregroundColor(isSelected(item) ? primary : textSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(
                                isSelected(item) ? primary : Color.gray.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Layout flexible pour les chips (wrap automatique)
struct FlexibleView<Items: Collection, Content: View>: View where Items.Element: Hashable {

    let items: Items
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Items.Element) -> Content

    init(items: Items,
         spacing: CGFloat,
         alignment: HorizontalAlignment,
         @ViewBuilder content: @escaping (Items.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return GeometryReader { geometry in
            ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
                ForEach(Array(items), id: \.self) { item in
                    content(item)
                        .padding(.all, 4)
                        .alignmentGuide(.leading) { dim in
                            if (abs(width - dim.width) > geometry.size.width) {
                                width = 0
                                height -= dim.height + spacing
                            }
                            let result = width
                            if item == items.last {
                                width = 0 // reset
                            } else {
                                width -= dim.width + spacing
                            }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last {
                                height = 0 // reset
                            }
                            return result
                        }
                }
            }
        }
        .frame(height: nil)
    }
}
