import SwiftUI

struct TermsConditionsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms & Conditions")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(themeManager.textColor)
                    
                    Text("By using our application, you agree to these terms and conditions.")
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Use License")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        Text("Permission is granted to temporarily download one copy of the materials for personal, non-commercial transitory viewing only.")
                            .foregroundColor(themeManager.secondaryTextColor)
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. Disclaimer")
                            .font(.headline)
                            .foregroundColor(themeManager.textColor)
                        Text("The materials on our application are provided on an 'as is' basis.")
                            .foregroundColor(themeManager.secondaryTextColor)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("Terms & Conditions")
        .navigationBarTitleDisplayMode(.inline)
    }
}