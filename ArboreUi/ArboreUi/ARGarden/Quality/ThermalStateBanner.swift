//
//  ThermalStateBanner.swift
//  ArboreUi
//
//  Banner UI à attacher en `safeAreaInset(edge: .top)` ou `overlay` sur
//  une vue AR. Devient visible lorsque `ARQualityObserver` poste
//  `.arboreThermalCritical`, se masque sur `.arboreThermalRecovered`.
//
//  Le banner est dismissable manuellement — l'utilisateur qui sait ce
//  qu'il fait peut le cacher pour continuer sa session. Il réapparaît
//  uniquement à la prochaine transition vers un état critique.
//

import SwiftUI

struct ThermalStateBanner: View {
    @State private var isVisible: Bool = false
    @State private var dismissedThisCycle: Bool = false

    var body: some View {
        Group {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onReceive(NotificationCenter.default.publisher(for: .arboreThermalCritical)) { _ in
            // Une nouvelle alerte critique réactive l'affichage même si
            // l'utilisateur avait dismiss la précédente.
            dismissedThisCycle = false
            isVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .arboreThermalRecovered)) { _ in
            isVisible = false
            dismissedThisCycle = false
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "thermometer.high")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("THERMAL_BANNER_TITLE", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(NSLocalizedString("THERMAL_BANNER_SUBTITLE", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer(minLength: 8)

            Button(action: {
                dismissedThisCycle = true
                isVisible = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.85))
            }
            .accessibilityLabel(NSLocalizedString("THERMAL_BANNER_DISMISS", comment: ""))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.95))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            ThermalStateBanner()
            Spacer()
        }
        .onAppear {
            NotificationCenter.default.post(name: .arboreThermalCritical, object: nil)
        }
    }
}
