import SwiftUI

struct TermsConditionsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let brandName = "Arbore"
    private let contactEmail = "support@arbore.app"
    private let lastUpdated = "11 Nov 2025"

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar - Uniforme
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark") // Utiliser X pour la fermeture de vues modales pleines
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Terms & Conditions")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor) // Assurer un fond uni pour la barre

                ScrollView {
                    VStack(spacing: 18) { // Augmentation de l'espacement
                        headerCard

                        TermsCard(
                            title: "Acceptation des conditions",
                            icon: "checkmark.seal.fill",
                            items: [
                                "En créant un compte ou en utilisant \(brandName), vous acceptez les présentes Conditions.",
                                "Si vous n’acceptez pas ces Conditions, vous ne devez pas utiliser l’application."
                            ],
                            themeManager: themeManager
                        )
                        
                        // ... (Autres cartes TermsCard conservées) ...
                        TermsCard(
                            title: "Description du service",
                            icon: "leaf.fill",
                            items: [
                                "\(brandName) fournit des fonctionnalités liées au jardinage : scans de plantes, recommandations, visualisations, notifications et synchronisation.",
                                "Certaines fonctionnalités sont payantes et accessibles via des abonnements."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Comptes & sécurité",
                            icon: "person.crop.circle.fill",
                            items: [
                                "Vous êtes responsable de l’exactitude des informations de votre compte et de la confidentialité de vos identifiants.",
                                "Prévenez-nous immédiatement en cas d’usage non autorisé de votre compte."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Abonnements & facturation",
                            icon: "creditcard.fill",
                            items: [
                                "Les achats sont gérés par l’App Store / Play Store ; leurs conditions s’appliquent.",
                                "Les abonnements se renouvellent automatiquement jusqu’à annulation.",
                                "Les tarifs peuvent évoluer ; nous vous informerons des changements applicables."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Essais gratuits & annulation",
                            icon: "clock.badge.checkmark",
                            items: [
                                "Les essais gratuits, lorsqu’ils sont proposés, se convertissent en abonnement payant à la fin de la période, sauf annulation avant l’échéance.",
                                "Vous pouvez annuler votre abonnement à tout moment depuis les réglages de l’App Store / Play Store."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Contenu utilisateur",
                            icon: "photo.on.rectangle.angled",
                            items: [
                                "Vous conservez vos droits sur les photos et contenus que vous importez.",
                                "Vous nous accordez une licence mondiale, non exclusive et révocable pour héberger, traiter et afficher ce contenu uniquement afin de fournir le service.",
                                "Vous garantissez disposer des droits nécessaires pour partager ces contenus."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Utilisations interdites",
                            icon: "hand.raised.fill",
                            items: [
                                "Ingénierie inverse, contournement des mesures de sécurité, usage frauduleux ou illégal.",
                                "Interférence avec le service, surcharge des serveurs, collecte automatisée non autorisée.",
                                "Publication de contenus illégaux, offensants, diffamatoires ou portant atteinte aux droits d’autrui."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Propriété intellectuelle",
                            icon: "shield.lefthalf.filled",
                            items: [
                                "Le nom \(brandName), le logo, l’app et son contenu (hors contenu utilisateur) sont protégés par les droits de propriété intellectuelle.",
                                "Aucun droit de propriété ne vous est transféré du fait de l’usage de l’app."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Vie privée",
                            icon: "lock.shield.fill",
                            items: [
                                "Votre utilisation est également régie par notre Politique de confidentialité.",
                                "Cette politique explique les données collectées, leurs usages et vos droits."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Services tiers",
                            icon: "link.circle.fill",
                            items: [
                                "L’app peut intégrer des services tiers (hébergement, analytics, paiements).",
                                "Nous ne sommes pas responsables des pratiques ou contenus de ces services."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Disponibilité & modifications",
                            icon: "antenna.radiowaves.left.and.right",
                            items: [
                                "Nous pouvons mettre à jour, suspendre ou interrompre tout ou partie du service à tout moment, avec ou sans préavis.",
                                "Nous ne garantissons pas une disponibilité ininterrompue."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Limitation de responsabilité",
                            icon: "exclamationmark.triangle.fill",
                            items: [
                                "Dans les limites autorisées par la loi, \(brandName) ne saurait être responsable des dommages indirects, spéciaux, accessoires, consécutifs, pertes de données ou pertes de profits.",
                                "Votre seul recours en cas d’insatisfaction est de cesser d’utiliser l’app et, le cas échéant, d’annuler votre abonnement."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Indemnisation",
                            icon: "scales",
                            items: [
                                "Vous acceptez d’indemniser \(brandName) pour toute réclamation résultant d’une violation de ces Conditions ou d’un usage illégal de l’app."
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: "Loi applicable & juridiction",
                            icon: "globe.europe.africa.fill",
                            items: [
                                "Ces Conditions sont régies par le droit applicable dans votre pays de résidence si la loi locale l’impose, à défaut par le droit français.",
                                "Tout litige sera soumis aux tribunaux compétents du ressort déterminé par ces règles."
                            ],
                            themeManager: themeManager
                        )
                        // ... (Fin des autres cartes) ...

                        contactCard
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20) // Ajout de padding vertical
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Header (Mise à jour pour coins uniformes)
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions générales d’utilisation")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(themeManager.textColor)
            Text("Merci d’utiliser \(brandName). Veuillez lire attentivement ces Conditions : elles encadrent votre accès à l’app et son utilisation.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
            Text("Dernière mise à jour : \(lastUpdated)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor.opacity(0.9))
                .padding(.top, 2)
        }
        .padding(18) // Rembourrage uniforme
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) // Coins uniformes
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
            Text("Pour toute question ou réclamation liée aux présentes Conditions, contactez-nous.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)

            Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text(contactEmail)
                }
                .font(.system(size: 15, weight: .bold)) // Un peu plus audacieux
                .foregroundColor(.black)
                .padding(.vertical, 12) // Rembourrage uniforme
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white)) // Coins uniformes
            }
        }
        .padding(18) // Rembourrage uniforme
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) // Coins uniformes
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Footer note (Mise à jour pour coins uniformes)
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mises à jour des Conditions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            Text("Nous pouvons modifier ces Conditions pour refléter l’évolution de nos services et exigences légales. Nous vous informerons des changements importants dans l’app.")
                .font(.system(size: 13))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding(18) // Rembourrage uniforme
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) // Coins uniformes
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

// MARK: - Reusable Card (Mise à jour pour coins uniformes)
struct TermsCard: View {
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
