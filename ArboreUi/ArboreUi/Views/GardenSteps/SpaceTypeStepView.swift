import SwiftUI

struct SpaceTypeStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_SPACE_TITLE"))
                        .font(.system(size: 28, weight: .bold))

                    Text(L10n.t("WIZARD_SPACE_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        ForEach(GardenSpaceType.allCases) { spaceType in
                            SpaceTypeCard(
                                spaceType: spaceType,
                                isSelected: state.spaceType == spaceType
                            ) {
                                state.spaceType = spaceType
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                    .padding(.bottom, 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onNext) {
                    HStack {
                        Text(L10n.t("COMMON_CONTINUE"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.spaceType != nil))
                .disabled(state.spaceType == nil)

                Button(L10n.t("COMMON_BACK")) { onBack() }
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0),
                        Color.gardenBackground.opacity(0.99),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

private struct SpaceTypeCard: View {
    let spaceType: GardenSpaceType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Image(spaceType.imageName)
                    .resizable()
                    .scaledToFill()
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.05),
                                Color.black.opacity(0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 160, height: 200)
                    .clipped()

                Text(spaceType.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(14)
            }
            .frame(width: 160, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isSelected ? Color.gardenAccent : .clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.gardenAccent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(10)
                }
            }
            .shadow(
                color: isSelected
                    ? Color.gardenAccent.opacity(0.4)
                    : Color.black.opacity(0.12),
                radius: isSelected ? 12 : 6,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }
}
