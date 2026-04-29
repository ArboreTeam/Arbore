// ✅ PlantPhotoGallery.swift amélioré
import SwiftUI

struct PlantPhotoGallery: View {
    let images: [String]
    @Binding var isPresented: Bool
    @State private var currentIndex = 0
    @State private var showUI = true

    var body: some View {
        ZStack {
            // 🔆 Fond flouté + dégradé progressif
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
                .ignoresSafeArea()
                .background(Color.black.opacity(0.82).ignoresSafeArea())
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.88),
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.48),
                            Color.black.opacity(0.32)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 🔁 Galerie interactive swipeable sur toute la surface
            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { index in
                    ZoomableImageView(imageURL: images[index])
                        .tag(index)
                        .overlay(
                            Color.clear.contentShape(Rectangle())
                                .gesture(
                                    DragGesture()
                                        .onEnded { value in
                                            let dragThreshold: CGFloat = 50
                                            if value.translation.width < -dragThreshold && currentIndex < images.count - 1 {
                                                currentIndex += 1
                                            } else if value.translation.width > dragThreshold && currentIndex > 0 {
                                                currentIndex -= 1
                                            }
                                        }
                                )
                        )
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentIndex)

            // 🎛 UI overlay
            if showUI {
                VStack {
                    // ❌ Bouton de fermeture stylisé
                    HStack {
                        Spacer()
                        Button(action: {
                            isPresented = false
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.78))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .bold))
                            }
                        }
                        .padding()
                    }

                    Spacer()

                    // 🔘 Pagination dots + compteur
                    VStack(spacing: 8) {
                        Text("\(currentIndex + 1)/\(images.count)")
                            .foregroundColor(.white.opacity(0.9))
                            .font(.caption.weight(.semibold))

                        HStack(spacing: 6) {
                            ForEach(images.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                .transition(.opacity)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
        )
    }
}

// 📷 Image zoomable améliorée
struct ZoomableImageView: View {
    let imageURL: String
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height * 0.9)
                    .clipped()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = value.translation
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    offset = .zero
                                }
                            }
                    )
                    .gesture(
                        TapGesture(count: 2).onEnded {
                            withAnimation(.easeInOut) {
                                if scale > 1.1 {
                                    scale = 1.0
                                } else {
                                    scale = 2.5
                                }
                                lastScale = scale
                            }
                        }
                    )
            } placeholder: {
                Color.black.opacity(0.45)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .ignoresSafeArea()
    }
}

// 🎨 UIKit wrapper pour fond flouté
struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}
