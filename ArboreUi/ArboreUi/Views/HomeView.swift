import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @ObservedObject var plantService = PlantService()
    @StateObject var userService = UserService()
    @EnvironmentObject var themeManager: ThemeManager

    // MOCKS – à brancher ensuite sur ton backend / services
    @State private var userName: String = "Hugo"
    @State private var userError: String? = nil
    @State private var currentUID: String = ""
    @State private var profileImageURL: URL? = URL(string:
        "https://lh3.googleusercontent.com/aida-public/AB6AXuDWmaHAl_C1VSIzZLeaHvIVQY7q_1XPTw4E1bwkpalrEtAoGOdI0CHFIjQhQPPf6GHMZcwxa0gMOdFsuvzbuJ9tjcmxkegeBHpegLpCN9k86jE05YcooVOCcq40CJoT_cdl3Wm3uFEEZgztfDxDF3uaUfon17L2LiN_3wWH7USt2-uOFUQ8GcgeWxKN5RKf51dJGyRpkbnMxSD5MIwJy_sUnENID4G7OLEPSHtF16ljGHVmOepfnUbwBtAH8SdLbbwGrtOVUUrG9AI"
    )

    @State private var heroImageURL: URL? = URL(string:
        "https://lh3.googleusercontent.com/aida-public/AB6AXuCe_3do_emvEEcKrzXhX4NPE_KEXqIfqls06OPVJAHBZByFJaHRvcbjgdSaNmzLmjYQZQ9uubbD1w3vLjaAho6PCId_U5a84LblSIhhh438CjGSbqoyRlXAcq0-Ms8AK7sWfGFqJefH8o9krWdE688UHBiWnD81Y1bFpjYP2fCIgDbp0fFcEkVvx4-vwo54HTkTdn4q4tPUL4USXAkri6t6WfOWV24goEy0z5LqQl0AC1NljyVqeMl3Auwh4UmHWECjVq25dlCwFVw"
    )

    @State private var sponsorLogoURL: URL? = URL(string:
        "https://lh3.googleusercontent.com/aida-public/AB6AXuB1UhsiroUqp2E8eHgsZtuDXFvcC-Um0gl0Zn9ttiq-NQ3UbkvW_bz4NYs9AN7TiJGkJfm3GNQEg2Pl95t4QnlmokqfBvxaEdddQuL1vsngT1_qgdgEp5J8i1GCxvdpSE_X6_-8kdnutqC30hOKXWdPZ-Gv_UfFaXvoYB2tkeNmQYEr18Grgca-HB8hqetoJVjOOtk530HfjVuvnauGwBC0Wd4q-7Wwpt_cF51NPv2WOUCOCoC5fxZjFFGS_h-6Ues8o5PMBsM27kM"
    )

    // Données du résumé quotidien
    @State private var plantCount: Int = 12
    @State private var weatherTemp: String = "18°"
    @State private var weatherDesc: String = "Partiellement nuageux"
    @State private var plantsToWater: Int = 2
    @State private var healthStatus: String = "Stable"

    // Couleurs du design HTML
    private let primary = Color(hex: "#13EC5B")
    private let cardDark = Color(hex: "#28392E")
    private let cardDarkSoft = Color(hex: "#28392E").opacity(0.5)

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond noir, comme tu veux
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        profileHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        futureGardenCard
                            .padding(.horizontal, 16)
                            .padding(.top, 24)

                        // RÉSUMÉ QUOTIDIEN
                        Text("Résumé Quotidien")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        dailySummaryGrid
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        // SPONSOR
                        sponsorBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadUserData()
                plantService.fetchPlants()
            }
        }
    }
}

// MARK: - Header

private extension HomeView {
    var profileHeader: some View {
        HStack(spacing: 12) {
            // Image profil
            AsyncImage(url: profileImageURL) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                case .failure:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.8))
                        )
                        .frame(width: 64, height: 64)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bonjour \(userName)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text("Vue d’ensemble de ton univers végétal 🌱")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#9DB9A6"))
            }

            Spacer()
        }
    }
}

// MARK: - Futur Jardin

private extension HomeView {
    var futureGardenCard: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroImageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 220)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                case .failure:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 220)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Jardin japonais")
                            .font(.system(size: 22, weight: .bold))
                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.white)

                    Text("Allée en gravier, érables rouges, lanternes en pierre et zone repos.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    chip(icon: "sun.max.fill", text: "Lumière adaptée")
                    chip(icon: "drop.fill", text: "Sol drainant")
                }

                Button {
                    // TODO: ouvrir la visualisation AR
                } label: {
                    Text("Ouvrir la visualisation")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#102216"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Résumé Quotidien

private extension HomeView {
    var dailySummaryGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardDarkSoft)

            LazyVGrid(columns: columns, spacing: 12) {
                metricCard(
                    icon: "leaf.fill",
                    title: "Dans ton jardin",
                    value: "\(plantCount)"
                )

                metricCard(
                    icon: "cloud.sun.fill",
                    title: weatherDesc,
                    value: weatherTemp
                )

                metricCard(
                    icon: "drop.fill",
                    title: "À arroser aujourd'hui",
                    value: "\(plantsToWater) plantes"
                )

                metricCard(
                    icon: "heart.fill",
                    title: "Aucune alerte",
                    value: healthStatus
                )
            }
            .padding(8)
        }
    }

    func metricCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(primary)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardDark)
        )
    }
}

// MARK: - Sponsor

private extension HomeView {
    var sponsorBanner: some View {
        HStack(spacing: 12) {
            AsyncImage(url: sponsorLogoURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 48, height: 48)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .failure:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 48, height: 48)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Green&Co Terreau Premium")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text("Le meilleur pour vos plantes.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            Spacer()

            Button {
                // TODO: ouvrir l’offre sponsorisée
            } label: {
                Text("Découvrir")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(primary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardDarkSoft)
        )
    }
}

// MARK: - User

private extension HomeView {
    func loadUserData() {
        if let uid = Auth.auth().currentUser?.uid {
            self.currentUID = uid
            userService.fetchUser(by: uid) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let user):
                        let first = user.name.components(separatedBy: " ").first
                        self.userName = first ?? userName
                        self.userError = nil
                    case .failure(let error):
                        self.userError = "Impossible de récupérer l'utilisateur : \(error.localizedDescription)"
                    }
                }
            }
        } else {
            self.userError = "Utilisateur non connecté."
        }
    }
}

// MARK: - Preview

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(ThemeManager())
    }
}
