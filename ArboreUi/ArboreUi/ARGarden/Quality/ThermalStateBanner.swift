//
//  ThermalStateBanner.swift
//  ArboreUi
//
//  Compact status UI à attacher en `overlay` sur une vue AR. Devient visible
//  lorsque `ARQualityObserver` poste `.arboreThermalCritical`, se masque sur
//  `.arboreThermalRecovered`.
//
//  Le statut est volontairement bref : il confirme que l'app allège l'AR sans
//  interrompre le placement ni masquer la caméra.
//

import SwiftUI

struct ThermalStateBanner: View {
    @State private var isVisible: Bool = false
    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onReceive(NotificationCenter.default.publisher(for: .arboreThermalCritical)) { _ in
            showBriefly()
        }
        .onReceive(NotificationCenter.default.publisher(for: .arboreThermalRecovered)) { _ in
            autoHideTask?.cancel()
            isVisible = false
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 7) {
            Image(systemName: "thermometer.high")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.accentGold)

            Text(NSLocalizedString("THERMAL_BANNER_TITLE", comment: ""))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    Capsule(style: .continuous)
                        .fill(ArboreDesign.Colors.card.opacity(0.74))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(ArboreDesign.Colors.border.opacity(0.78), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
        .padding(.top, 8)
        .accessibilityLabel(NSLocalizedString("THERMAL_BANNER_SUBTITLE", comment: ""))
    }

    private func showBriefly() {
        autoHideTask?.cancel()
        isVisible = true
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isVisible = false
            }
        }
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
