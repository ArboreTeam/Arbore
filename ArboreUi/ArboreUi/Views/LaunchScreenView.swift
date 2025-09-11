import SwiftUI

struct LaunchScreenView: View {
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color(hex: "#2D3E30") // fond vert foncé
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("arbore_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible ? 1 : 0.8)
                    .animation(.easeOut(duration: 0.6), value: isVisible)

                Text("Arbore glow with harmony")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundColor(.white)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.8).delay(0.2), value: isVisible)
            }
        }
        .onAppear {
            isVisible = true
        }
    }
}
