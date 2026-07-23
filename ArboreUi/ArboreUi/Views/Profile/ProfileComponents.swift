import SwiftUI
import PhotosUI

// MARK: - Current plan card
struct SubscriptionPlanCard: View {
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.small, style: .continuous)
                    .fill(ArboreDesign.Colors.primaryGreen)
                    .frame(width: 52, height: 4)

                HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .frame(width: 46, height: 46)
                        .background(ArboreDesign.Colors.primaryGreen.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                        Text(L10n.t("PLAN_TITLE_STANDARD"))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text(L10n.t("SUBSCRIPTION_DESCRIPTION_STANDARD"))
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: ArboreDesign.Spacing.sm)

                    VStack(alignment: .trailing, spacing: ArboreDesign.Spacing.xs) {
                        Text(L10n.t("PLAN_FREE"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)

                        Text(L10n.t("SUBSCRIPTION_BADGE_ACTIVE"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, ArboreDesign.Spacing.xs)
                            .padding(.vertical, 5)
                            .background(ArboreDesign.Colors.primaryGreen)
                            .clipShape(Capsule())
                    }
                }
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
    SubscriptionPlanCard()
        .padding()
}
