import SwiftUI

struct UpgradePlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: String = "Premium"
    
    let plans: [PlanModel] = [
        PlanModel(
            name: "Standard",
            price: "Gratuit",
            description: "Votre plan actuel",
            features: ["Accès basique", "1 panier", "Support communautaire"],
            isPopular: false
        ),
        PlanModel(
            name: "Premium",
            price: "9,99€/mois",
            description: "Le plus populaire",
            features: [
                "Accès illimité",
                "5 paniers",
                "Suivi avancé",
                "Support prioritaire",
                "1 RevPoint par 4€ dépensé"
            ],
            isPopular: true
        ),
        PlanModel(
            name: "Ultra",
            price: "19,99€/mois",
            description: "Pour les experts",
            features: [
                "Tout de Premium",
                "Paniers illimités",
                "API access",
                "Support 24/7",
                "1,5 RevPoint par 4€ dépensé",
                "Badge exclusif"
            ],
            isPopular: false
        )
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // En-tête
                        VStack(spacing: 8) {
                            Text("Choisissez votre plan")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            
                            Text("Débloquez plus de fonctionnalités")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        
                        // Plans
                        VStack(spacing: 12) {
                            ForEach(plans, id: \.name) { plan in
                                PlanCardView(
                                    plan: plan,
                                    isSelected: selectedPlan == plan.name,
                                    action: { selectedPlan = plan.name }
                                )
                                .environmentObject(themeManager)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Détails du plan sélectionné
                        if let selectedPlanModel = plans.first(where: { $0.name == selectedPlan }) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Inclus dans \(selectedPlanModel.name)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                    .padding(.horizontal, 16)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(selectedPlanModel.features, id: \.self) { feature in
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 14))
                                            
                                            Text(feature)
                                                .font(.system(size: 14))
                                                .foregroundColor(themeManager.textColor)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(themeManager.cardBackgroundColor)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        // Bouton d'action
                        if selectedPlan != "Standard" {
                            Button(action: {
                                // Logique d'achat
                                dismiss()
                            }) {
                                Text("S'abonner à \(selectedPlan)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.5, green: 0.3, blue: 1),
                                                Color(red: 0.3, green: 0.5, blue: 1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 16)
                        } else {
                            Text("Vous êtes déjà sur ce plan")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(themeManager.cardBackgroundColor)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Questions ?")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor)
                            
                            Link("Contactez le support", destination: URL(string: "mailto:support@arbore.app") ?? URL(fileURLWithPath: ""))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(themeManager.textColor)
                    }
                }
            }
        }
    }
}

// MARK: - Plan Card View
struct PlanCardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let plan: PlanModel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(plan.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                            
                            if plan.isPopular {
                                Text("POPULAIRE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(plan.description)
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    
                    Spacer()
                    
                    Text(plan.price)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                }
                
                if isSelected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Sélectionné")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? Color.blue.opacity(0.1) : themeManager.cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.blue : Color.clear,
                        lineWidth: 2
                    )
            )
        }
    }
}

// MARK: - Plan Model
struct PlanModel {
    let name: String
    let price: String
    let description: String
    let features: [String]
    let isPopular: Bool
}

#Preview {
    UpgradePlanView()
        .environmentObject(ThemeManager())
}