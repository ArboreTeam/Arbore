import SwiftUI

struct PlantDetailView: View {
    let plantID: String
    @State private var plant: Plant?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isLiked: Bool = false
    @State private var showARView = false
    @State private var currentPage = 0
    @State private var showFullDescription = false
    @State private var showGallery = false
    @State private var showGalleryOverlay = false
    @State private var galleryStartIndex = 0
    @State private var isAddedToGarden = false
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // ✅ Top Bar
            ZStack(alignment: .bottom) {
                Color(hex: "#263826")
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 75)

                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.headline)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(plant?.translations[selectedLanguage]?["nom"] ?? plant?.name ?? "")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text((plant?.translations[selectedLanguage]?["type"] ?? plant?.type ?? "Type inconnu").capitalized)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: { isLiked.toggle() }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .white)
                            .font(.title2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            if isLoading {
                ProgressView("Chargement de la plante...")
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding()
            } else if let errorMessage = errorMessage {
                Text("\u{274C} \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            } else if let plant = plant {
                let t = plant.translations[selectedLanguage] ?? [:]

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ✅ Image principale avec bouton superposé
                        ZStack(alignment: .bottom) {
                            GeometryReader { geo in
                                let offset = geo.frame(in: .named("scroll")).minY

                                AsyncImage(url: URL(string: plant.imageURLs.first ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: UIScreen.main.bounds.width, height: offset > 0 ? 320 + offset : 320)
                                        .clipped()
                                        .offset(y: offset > 0 ? -offset : 0)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                        .frame(height: 320)
                                        .overlay(ProgressView())
                                }
                            }
                            .frame(height: 320)
                        }
                        .frame(height: 320)

                        // ✅ Fond incurvé + contenu
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 32)
                                .fill(colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED"))
                                .padding(.top, -32)
                                .padding(.bottom, -200)

                            VStack(alignment: .leading, spacing: 24) {
                                
                                // ✅ Bouton flottant bien par-dessus le fond incurvé
                                HStack {
                                    Spacer() // pousse le bouton vers la droite

                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            isAddedToGarden = true
                                        }
                                    }) {
                                        Text(isAddedToGarden ? "🌱 Déjà ajouté !" : "Ajouter à mon jardin")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(isAddedToGarden ? Color(hex: "#B5D3B2") : Color(hex: "#263826"))
                                            .foregroundColor(isAddedToGarden ? Color(hex: "#263826") : .white)
                                            .cornerRadius(20)
                                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                    }
                                    
                                    Spacer()
                                }
                                .offset(y: -50)
                                .padding(.bottom, -80)
                                
                                //description
                                HStack {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 10) {
                                            Image("description_icon")
                                                .resizable()
                                                .renderingMode(.template)
                                                .foregroundColor(Color(hex: "#263826"))
                                                .frame(width: 25, height: 25)

                                            Text("Description")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#2C2F24"))

                                            Spacer()
                                        }

                                        Text(t["description"] ?? plant.description)
                                            .font(.system(size: 15))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "#2C2F24"))
                                            .lineLimit(showFullDescription ? nil : 2)
                                            .fixedSize(horizontal: false, vertical: true)

                                        if (t["description"] ?? plant.description).count > 100 {
                                            Button(action: {
                                                withAnimation {
                                                    showFullDescription.toggle()
                                                }
                                            }) {
                                                Text(showFullDescription ? "Lire moins" : "Lire plus")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(Color(hex: "#263826"))
                                            }
                                        }
                                    }
                                    .padding(20)
                                    .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color(hex: "#D9E0D2"))
                                    .cornerRadius(20)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 4)
                                }
                                .frame(maxWidth: 380)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)

                                // Cartes infos
                                GeneralInfoGridView()

                                // AR View
                                VStack(spacing: 12) {
                                    Text("Voir la plante en Réalité Virtuelle")
                                        .font(.headline)
                                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#263826"))

                                    Text("Utilisez votre caméra pour visualiser cette plante dans votre environnement réel.")
                                        .font(.subheadline)
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)

                                    Image("plant_scanner_placeholder")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 180)
                                        .padding(.vertical, 8)

                                    Button(action: {
                                        showARView = true
                                    }) {
                                        Text("Commencer maintenant")
                                            .foregroundColor(.white)
                                            .fontWeight(.semibold)
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(Color(hex: "#263826"))
                                            .cornerRadius(12)
                                    }
                                    .fullScreenCover(isPresented: $showARView) {
                                        if let modelURLString = plant.modelURL, let url = URL(string: modelURLString) {
                                            ARViewWrapper(modelURL: url)
                                        } else {
                                            Text("\u{274C} Modèle AR non disponible.")
                                        }
                                    }
                                }
                                .padding()
                                .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                                .cornerRadius(20)
                                
                                // ✅ Galerie stylée dans une carte
                                if plant.imageURLs.count > 1 {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "#263826").opacity(0.1))
                                                    .frame(width: 32, height: 32)
                                                Image(systemName: "photo.on.rectangle")
                                                    .foregroundColor(Color(hex: "#263826"))
                                            }

                                            Text("Galerie de la plante")
                                                .font(.headline)
                                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#263826"))

                                            Spacer()

                                            Button(action: {
                                                galleryStartIndex = 0
                                                showGallery = true
                                            }) {
                                                Text("Voir tout")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                                            }
                                        }
                                        .padding(.horizontal, 8)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(plant.imageURLs.prefix(3).indices, id: \.self) { index in
                                                    ZStack {
                                                        AsyncImage(url: URL(string: plant.imageURLs[index])) { image in
                                                            image
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: 120, height: 120)
                                                                .clipped()
                                                                .cornerRadius(16)
                                                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                                        } placeholder: {
                                                            Color.gray.opacity(0.2)
                                                                .frame(width: 120, height: 120)
                                                                .cornerRadius(16)
                                                                .overlay(ProgressView())
                                                        }
                                                        .onTapGesture {
                                                            galleryStartIndex = index
                                                            showGallery = true
                                                        }

                                                        if index == 2 && plant.imageURLs.count > 3 {
                                                            Rectangle()
                                                                .fill(Color.black.opacity(0.4))
                                                                .frame(width: 120, height: 120)
                                                                .cornerRadius(16)
                                                            Text("+\(plant.imageURLs.count - 3)")
                                                                .foregroundColor(.white)
                                                                .fontWeight(.bold)
                                                        }
                                                    }
                                                    .scaleEffect(0.98)
                                                    .onTapGesture {
                                                        galleryStartIndex = index
                                                        showGallery = true
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                    .padding()
                                    .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                                    .cornerRadius(20)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
                                    .padding(.bottom)
                                }
                                
                                ZStack {
                                    // 🌿 BANNIÈRE EN FOND (belle illustration lavande)
                                    Image("truffaut_banner_frame") // ← nom de l'image lavande dans tes assets
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 360)

                                    // 🛒 TON BOUTON ACTUEL (à garder tel quel)
                                    Button(action: {
                                        if let url = URL(string: "https://www.truffaut.com/recherche?q=\(plant.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Image("truffaut_cta") // ✅ ton bouton-image conservé
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: 300) // ← tu peux ajuster ici pour qu’il "flotte" bien dans la bannière
                                            .cornerRadius(20)
                                            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 28)



                            }
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                            .padding(.top, 5)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { fetchPlantDetails() }
        .overlay(
            Group {
                if showGallery, let plant = plant {
                    PlantPhotoGallery(images: plant.imageURLs, isPresented: $showGallery)
                }
            }
        )
    }

    func fetchPlantDetails() {
        guard let url = URL(string: "http://79.137.92.154:8080/plants/\(plantID)") else {
            self.errorMessage = "URL invalide"
            self.isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Erreur de connexion : \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Données non valides"
                    return
                }

                do {
                    self.plant = try JSONDecoder().decode(Plant.self, from: data)
                } catch {
                    self.errorMessage = "Erreur lors du décodage des données"
                }
            }
        }.resume()
    }
}

