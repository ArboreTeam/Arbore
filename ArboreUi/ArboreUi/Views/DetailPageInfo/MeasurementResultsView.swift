import SwiftUI

struct MeasurementResultsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    let measurement: PotMeasurement?
    let plantName: String?
    
    @State private var showingSaveConfirmation = false
    @State private var selectedShareOption: ShareOption?
    
    private let gradientColors = [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")]
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        successHeader
                        
                        if let measurement = measurement {
                            dimensionsCard(measurement: measurement)
                            
                            volumeCard(measurement: measurement)
                            
                            if let material = measurement.material {
                                materialCard(material: material)
                            }
                            
                            recommendationsCard(measurement: measurement)
                            
                            if !measurement.notes.isEmpty {
                                notesCard(measurement: measurement)
                            }
                            
                            actionButtons
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(NSLocalizedString("MEASURE_RESULTS_TITLE", comment: ""))
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { selectedShareOption = .image }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
            .alert(item: $selectedShareOption) { option in
                Alert(
                    title: Text(NSLocalizedString("MEASURE_SHARE_TITLE", comment: "")),
                    message: Text(NSLocalizedString("MEASURE_SHARE_MESSAGE", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("COMMON_OK", comment: "")))
                )
            }
            .overlay(saveConfirmationOverlay)
        }
    }
    
    // MARK: - Success Header
    
    private var successHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(hex: "#FDBA74").opacity(0.3), radius: 20, x: 0, y: 10)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("MEASURE_RESULTS_SUCCESS_TITLE", comment: ""))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if let plantName = plantName {
                    Text(String(format: NSLocalizedString("MEASURE_RESULTS_FOR_PLANT", comment: ""), plantName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Dimensions Card
    
    private func dimensionsCard(measurement: PotMeasurement) -> some View {
        ResultCard(
            icon: "ruler",
            iconColor: Color(hex: "#FDBA74"),
            title: NSLocalizedString("MEASURE_RESULTS_DIMENSIONS", comment: "")
        ) {
            VStack(spacing: 16) {
                HStack {
                    ResultMetric(
                        icon: "arrow.left.and.right",
                        label: NSLocalizedString("MEASURE_DIAMETER", comment: ""),
                        value: String(format: "%.1f cm", measurement.diameter),
                        color: Color(hex: "#FDBA74")
                    )
                    
                    Spacer()
                    
                    ResultMetric(
                        icon: "arrow.up.and.down",
                        label: NSLocalizedString("MEASURE_HEIGHT", comment: ""),
                        value: String(format: "%.1f cm", measurement.height),
                        color: Color(hex: "#FED7AA")
                    )
                }
                
                Divider()
                
                HStack {
                    Image(systemName: measurement.shape.icon)
                        .foregroundColor(Color(hex: "#FDBA74"))
                    Text(measurement.shape.displayName)
                        .font(.system(size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Volume Card
    
    private func volumeCard(measurement: PotMeasurement) -> some View {
        ResultCard(
            icon: "cube.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: NSLocalizedString("MEASURE_RESULTS_VOLUME", comment: "")
        ) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("MEASURE_RESULTS_CAPACITY", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(measurement.volumeInLiters)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: 50))
                        .foregroundColor(Color(hex: "#38BDF8").opacity(0.3))
                }
                
                if measurement.drainageHoles {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("MEASURE_RESULTS_HAS_DRAINAGE", comment: ""))
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Material Card
    
    private func materialCard(material: PotMaterial) -> some View {
        ResultCard(
            icon: material.icon,
            iconColor: Color(hex: "#4ADE80"),
            title: NSLocalizedString("MEASURE_POT_MATERIAL", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(material.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(material.characteristics)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Recommendations Card
    
    private func recommendationsCard(measurement: PotMeasurement) -> some View {
        let recommendation = PotRecommendation(
            currentVolume: measurement.volume,
            plantType: plantName
        )
        
        return ResultCard(
            icon: recommendation.needsRepotting ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
            iconColor: recommendation.needsRepotting ? Color(hex: "#EAB308") : Color(hex: "#22C55E"),
            title: NSLocalizedString("MEASURE_RESULTS_RECOMMENDATIONS", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(recommendation.message)
                    .font(.system(size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                
                if recommendation.needsRepotting {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("MEASURE_RESULTS_RECOMMENDED_SIZE", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            RecommendationMetric(
                                label: NSLocalizedString("MEASURE_DIAMETER", comment: ""),
                                value: String(format: "%.1f cm", recommendation.recommendedDiameter)
                            )
                            
                            RecommendationMetric(
                                label: NSLocalizedString("MEASURE_RESULTS_VOLUME", comment: ""),
                                value: String(format: "%.1f L", recommendation.recommendedVolume)
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Notes Card
    
    private func notesCard(measurement: PotMeasurement) -> some View {
        ResultCard(
            icon: "text.alignleft",
            iconColor: Color(hex: "#A78BFA"),
            title: NSLocalizedString("MEASURE_NOTES", comment: "")
        ) {
            Text(measurement.notes)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: saveMeasurement) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text(NSLocalizedString("MEASURE_SAVE_BUTTON", comment: ""))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            
            Button(action: { dismiss() }) {
                Text(NSLocalizedString("MEASURE_DONE_BUTTON", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Save Confirmation Overlay
    
    private var saveConfirmationOverlay: some View {
        Group {
            if showingSaveConfirmation {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text(NSLocalizedString("MEASURE_SAVED_TITLE", comment: ""))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(NSLocalizedString("MEASURE_SAVED_MESSAGE", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .padding(40)
                    .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                    .cornerRadius(24)
                    .shadow(radius: 30)
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func saveMeasurement() {
        // Save measurement to UserDefaults or database
        if let measurement = measurement {
            print("✅ Measurement saved:", measurement)
            
            // TODO: Implement actual save logic
            // - Save to UserDefaults
            // - Save to Core Data
            // - Upload to Firebase
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showingSaveConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingSaveConfirmation = false
            }
            dismiss()
        }
    }
}

// MARK: - Supporting Views

struct ResultCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 5)
        )
    }
}

struct ResultMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct RecommendationMetric: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

enum ShareOption: Identifiable {
    case image, text
    
    var id: String {
        switch self {
        case .image: return "image"
        case .text: return "text"
        }
    }
}

// MARK: - Preview

struct MeasurementResultsView_Previews: PreviewProvider {
    static var previews: some View {
        MeasurementResultsView(
            measurement: PotMeasurement(
                plantName: "Monstera",
                diameter: 20,
                height: 25,
                shape: .round,
                material: .terracotta,
                drainageHoles: true,
                notes: "Pot actuel"
            ),
            plantName: "Monstera"
        )
        .environmentObject(ThemeManager())
    }
}
