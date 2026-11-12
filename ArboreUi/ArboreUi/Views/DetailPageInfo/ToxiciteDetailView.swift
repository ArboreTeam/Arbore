import SwiftUI

// MARK: - Sécurité du foyer
//
// Le catalogue porte un verdict de toxicité SOURCÉ pour 872 plantes, et
// jusqu'ici la fiche n'en montrait rien : la toxicité ne remontait qu'en badge
// de compatibilité dans le catalogue AR, et seulement si le questionnaire
// l'avait demandée. Quelqu'un qui consulte une plante hors de ce parcours
// n'avait aucun moyen de savoir.
//
// Trois principes tiennent cette vue :
//
//  1. **Les deux publics sont séparés.** Une plante peut être comestible pour
//     l'humain et détruire les globules rouges d'un chat — c'est le cas de la
//     ciboulette. Les afficher ensemble effacerait la distinction que tout le
//     travail de documentation a servi à établir.
//  2. **« Non établie » se dit, et ne se déguise pas.** 92 espèces du catalogue
//     sont dans ce cas, et ce ne sont pas des plantes rares : l'olivier, le
//     photinia, l'abélia. Les présenter comme sûres serait mentir ; les
//     présenter comme toxiques aussi.
//  3. **La provenance est montrée.** Un verdict sans source n'engage personne.
struct ToxiciteDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let profile: PlantBotanicalProfile?
    let flags: PlantFlags?
    var plantName: String?

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    audienceSection(
                        icon: "pawprint.fill",
                        titre: NSLocalizedString("TOXICITY_SECTION_PETS_TITLE", comment: ""),
                        fait: profile?.petToxicity,
                        repli: flags?.toxicToPets,
                        conseil: NSLocalizedString("TOXICITY_UNKNOWN_ADVICE_PETS", comment: "")
                    )
                    audienceSection(
                        icon: "figure.and.child.holdinghands",
                        titre: NSLocalizedString("TOXICITY_SECTION_CHILDREN_TITLE", comment: ""),
                        fait: profile?.childToxicity,
                        repli: flags?.toxicToChildren,
                        conseil: NSLocalizedString("TOXICITY_UNKNOWN_ADVICE_CHILDREN", comment: "")
                    )
                    avertissementGeneral
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("TOXICITY_NAV_TITLE", comment: ""))
    }

    // MARK: - Une section par public

    @ViewBuilder
    private func audienceSection(
        icon: String,
        titre: String,
        fait: PlantToxicityFact?,
        repli: Bool?,
        conseil: String
    ) -> some View {
        let etat = Etat(fait: fait, repli: repli)

        ToxiciteCarte(icon: icon, iconColor: etat.couleur, title: titre) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: etat.symbole)
                        .foregroundColor(etat.couleur)
                    Text(etat.libelle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(etat.couleur)
                }

                // La prose sourcée, quand la recherche en a produit une.
                if let detail = fait?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Le conseil de vérification, pour un verdict non établi.
                if etat.estIndetermine {
                    Text(conseil)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(etat.couleur.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let provenance = provenanceTexte(fait?.evidence) {
                    Text(provenance)
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Ce qu'on affiche, et qui ne se déduit pas d'un booléen.
    private struct Etat {
        let libelle: String
        let symbole: String
        let couleur: Color
        let estIndetermine: Bool

        init(fait: PlantToxicityFact?, repli: Bool?) {
            // Le verdict stocké décide. Le drapeau ne sert que de repli, et
            // seul son `true` porte une information : son `false` a longtemps
            // voulu dire à la fois « sûre » et « pas recherchée », donc il ne
            // vaut pas une innocuité démontrée.
            switch fait?.value {
            case .toxic: self.init(.toxique)
            case .irritant: self.init(.irritante)
            case .safe: self.init(.sure)
            case .unknown, .none:
                self.init(repli == true ? .toxique : .indeterminee)
            }
        }

        private enum Cas { case toxique, irritante, sure, indeterminee }

        private init(_ cas: Cas) {
            switch cas {
            case .toxique:
                libelle = NSLocalizedString("TOXICITY_VERDICT_TOXIC", comment: "")
                symbole = "exclamationmark.triangle.fill"
                couleur = Color(hex: "#DC2626")
                estIndetermine = false
            case .irritante:
                libelle = NSLocalizedString("TOXICITY_VERDICT_IRRITANT", comment: "")
                symbole = "exclamationmark.circle.fill"
                couleur = Color(hex: "#EA580C")
                estIndetermine = false
            case .sure:
                libelle = NSLocalizedString("TOXICITY_VERDICT_SAFE", comment: "")
                symbole = "checkmark.seal.fill"
                couleur = Color(hex: "#16A34A")
                estIndetermine = false
            case .indeterminee:
                libelle = NSLocalizedString("TOXICITY_VERDICT_UNKNOWN", comment: "")
                symbole = "questionmark.circle.fill"
                couleur = Color(hex: "#CA8A04")
                estIndetermine = true
            }
        }
    }

    /// « Source, consultée le … » — un verdict sans provenance n'engage personne.
    private func provenanceTexte(_ evidence: PlantDataEvidence?) -> String? {
        guard let evidence else { return nil }
        let nom = evidence.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let date = evidence.reviewedAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if nom.isEmpty && date.isEmpty { return nil }
        if date.isEmpty { return String(format: NSLocalizedString("TOXICITY_SOURCE_ONLY", comment: ""), nom) }
        if nom.isEmpty { return String(format: NSLocalizedString("TOXICITY_REVIEWED_ONLY", comment: ""), date) }
        return String(format: NSLocalizedString("TOXICITY_SOURCE_AND_DATE", comment: ""), nom, date)
    }

    // MARK: - L'avertissement qui vaut pour tous les verdicts

    private var avertissementGeneral: some View {
        ToxiciteCarte(
            icon: "info.circle.fill",
            iconColor: Color(hex: "#0EA5E9"),
            title: NSLocalizedString("TOXICITY_DISCLAIMER_TITLE", comment: "")
        ) {
            Text(NSLocalizedString("TOXICITY_DISCLAIMER_BODY", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryTextColor: Color { colorScheme == .dark ? .white : .black }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }
}

// MARK: - Carte

private struct ToxiciteCarte<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