struct GeneralInfoGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.below.ecg.fill")
                    .foregroundColor(Color(hex: "#263826"))
                Text("Informations générales")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .padding(.horizontal)

            VStack(spacing: 14) {
                GeneralInfoCard(icon: "sun.max.fill", title: "Soleil", description: "Exposition, orientation", color: Color(hex: "#EEDB8B"), destination: SoleilDetailView())
                GeneralInfoCard(icon: "drop.fill", title: "Eau", description: "Fréquence, quantité", color: Color(hex: "#A4C3D7"), destination: EauDetailView())
                GeneralInfoCard(icon: "leaf.fill", title: "Terre & Pot", description: "Sol, drainage, pot", color: Color(hex: "#A7C6AD"), destination: TerreDetailView())
                GeneralInfoCard(icon: "cross.case.fill", title: "Santé", description: "Prévention, parasites, maladies", color: Color(hex: "#E6A6A1"), destination: SanteDetailView())
                GeneralInfoCard(icon: "calendar", title: "Cycle de vie", description: "Floraison, origine", color: Color(hex: "#EFCFAF"), destination: CycleDeVieView())
                GeneralInfoCard(icon: "brain.head.profile", title: "Entretien", description: "Conseils pratiques", color: Color(hex: "#C5B3E6"), destination: EntretienView())
            }
            .padding(.horizontal)
        }
    }
}

struct GeneralInfoCard<Destination: View>: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let destination: Destination
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 20, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            .padding()
            .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: 4, x: 0, y: 2)
        }
    }
}
