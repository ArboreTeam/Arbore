import SwiftUI

struct HomeView: View {
    @State private var projects: [GardenProject] = []
    @State private var goToQuestionnaire = false

    // Palette proche de ton design HTML
    private let background = Color(hex: "#F9F9F7")
    private let primary = Color(hex: "#8DBA8E")
    private let textDark = Color(hex: "#333333")
    private let textSubtle = Color(hex: "#63886f")
    private let cardLight = Color.white

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // MARK: - HEADER CENTRÉ
                        header

                        // MARK: - CARTE "CRÉER UN JARDIN"
                        createGardenHero

                        // MARK: - VOS JARDINS
                        gardensTitle

                        if projects.isEmpty {
                            emptyState
                        } else {
                            gardensList
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadMockProjectsIfNeeded()   // à remplacer plus tard par ton backend
            }
        }
    }
}

// MARK: - Header "Arbore" centré
private extension HomeView {
    var header: some View {
        VStack(spacing: 8) {
            Text("Arbore")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundColor(textDark)
                .multilineTextAlignment(.center)

            Text("Imaginez et visualisez\nvotre futur jardin")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(textSubtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private extension HomeView {
    var createGardenHero: some View {

        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(primary.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 22))
                        .foregroundColor(primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Créer un futur jardin")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(textDark)

                    Text("Commencez la conception étape par étape.")
                        .font(.system(size: 15))
                        .foregroundColor(textSubtle)
                }
            }

            Button {
                createNewGarden()
                goToQuestionnaire = true
            } label: {
                Text("Commencer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            NavigationLink(
                destination: GardenWizardView(
                    uid: "TEST_UID",
                    onGardenCreated: { created in
                        print("✅ Garden créé en Mongo:", created.id ?? "nil")
                    },
                    onFinish: { state in
                        print("Garden wizard completed")
                    }
                ),
                isActive: $goToQuestionnaire,
                label: { EmptyView() }
            )
            .hidden()

        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardLight)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Titre "Vos jardins"
private extension HomeView {
    var gardensTitle: some View {
        HStack {
            Text("Vos jardins")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(textDark)

            Spacer()

            if projects.count > 2 {
                NavigationLink {
                    AllGardensView(projects: projects)
                } label: {
                    HStack(spacing: 4) {
                        Text("Voir tout")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(primary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - État vide (aucun jardin)
private extension HomeView {
    var emptyState: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aucun jardin pour le moment")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDark)

                Text("Vos jardins enregistrés apparaîtront ici.\nCommencez par en créer un nouveau.")
                    .font(.system(size: 14))
                    .foregroundColor(textSubtle)
            }
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 28))
                .foregroundColor(primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
        )
    }
}

// MARK: - Liste des jardins existants
private extension HomeView {
    var gardensList: some View {
        let displayedProjects = Array(projects.prefix(2))

        return VStack(spacing: 16) {
            ForEach(displayedProjects, id: \.id) { project in
                gardenCard(project: project)
            }
        }
    }

    func gardenCard(project: GardenProject) -> some View {
        Button {
            // TODO : ouvrir le projet
        } label: {
            VStack(spacing: 0) {

                // IMAGE (haut de la carte)
                LinearGradient(
                    colors: [Color(hex: "#2F5136"), Color(hex: "#4F7B54")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "leaf.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.12))
                        .padding(30)
                )
                .frame(height: 140)

                // CONTENU (bas de la carte)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textDark)

                        Text("\(project.plantingZones.count) plantes")
                            .font(.system(size: 13))
                            .foregroundColor(textSubtle)

                        Text("Dernière modification : \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 12))
                            .foregroundColor(textSubtle.opacity(0.9))
                    }

                    Spacer()

                    Text("Ouvrir")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .padding(16)
            }
            .background(cardLight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vue "Tous les jardins"

struct AllGardensView: View {
    let projects: [GardenProject]

    private let background = Color(hex: "#F9F9F7")
    private let textDark = Color(hex: "#333333")

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            List {
                ForEach(projects, id: \.id) { project in
                    Text(project.name)
                        .foregroundColor(textDark)
                }
            }
        }
        .navigationTitle("Tous les jardins")
    }
}

// MARK: - Mock temporaire
private extension HomeView {
    func createNewGarden() {
        let garden = GardenProject(name: "Nouveau jardin")
        projects.insert(garden, at: 0)
    }

    func loadMockProjectsIfNeeded() {
        // Pour tester le design avec des jardins existants,
        // commente cette ligne pour voir l’état vide.
        projects = [
            GardenProject(name: "Terrasse ensoleillée"),
            GardenProject(name: "Jardin avant fleuri"),
            GardenProject(name: "Grand jardin familial")
        ]
    }
}
