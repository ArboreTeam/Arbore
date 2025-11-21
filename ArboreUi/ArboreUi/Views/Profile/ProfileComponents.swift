import SwiftUI
import PhotosUI

// MARK: - Subscription Plan Card (AMÉLIORÉE V3)
struct SubscriptionPlanCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let currentPlanName: String
    
    // Définitions des plans traduits en français avec le texte du prix
    private let plansData: [String: (color: Color, icon: String, description: String, priceText: String)] = [
        "Standard": (
            color: .green,
            icon: "leaf.fill",
            description: "Fonctionnalités de base. Scans limités.",
            priceText: "Gratuit"
        ),
        "Premium": (
            color: Color(red: 0.1, green: 0.8, blue: 0.5), // Vert vif Premium
            icon: "sparkles.square.fill",
            description: "Abonnement Premium actif. Scans illimités et plus.",
            priceText: "Payant"
        ),
        "Metal": (
            color: Color(red: 0.6, green: 0.6, blue: 0.7), // Gris/Bleu Métal
            icon: "goforward.plus",
            description: "Abonnement Metal actif. Analyses et suivis avancés.",
            priceText: "Payant"
        ),
        "Ultra": (
            color: Color(red: 0.7, green: 0.5, blue: 0.9), // Violet/Bleu Ultra
            icon: "diamond.fill",
            description: "Abonnement Ultra actif. Expérience et support complets.",
            priceText: "Payant"
        )
    ]
    
    private var currentPlan: (color: Color, icon: String, description: String, priceText: String)? {
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
        let planTitle = currentPlanName == "Standard" ? "Plan Standard" : "Plan \(currentPlanName)"

        return AnyView(
            VStack(spacing: 0) {
                // Contenu de la carte
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        
                        // Icône du plan
                        Image(systemName: plan.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(planColor)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(planTitle)
                                .font(.system(size: 19, weight: .heavy))
                                .foregroundColor(themeManager.textColor)

                            Text(plan.description)
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .lineLimit(2)
                        }
                        
                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(plan.priceText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(planColor)
                            
                            // Badge de statut actif (utilisé dans la capture d'écran)
                            Text("Actif")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(planColor.opacity(0.85)))
                        }
                    }
                }
                .padding(18)
                // Le padding doit être appliqué à la VStack interne pour ne pas perturber l'overlay/stroke
            }
            .background(
                ZStack {
                    Color.gray.opacity(0.15)
                    
                    // Bordure stylisée avec accentuation supérieure
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
                    
                    // Bandeau d'accentuation (Implémentation stable et propre)
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
        Text("Plan non défini ou erreur de chargement.")
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
