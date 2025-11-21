import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let brandName = "Arbore"
    private let contactEmail = "support@arbore.app"
    private let lastUpdated = "11 Nov 2025"

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with close button - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark") // Utiliser X
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Privacy Policy")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 18) { // Augmentation de l'espacement
                        headerCard

                        PolicyCard(
                            title: "Données que nous collectons",
                            icon: "tray.full.fill",
                            items: [
                                "Identité : nom, adresse e-mail, identifiant Firebase.",
                                "Utilisation : scans de plantes, préférences d'affichage, interactions dans l'app.",
                                "Appareil & diagnostics : version de l'app, modèle d'appareil, journaux de crash.",
                                "Contenu utilisateur : photos/visuels importés pour l'identification.",
                                "Achats : historiques d'abonnement (via App Store / Play Store)."
                            ],
                            themeManager: themeManager
                        )
                        
                        // ... (Autres PolicyCard conservées) ...
                        PolicyCard(
                            title: "Pourquoi nous les utilisons",
                            icon: "target",
                            items: [
                                "Fournir les fonctionnalités d'\(brandName) (scans, recommandations, sauvegardes).",
                                "Personnaliser l'expérience (styles, notifications météo, conseils).",
                                "Améliorer la qualité (analyses d'usage, corrections de bugs, sécurité).",
                                "Gérer l'abonnement et l'assistance client.",
                                "Respecter nos obligations légales."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Base légale (RGPD)",
                            icon: "doc.text.magnifyingglass",
                            items: [
                                "Exécution du contrat : fournir l'app et ses services.",
                                "Intérêts légitimes : améliorer et sécuriser \(brandName).",
                                "Consentement : notifications, accès caméra/photos.",
                                "Obligation légale : conservation liée à la facturation."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Conservation",
                            icon: "archivebox.fill",
                            items: [
                                "Nous conservons vos données aussi longtemps que nécessaire pour fournir le service.",
                                "Vous pouvez supprimer votre compte depuis le profil ; les données liées sont alors effacées ou anonymisées, sauf obligations légales."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Partage & destinataires",
                            icon: "arrow.2.squarepath",
                            items: [
                                "Fournisseurs techniques : hébergement, analytics, crash reporting.",
                                "Paiements & abonnements : App Store / Play Store.",
                                "Nous ne vendons pas vos données. Les transferts sont limités au nécessaire et encadrés par contrat."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Vos droits",
                            icon: "hand.raised.fill",
                            items: [
                                "Accès, rectification, portabilité, effacement.",
                                "Opposition et limitation dans les conditions prévues par la loi.",
                                "Retrait du consentement (ex. notifications) à tout moment.",
                                "Pour exercer vos droits, contactez-nous : \(contactEmail)."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Sécurité",
                            icon: "lock.shield.fill",
                            items: [
                                "Chiffrement en transit (HTTPS) et bonnes pratiques de sécurité.",
                                "Accès restreint aux seules personnes habilitées.",
                                "Sur mobile, protégez votre appareil (code, Face/Touch ID)."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Enfants",
                            icon: "person.2.wave.2.fill",
                            items: [
                                "\(brandName) ne vise pas les moins de 13 ans (ou l'âge légal local).",
                                "Si une collecte inappropriée nous est signalée, nous supprimerons les données concernées."
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: "Transferts internationaux",
                            icon: "globe.europe.africa.fill",
                            items: [
                                "Lorsque des données sont traitées hors UE/EEE, nous appliquons des garanties appropriées (clauses types, mesures complémentaires) conformément au RGPD."
                            ],
                            themeManager: themeManager
                        )
                        // ... (Fin des autres PolicyCard) ...

                        contactCard
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20) // Ajout de padding vertical
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Header (Mise à jour pour coins uniformes)
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(brandName) respecte votre vie privée.")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(themeManager.textColor)
            Text("Cette politique explique quelles données nous collectons, comment nous les utilisons et les choix dont vous disposez.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
            Text("Dernière mise à jour : \(lastUpdated)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor.opacity(0.9))
                .padding(.top, 2)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Contact card (Mise à jour pour coins uniformes et bouton noir/blanc)
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                Text("Nous contacter")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            Text("Pour toute question, demande d'accès ou suppression de données, écrivez-nous.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)

            Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text(contactEmail)
                }
                .font(.system(size: 15, weight: .bold)) // Un peu plus audacieux
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Footer note (Mise à jour pour coins uniformes)
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modifications de cette politique")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            Text("Nous pouvons mettre à jour cette politique pour refléter l'évolution de nos pratiques. Toute modification substantielle sera signalée dans l'app.")
                .font(.system(size: 13))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

// MARK: - Reusable Card (Mise à jour pour coins uniformes)
struct PolicyCard: View {
    let title: String
    let icon: String
    let items: [String]
    let themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { // Augmentation de l'espacement
            HStack(spacing: 12) { // Augmentation de l'espacement
                Image(systemName: icon)
                    .font(.system(size: 20)) // Icône plus grande
                    .foregroundColor(.green)
                Text(title)
                    .font(.system(size: 17, weight: .bold)) // Plus audacieux
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.green.opacity(0.9))
                            .padding(.top, 6)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18) // Rembourrage uniforme
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) // Coins uniformes
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
