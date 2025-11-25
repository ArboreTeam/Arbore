//
//  LocationStepView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI
import CoreLocation
import MapKit

struct LocationStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    @EnvironmentObject var themeManager: ThemeManager
    
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), // Paris par défaut
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showingMap = false
    
    var body: some View {
        VStack(spacing: 24) {
            // En-tête
            StepHeader(
                icon: "location.fill",
                title: "Localisation",
                description: "Partagez votre localisation pour des recommandations adaptées au climat local"
            )
            
            // Pourquoi c'est important
            VStack(alignment: .leading, spacing: 12) {
                Label("Pourquoi c'est important ?", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                VStack(spacing: 8) {
                    BenefitRow(
                        icon: "thermometer.sun.fill",
                        text: "Plantes adaptées à votre zone climatique"
                    )
                    
                    BenefitRow(
                        icon: "calendar",
                        text: "Calendrier de plantation personnalisé"
                    )
                    
                    BenefitRow(
                        icon: "leaf.fill",
                        text: "Suggestions de plantes locales robustes"
                    )
                    
                    BenefitRow(
                        icon: "snowflake",
                        text: "Zone de rusticité et résistance au gel"
                    )
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            // État de la localisation
            if let location = project.location {
                LocationCard(location: location, onUpdate: {
                    requestLocation()
                })
            } else {
                // Demande de localisation
                VStack(spacing: 16) {
                    if locationManager.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Récupération de votre position...")
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryTextColor)
                    } else {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue.opacity(0.7))
                        
                        Text("Localisation non définie")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        
                        Text("Autorisez l'accès à votre position pour des recommandations précises")
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryTextColor)
                            .multilineTextAlignment(.center)
                        
                        Button(action: requestLocation) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Partager ma position")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            showingMap = true
                        }) {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("Sélectionner sur la carte")
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(12)
            }
            
            // Note de confidentialité
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    
                    Text("Vos données sont sécurisées")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.textColor)
                }
                
                Text("Nous n'utilisons votre localisation que pour les recommandations de plantes. Elle n'est jamais partagée.")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(12)
            
            Spacer()
        }
        .sheet(isPresented: $showingMap) {
            MapSelectionView(region: $region, onSelect: { coordinate in
                saveLocation(coordinate: coordinate)
                showingMap = false
            })
        }
        .onChange(of: locationManager.location) { oldValue, newValue in
            if let location = newValue {
                saveLocation(coordinate: location.coordinate)
            }
        }
        .alert("Erreur de localisation", isPresented: $locationManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(locationManager.errorMessage)
        }
    }
    
    // MARK: - Helper Methods
    private func requestLocation() {
        locationManager.requestLocation()
    }
    
    private func saveLocation(coordinate: CLLocationCoordinate2D) {
        let locationData = LocationData(coordinate: coordinate)
        projectService.saveLocation(for: project.id, location: locationData)
        
        // Géocodage inverse pour obtenir la ville
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                var updatedLocation = locationData
                // Note: Les propriétés sont let, donc on devrait recréer l'objet
                // Pour simplifier, on suppose qu'on ajoutera ces infos plus tard
            }
        }
    }
}

// MARK: - Location Card
struct LocationCard: View {
    let location: LocationData
    let onUpdate: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text("Localisation enregistrée")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                    }
                    
                    if let city = location.city {
                        Text(city)
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    
                    Text("Lat: \(String(format: "%.4f", location.latitude)), Lon: \(String(format: "%.4f", location.longitude))")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
            }
            
            // Informations climatiques
            if let climateZone = location.climateZone ?? "Tempéré" as String? {
                HStack(spacing: 16) {
                    ClimateInfoCard(
                        icon: "cloud.sun.fill",
                        title: "Climat",
                        value: climateZone
                    )
                    
                    if let temp = location.averageTemperature {
                        ClimateInfoCard(
                            icon: "thermometer",
                            title: "Temp. moy.",
                            value: "\(Int(temp))°C"
                        )
                    }
                    
                    if let zone = location.hardinessZone {
                        ClimateInfoCard(
                            icon: "snowflake",
                            title: "Zone",
                            value: zone
                        )
                    }
                }
            }
            
            Button(action: onUpdate) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Mettre à jour")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Climate Info Card
struct ClimateInfoCard: View {
    let icon: String
    let title: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(themeManager.textColor)
            
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(themeManager.cardBackgroundColor)
        .cornerRadius(8)
    }
}

// MARK: - Benefit Row
struct BenefitRow: View {
    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(themeManager.textColor)
            
            Spacer()
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        isLoading = true
        
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "L'accès à la localisation a été refusé. Veuillez l'autoriser dans les Réglages."
            showError = true
        @unknown default:
            isLoading = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
        isLoading = false
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Impossible de récupérer votre position. Veuillez réessayer."
        showError = true
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

// MARK: - Map Selection View
struct MapSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var region: MKCoordinateRegion
    let onSelect: (CLLocationCoordinate2D) -> Void
    
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, annotationItems: selectedCoordinate.map { [MapPin(coordinate: $0)] } ?? []) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: .green)
                }
                .onTapGesture { location in
                    // Convertir la position du tap en coordonnées
                    // Note: nécessite une implémentation plus complexe avec MapKit
                }
                
                VStack {
                    Spacer()
                    
                    Button(action: {
                        if let coordinate = selectedCoordinate {
                            onSelect(coordinate)
                        } else {
                            onSelect(region.center)
                        }
                    }) {
                        Text("Confirmer cette position")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                            .padding()
                    }
                }
            }
            .navigationTitle("Sélectionner la position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    LocationStepView(project: GardenProject(name: "Test"))
        .environmentObject(GardenProjectService())
        .environmentObject(ThemeManager())
}
