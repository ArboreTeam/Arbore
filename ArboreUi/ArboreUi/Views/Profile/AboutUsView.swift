import SwiftUI

struct AboutUsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("Arbore")
                        .font(.title2)
                        .bold()
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Arbore")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Arbore is a gardening companion application designed to help you grow and manage your plants with ease.")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                        .lineLimit(nil)
                }
                .padding()
                .background(themeManager.cardBackgroundColor)
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("About Us")
        .navigationBarTitleDisplayMode(.inline)
    }
}