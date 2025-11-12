import SwiftUI
import UIKit

struct AccessibilityView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var voiceOverEnabled: Bool = UIAccessibility.isVoiceOverRunning
    @State private var boldText: Bool = false
    @State private var increaseContrast: Bool = false
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @State private var textSizeMultiplier: Double = 1.0
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack {
                List {
                    Section(header: Text("VoiceOver")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("VoiceOver")
                                    .foregroundColor(themeManager.textColor)
                                Text("Screen reader for blind and low vision users")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            Spacer()
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.blue)
                                Text("Settings")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            .onTapGesture {
                                openSettings()
                            }
                        }
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Display")) {
                        Toggle("Bold Text", isOn: $boldText)
                        Toggle("Increase Contrast", isOn: $increaseContrast)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Motion")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reduce Motion")
                                    .foregroundColor(themeManager.textColor)
                                Text("Minimize animations and transitions")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            Spacer()
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.blue)
                                Text("Settings")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            .onTapGesture {
                                openSettings()
                            }
                        }
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Text Size")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("A")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                                Slider(value: $textSizeMultiplier, in: 0.8...1.5, step: 0.1)
                                Text("A")
                                    .font(.title2)
                                    .foregroundColor(themeManager.secondaryTextColor)
                            }
                            
                            HStack {
                                Text("Size: \(Int(textSizeMultiplier * 100))%")
                                    .font(.caption)
                                    .foregroundColor(themeManager.secondaryTextColor)
                                Spacer()
                                Text("Sample Text")
                                    .font(.system(size: 14 * textSizeMultiplier))
                                    .foregroundColor(themeManager.textColor)
                            }
                        }
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}