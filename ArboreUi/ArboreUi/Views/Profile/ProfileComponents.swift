import SwiftUI
import PhotosUI

// MARK: - Subscription Plan Card (AMÉLIORÉE V3, localisée)
struct SubscriptionPlanCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let currentPlanName: String

    // plansData now holds keys for localized strings
    private let plansData: [String: (color: Color, icon: String, descriptionKey: String, priceKey: String)] = [
        "Standard": (
            color: ArboreDesign.Colors.primaryGreen,
            icon: "leaf",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_STANDARD",
            priceKey: "PLAN_FREE"
        ),
        "Premium": (
            color: ArboreDesign.Colors.accentGold,
            icon: "sparkles",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_PREMIUM",
            priceKey: "PLAN_PAID"
        ),
        "Metal": (
            color: ArboreDesign.Colors.secondaryGreen,
            icon: "shield.lefthalf.filled",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_METAL",
            priceKey: "PLAN_PAID"
        ),
        "Ultra": (
            color: ArboreDesign.Colors.accentGold,
            icon: "diamond",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_ULTRA",
            priceKey: "PLAN_PAID"
        )
    ]

    private var currentPlan: (color: Color, icon: String, descriptionKey: String, priceKey: String)? {
        plansData[currentPlanName]
    }

    private var isFreePlan: Bool {
        currentPlanName == "Standard"
    }

    var body: some View {
        if let plan = currentPlan {
            planContent(plan)
        } else {
            emptyPlanView
        }
    }

    private func planContent(_ plan: (color: Color, icon: String, descriptionKey: String, priceKey: String)) -> some View {
        let planColor = isFreePlan ? ArboreDesign.Colors.primaryGreen : plan.color
        let description = NSLocalizedString(plan.descriptionKey, comment: "")
        let priceText = NSLocalizedString(plan.priceKey, comment: "")
        let activeBadge = NSLocalizedString("SUBSCRIPTION_BADGE_ACTIVE", comment: "Active badge")

        return AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.small, style: .continuous)
                    .fill(planColor)
                    .frame(width: 52, height: 4)

                HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                    Image(systemName: plan.icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(planColor)
                        .frame(width: 46, height: 46)
                        .background(planColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                        Text(planTitle)
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(description)
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: ArboreDesign.Spacing.sm)

                    VStack(alignment: .trailing, spacing: ArboreDesign.Spacing.xs) {
                        Text(priceText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(planColor)

                        Text(activeBadge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isFreePlan ? .white : ArboreDesign.Colors.textPrimary)
                            .padding(.horizontal, ArboreDesign.Spacing.xs)
                            .padding(.vertical, 5)
                            .background(planColor.opacity(isFreePlan ? 1 : 0.18))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var planTitle: String {
        if currentPlanName == "Standard" {
            return NSLocalizedString("PLAN_TITLE_STANDARD", comment: "Standard plan title")
        } else {
            return String(format: NSLocalizedString("PLAN_TITLE_FORMAT", comment: "Plan title format"), currentPlanName)
        }
    }

    private var emptyPlanView: some View {
        AppCard {
            HStack(spacing: ArboreDesign.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(ArboreDesign.Colors.danger)

                Text(NSLocalizedString("PLAN_UNDEFINED", comment: "Plan undefined message"))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Spacer()
            }
        }
    }
}

// MARK: - Setting Row Item
struct SettingRowItem {
    let icon: String
    let label: String
    let destination: AnyView
    let iconColor: Color

    init<V: View>(icon: String, label: String, destination: V, iconColor: Color = ArboreDesign.Colors.primaryGreen) {
        self.icon = icon
        self.label = label
        self.destination = AnyView(destination)
        self.iconColor = iconColor
    }
}

// MARK: - Destination Item
struct DestinationItem: Identifiable {
    let id = UUID()
    let view: AnyView
}

// MARK: - Photo Picker (PHPicker)
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass: UIImage.self) else {
                parent.onComplete(nil)
                return
            }
            item.loadObject(ofClass: UIImage.self) { image, error in
                DispatchQueue.main.async {
                    let uiimage = image as? UIImage
                    self.parent.selectedImage = uiimage
                    self.parent.onComplete(uiimage)
                }
            }
        }
    }
}

// Preview pour les composants
#Preview {
    SubscriptionPlanCard(currentPlanName: "Premium")
        .environmentObject(ThemeManager())
        .padding()
}
