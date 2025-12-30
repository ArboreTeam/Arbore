import SwiftUI

struct TutorialOverlay: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentPage = 0
    private let totalPages = 4
    
    private let gradientColors = [Color(hex: "#FED7AA"), Color(hex: "#FDBA74")]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Tutorial content
                TabView(selection: $currentPage) {
                    TutorialPage(
                        icon: "camera.viewfinder",
                        title: NSLocalizedString("TUTORIAL_PAGE1_TITLE", comment: ""),
                        description: NSLocalizedString("TUTORIAL_PAGE1_DESC", comment: ""),
                        gradientColors: gradientColors
                    )
                    .tag(0)
                    
                    TutorialPage(
                        icon: "arrow.left.and.right",
                        title: NSLocalizedString("TUTORIAL_PAGE2_TITLE", comment: ""),
                        description: NSLocalizedString("TUTORIAL_PAGE2_DESC", comment: ""),
                        gradientColors: gradientColors
                    )
                    .tag(1)
                    
                    TutorialPage(
                        icon: "arrow.up.and.down",
                        title: NSLocalizedString("TUTORIAL_PAGE3_TITLE", comment: ""),
                        description: NSLocalizedString("TUTORIAL_PAGE3_DESC", comment: ""),
                        gradientColors: gradientColors
                    )
                    .tag(2)
                    
                    TutorialPage(
                        icon: "hand.tap",
                        title: NSLocalizedString("TUTORIAL_PAGE4_TITLE", comment: ""),
                        description: NSLocalizedString("TUTORIAL_PAGE4_DESC", comment: ""),
                        gradientColors: gradientColors
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 400)
                
                Spacer()
                
                // Start button
                Button(action: { isPresented = false }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(currentPage == totalPages - 1 
                             ? NSLocalizedString("TUTORIAL_START_BUTTON", comment: "")
                             : NSLocalizedString("TUTORIAL_NEXT_BUTTON", comment: ""))
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

struct TutorialPage: View {
    let icon: String
    let title: String
    let description: String
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: gradientColors[1].opacity(0.5), radius: 30, x: 0, y: 15)
                
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct TutorialOverlay_Previews: PreviewProvider {
    static var previews: some View {
        TutorialOverlay(isPresented: .constant(true))
    }
}
