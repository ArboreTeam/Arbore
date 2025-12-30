import SwiftUI
import ARKit
import RealityKit

struct MeasurePotView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    let plantName: String?
    
    @StateObject private var arViewModel = ARMeasurementViewModel()
    @State private var showingManualInput = false
    @State private var showingResults = false
    @State private var showingTutorial = true
    @State private var selectedTab: MeasurementTab = .ar
    
    private let gradientColors = [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")]
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab selector
                    tabSelector
                    
                    if selectedTab == .ar {
                        arMeasurementView
                    } else {
                        manualInputView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(NSLocalizedString("MEASURE_POT_TITLE", comment: ""))
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingTutorial = true }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                MeasurementResultsView(
                    measurement: arViewModel.currentMeasurement,
                    plantName: plantName
                )
                .environmentObject(themeManager)
            }
            .overlay(tutorialOverlay)
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(
                title: NSLocalizedString("MEASURE_TAB_AR", comment: ""),
                icon: "camera.viewfinder",
                isSelected: selectedTab == .ar,
                action: { selectedTab = .ar }
            )
            
            TabButton(
                title: NSLocalizedString("MEASURE_TAB_MANUAL", comment: ""),
                icon: "hand.tap",
                isSelected: selectedTab == .manual,
                action: { selectedTab = .manual }
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(hex: "#1C1C1E") : Color.white)
    }
    
    // MARK: - AR Measurement View
    
    private var arMeasurementView: some View {
        ZStack {
            // AR View
            ARMeasurementViewContainer(viewModel: arViewModel)
                .ignoresSafeArea()
            
            // Overlays
            VStack {
                // Instructions at top
                instructionsCard
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // Measurement display
                if arViewModel.isPlacingPoints {
                    currentMeasurementDisplay
                        .padding(.horizontal, 20)
                }
                
                // Controls at bottom
                arControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
            }
            
            // Crosshair center
            if arViewModel.isPlacingPoints {
                crosshair
            }
        }
    }
    
    private var instructionsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: arViewModel.currentInstruction.icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#FDBA74"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(arViewModel.currentInstruction.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(arViewModel.currentInstruction.description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 5)
        )
    }
    
    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#FDBA74"), lineWidth: 2)
                .frame(width: 20, height: 20)
            
            Circle()
                .fill(Color(hex: "#FDBA74"))
                .frame(width: 6, height: 6)
        }
    }
    
    private var currentMeasurementDisplay: some View {
        VStack(spacing: 12) {
            if let diameter = arViewModel.diameter {
                MeasurementBadge(
                    icon: "arrow.left.and.right",
                    label: NSLocalizedString("MEASURE_DIAMETER", comment: ""),
                    value: String(format: "%.1f cm", diameter * 100)
                )
            }
            
            if let height = arViewModel.height {
                MeasurementBadge(
                    icon: "arrow.up.and.down",
                    label: NSLocalizedString("MEASURE_HEIGHT", comment: ""),
                    value: String(format: "%.1f cm", height * 100)
                )
            }
        }
    }
    
    private var arControls: some View {
        HStack(spacing: 16) {
            if arViewModel.canReset {
                Button(action: { arViewModel.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
            }
            
            Button(action: {
                if arViewModel.isComplete {
                    showingResults = true
                } else {
                    arViewModel.placePoint()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: arViewModel.isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(arViewModel.isComplete 
                         ? NSLocalizedString("MEASURE_VIEW_RESULTS", comment: "")
                         : NSLocalizedString("MEASURE_PLACE_POINT", comment: ""))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: arViewModel.isComplete ? [Color.green, Color.green.opacity(0.8)] : gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(28)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .disabled(!arViewModel.canPlacePoint)
        }
    }
    
    // MARK: - Manual Input View
    
    private var manualInputView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                manualInputHeader
                
                dimensionsInput
                
                shapeSelector
                
                materialSelector
                
                drainageToggle
                
                notesInput
                
                calculateButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
    
    private var manualInputHeader: some View {
        VStack(spacing: 12) {
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
                    .shadow(color: Color(hex: "#FDBA74").opacity(0.3), radius: 15, x: 0, y: 8)
                
                Image(systemName: "ruler")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            
            Text(NSLocalizedString("MEASURE_MANUAL_TITLE", comment: ""))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(NSLocalizedString("MEASURE_MANUAL_SUBTITLE", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var dimensionsInput: some View {
        VStack(spacing: 16) {
            DimensionInputField(
                icon: "arrow.left.and.right",
                label: NSLocalizedString("MEASURE_DIAMETER", comment: ""),
                value: $arViewModel.manualDiameter,
                unit: "cm"
            )
            
            DimensionInputField(
                icon: "arrow.up.and.down",
                label: NSLocalizedString("MEASURE_HEIGHT", comment: ""),
                value: $arViewModel.manualHeight,
                unit: "cm"
            )
        }
    }
    
    private var shapeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                NSLocalizedString("MEASURE_POT_SHAPE", comment: ""),
                systemImage: "square.on.circle"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PotShape.allCases, id: \.self) { shape in
                    ShapeButton(
                        shape: shape,
                        isSelected: arViewModel.selectedShape == shape,
                        action: { arViewModel.selectedShape = shape }
                    )
                }
            }
        }
    }
    
    private var materialSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                NSLocalizedString("MEASURE_POT_MATERIAL", comment: ""),
                systemImage: "cube.transparent"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            VStack(spacing: 8) {
                ForEach(PotMaterial.allCases, id: \.self) { material in
                    MaterialButton(
                        material: material,
                        isSelected: arViewModel.selectedMaterial == material,
                        action: { arViewModel.selectedMaterial = material }
                    )
                }
            }
        }
    }
    
    private var drainageToggle: some View {
        HStack {
            Label(
                NSLocalizedString("MEASURE_DRAINAGE_HOLES", comment: ""),
                systemImage: "drop.triangle"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Toggle("", isOn: $arViewModel.hasDrainage)
                .labelsHidden()
                .tint(Color(hex: "#FDBA74"))
        }
        .padding()
        .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
        .cornerRadius(12)
    }
    
    private var notesInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                NSLocalizedString("MEASURE_NOTES", comment: ""),
                systemImage: "text.alignleft"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            TextEditor(text: $arViewModel.notes)
                .frame(height: 80)
                .padding(8)
                .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#FDBA74").opacity(0.3), lineWidth: 1)
                )
        }
    }
    
    private var calculateButton: some View {
        Button(action: {
            arViewModel.calculateManualMeasurement(plantName: plantName)
            showingResults = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "function")
                Text(NSLocalizedString("MEASURE_CALCULATE", comment: ""))
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: arViewModel.canCalculate ? gradientColors : [Color.gray, Color.gray.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .disabled(!arViewModel.canCalculate)
        .padding(.top, 12)
    }
    
    // MARK: - Tutorial Overlay
    
    private var tutorialOverlay: some View {
        Group {
            if showingTutorial {
                TutorialOverlay(isPresented: $showingTutorial)
            }
        }
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                ? LinearGradient(
                    colors: [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                : LinearGradient(
                    colors: [Color.clear, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
    }
}

struct MeasurementBadge: View {
    let icon: String
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#FDBA74"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

struct DimensionInputField: View {
    let icon: String
    let label: String
    @Binding var value: String
    let unit: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#FDBA74"))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("0.0", text: $value)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#FDBA74").opacity(0.3), lineWidth: 1)
        )
    }
}

struct ShapeButton: View {
    let shape: PotShape
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: shape.icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? .white : Color(hex: "#FDBA74"))
                
                Text(shape.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                ? LinearGradient(
                    colors: [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white,
                        colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.clear : Color(hex: "#FDBA74").opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }
}

struct MaterialButton: View {
    let material: PotMaterial
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: material.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : Color(hex: "#FDBA74"))
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(material.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                    
                    Text(material.characteristics)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                isSelected
                ? LinearGradient(
                    colors: [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                : LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white,
                        colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.clear : Color(hex: "#FDBA74").opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }
}

enum MeasurementTab {
    case ar, manual
}

// MARK: - Preview

struct MeasurePotView_Previews: PreviewProvider {
    static var previews: some View {
        MeasurePotView(plantName: "Monstera")
            .environmentObject(ThemeManager())
    }
}
