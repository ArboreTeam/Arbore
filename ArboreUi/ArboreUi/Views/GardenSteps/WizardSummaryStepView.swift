import SwiftUI
import RoomPlan

struct WizardSummaryStepView: View {
    @ObservedObject var state: GardenWizardState
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var goToGardenMeasure = false
    @State private var goToRoomScan = false
    @State private var showLidarAlert = false   // 🔥 pour les devices sans LiDAR
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Fond de la carte de récap
    private var recapBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.06)
        : Color.white
    }
    
    private var recapShadow: Color {
        colorScheme == .dark
        ? Color.black.opacity(0.6)
        : Color.black.opacity(0.05)
    }
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Titre + emoji
                VStack(spacing: 24) {
                    Text("🎉")
                        .font(.system(size: 100))
                    
                    Text("Parfait !")
                        .font(.system(size: 36, weight: .bold))
                    
                    Text("Nous avons toutes les informations nécessaires pour analyser votre espace et vous suggérer les plantes idéales.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineSpacing(4)
                }
                
                // Carte récap
                VStack(alignment: .leading, spacing: 16) {
                    if let style = state.style {
                        RecapRow(emoji: style.emoji, title: "Style", value: style.title)
                    }
                    if let spaceType = state.spaceType {
                        RecapRow(emoji: spaceType.emoji, title: "Espace", value: spaceType.title)
                    }
                    if let exposure = state.exposure {
                        RecapRow(emoji: exposure.emoji, title: "Exposition", value: exposure.title)
                    }
                    if let maintenance = state.maintenance {
                        RecapRow(emoji: maintenance.emoji, title: "Entretien", value: maintenance.title)
                    }
                    if !state.safetySelections.isEmpty {
                        let safetyText = state.safetySelections
                            .sorted(by: { $0.rawValue < $1.rawValue })
                            .map { $0.title }
                            .joined(separator: ", ")
                        RecapRow(emoji: "🛡️", title: "Contraintes", value: safetyText)
                    }
                    if let soil = state.soil {
                        RecapRow(emoji: soil.emoji, title: "Sol", value: soil.title)
                    }
                }
                .padding(24)
                .background(recapBackground)
                .cornerRadius(20)
                .shadow(color: recapShadow, radius: 10, x: 0, y: 4)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                
                Spacer()
            }
            
            // NAVIGATION LINKS CACHÉS
            NavigationLink(
                destination: GardenMeasureView(),
                isActive: $goToGardenMeasure,
                label: { EmptyView() }
            )
            .hidden()
            
            NavigationLink(
                destination: RoomScanListView(),
                isActive: $goToRoomScan,
                label: { EmptyView() }
            )
            .hidden()
        }
        // Footer boutons + dégradé qui remonte
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: {
                    // Optionnel : persister les réponses
                    onFinish()
                    
                    // 🚀 Choix de la méthode en fonction de scanMethod
                    switch state.scanMethod {
                    case .some(.gardenPerimeter):
                        goToGardenMeasure = true
                        
                    case .some(.roomScan):
                        if RoomCaptureSession.isSupported {
                            goToRoomScan = true
                        } else {
                            showLidarAlert = true
                        }
                        
                    case .none:
                        // Fallback : si l’utilisateur n’a pas choisi
                        if RoomCaptureSession.isSupported {
                            goToRoomScan = true
                        } else {
                            goToGardenMeasure = true
                        }
                    }
                }) {
                    HStack {
                        Text("Scanner mon espace en AR")
                        Image(systemName: "camera.fill")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))
                
                Button("Retour") { onBack() }
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0.0),
                        Color.gardenBackground.opacity(0.9),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)          // ← fait remonter le “flou”
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .alert("Scan 3D indisponible", isPresented: $showLidarAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
            Cette méthode utilise le scanner LiDAR.
            Ton appareil ne dispose pas de LiDAR (ex : iPhone Pro / iPad Pro uniquement).

            Tu peux continuer avec la méthode de mesure classique !
            """)
        }
    }
}
