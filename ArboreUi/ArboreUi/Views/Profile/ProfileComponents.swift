import SwiftUI
import PhotosUI

// MARK: - Subscription Plan Card (AMÉLIORÉE V3, localisée)
struct SubscriptionPlanCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let currentPlanName: String

    // plansData now holds keys for localized strings
    private let plansData: [String: (color: Color, icon: String, descriptionKey: String, priceKey: String)] = [
        "Standard": (
            color: .green,
            icon: "leaf.fill",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_STANDARD",
            priceKey: "PLAN_FREE"
        ),
        "Premium": (
            color: Color(red: 0.1, green: 0.8, blue: 0.5),
            icon: "sparkles.square.fill",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_PREMIUM",
            priceKey: "PLAN_PAID"
        ),
        "Metal": (
            color: Color(red: 0.6, green: 0.6, blue: 0.7),
            icon: "goforward.plus",
            descriptionKey: "SUBSCRIPTION_DESCRIPTION_METAL",
            priceKey: "PLAN_PAID"
        ),
        "Ultra": (
            color: Color(red: 0.7, green: 0.5, blue: 0.9),
            icon: "diamond.fill",
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
        guard let plan = currentPlan else {
            return AnyView(emptyPlanView)
        }

        let planColor = isFreePlan ? .green : plan.color
        let planTitle: String = {
            if currentPlanName == "Standard" {
                return NSLocalizedString("PLAN_TITLE_STANDARD", comment: "Standard plan title")
            } else {
                return String(format: NSLocalizedString("PLAN_TITLE_FORMAT", comment: "Plan title format"), currentPlanName)
            }
        }()

        let description = NSLocalizedString(plan.descriptionKey, comment: "")
        let priceText = NSLocalizedString(plan.priceKey, comment: "")
        let activeBadge = NSLocalizedString("SUBSCRIPTION_BADGE_ACTIVE", comment: "Active badge")

        return AnyView(
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: plan.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(planColor)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(planTitle)
                                .font(.system(size: 19, weight: .heavy))
                                .foregroundColor(themeManager.textColor)

                            Text(description)
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(priceText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(planColor)

                            Text(activeBadge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(planColor.opacity(0.85)))
                        }
                    }
                }
                .padding(18)
            }
            .background(
                ZStack {
                    Color.gray.opacity(0.15)

                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    planColor.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )

                    RoundedRectangle(cornerRadius: 18)
                        .fill(planColor)
                        .frame(height: 4)
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle().frame(height: 4)
                                Spacer()
                            }
                        )
                }
            )
            .cornerRadius(18)
            .shadow(color: planColor.opacity(0.25), radius: 8, x: 0, y: 4)
        )
    }

    private var emptyPlanView: some View {
        Text(NSLocalizedString("PLAN_UNDEFINED", comment: "Plan undefined message"))
            .foregroundColor(.red)
            .padding()
    }
}

// MARK: - Setting Row Item
struct SettingRowItem {
    let icon: String
    let label: String
    let destination: AnyView
    let iconColor: Color

    init<V: View>(icon: String, label: String, destination: V, iconColor: Color = .green) {
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