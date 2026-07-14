import SwiftUI
import Vision
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - VUE SANTÉ PRINCIPALE

struct SanteDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    let health: HealthInfo?
    var plantName: String?
    @State private var showScanner = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerHero

                    if let health = health {
                        if hasProblemInfo(health: health) { problemsSection(health: health) }
                        if hasPestInfo(health: health) { pestsSection(health: health) }
                        if hasPreventionInfo(health: health) { preventionSection(health: health) }
                        outilsUtilesSection
                        scanSanteCTA
                    } else {
                        HealthSectionCard(
                            icon: "cross.case.fill", iconColor: Color(hex: "#F97316"),
                            title: NSLocalizedString("HEALTHDETAIL_INFO_UNAVAILABLE_TITLE", comment: "")
                        ) {
                            Text(NSLocalizedString("HEALTHDETAIL_INFO_UNAVAILABLE_BODY", comment: ""))
                                .font(.system(size: 14)).foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        outilsUtilesSection
                        scanSanteCTA
                    }
                }
                .padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            PlantHealthScannerView(plantName: plantName)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("HEALTHDETAIL_NAV_TITLE", comment: ""))
    }

    // --- Helpers ---
    private var primaryTextColor: Color { colorScheme == .dark ? .white : .black }
    private var secondaryTextColor: Color { colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7) }
    private var headerSubtitle: String {
        if let first = health?.commonProblems?.first, !first.isEmpty { return first }
        if let first = health?.pests?.first, !first.isEmpty { return first }
        return NSLocalizedString("HEALTHDETAIL_HEADER_DEFAULT_SUBTITLE", comment: "")
    }

    // HEADER
    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#7F1D1D"), Color(hex: "#450A0A")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)).frame(width: 64, height: 64)
                        Image(systemName: "cross.case.fill").font(.system(size: 30)).foregroundColor(Color(hex: "#F97316"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("HEALTHDETAIL_HEADER_TITLE", comment: "")).font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                        Text(headerSubtitle).font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    }
                    Spacer()
                }
                if let health = health, hasProblemInfo(health: health) || hasPestInfo(health: health) {
                    Divider().background(Color.white.opacity(0.15))
                    HStack(spacing: 10) {
                        if let count = health.commonProblems?.count, count > 0 {
                            let txt = String(format: NSLocalizedString("HEALTHDETAIL_HEADER_PROBLEMS_COUNT_FORMAT", comment: ""), count)
                            HealthHeaderPill(icon: "exclamationmark.triangle.fill", text: txt)
                        }
                        if let count = health.pests?.count, count > 0 {
                            let txt = String(format: NSLocalizedString("HEALTHDETAIL_HEADER_PESTS_COUNT_FORMAT", comment: ""), count)
                            HealthHeaderPill(icon: "ant.fill", text: txt)
                        }
                    }
                } else {
                    Text(NSLocalizedString("HEALTHDETAIL_HEADER_FALLBACK_TEXT", comment: "")).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // SECTIONS
    private func hasProblemInfo(health: HealthInfo) -> Bool { (health.commonProblems?.count ?? 0) > 0 || (health.symptomsAndCauses?.count ?? 0) > 0 }
    private func problemsSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "exclamationmark.triangle.fill", iconColor: Color(hex: "#F97316"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                if let problems = health.commonProblems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_COMMON_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(problems, id: \.self) { HealthBulletRow(text: $0) }
                    }
                }
                if let symptoms = health.symptomsAndCauses {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PROBLEMS_SYMPTOMS_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(symptoms, id: \.self) { HealthBulletRow(text: $0) }
                    }.padding(.top, 6)
                }
            }
        }
    }

    private func hasPestInfo(health: HealthInfo) -> Bool { (health.pests?.count ?? 0) > 0 || (health.treatments?.count ?? 0) > 0 }
    private func pestsSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "ant.fill", iconColor: Color(hex: "#22C55E"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                if let pests = health.pests {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_COMMON_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        WrapTagCloud(items: pests)
                    }
                }
                if let treatments = health.treatments {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("HEALTHDETAIL_SECTION_PESTS_TREATMENTS_TITLE", comment: "")).font(.system(size: 15, weight: .semibold)).foregroundColor(primaryTextColor)
                        ForEach(treatments, id: \.self) { HealthBulletRow(text: $0) }
                    }.padding(.top, 8)
                }
            }
        }
    }

    private func hasPreventionInfo(health: HealthInfo) -> Bool { (health.prevention?.count ?? 0) > 0 }
    private func preventionSection(health: HealthInfo) -> some View {
        HealthSectionCard(icon: "shield.lefthalf.filled", iconColor: Color(hex: "#22C55E"), title: NSLocalizedString("HEALTHDETAIL_SECTION_PREVENTION_TITLE", comment: "")) {
            if let prevention = health.prevention { ForEach(prevention, id: \.self) { HealthBulletRow(text: $0) } }
        }
    }

    private var outilsUtilesSection: some View {
        HealthSectionCard(icon: "wrench.and.screwdriver.fill", iconColor: Color(hex: "#38BDF8"), title: NSLocalizedString("HEALTHDETAIL_TOOLS_TITLE", comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                HealthToolRow(systemIcon: "magnifyingglass", title: NSLocalizedString("HEALTHDETAIL_TOOLS_MAGNIFIER_TITLE", comment: ""), subtitle: NSLocalizedString("HEALTHDETAIL_TOOLS_MAGNIFIER_SUBTITLE", comment: ""))
                HealthToolRow(systemIcon: "camera.viewfinder", title: NSLocalizedString("HEALTHDETAIL_TOOLS_PHOTOS_TITLE", comment: ""), subtitle: NSLocalizedString("HEALTHDETAIL_TOOLS_PHOTOS_SUBTITLE", comment: ""))
            }
        }
    }

    private var scanSanteCTA: some View {
        Button(action: { showScanner = true }) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                Text(NSLocalizedString("HEALTHDETAIL_CTA_SCAN_TITLE", comment: ""))
            }
            .font(.system(size: 16, weight: .semibold)).foregroundColor(.black).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(hex: "#BBF7D0"), Color(hex: "#4ADE80")], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(22).shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }.padding(.horizontal, 20)
    }
}

// MARK: - Subviews
private struct HealthSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let iconColor: Color; let title: String; let content: Content
    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) { self.icon = icon; self.iconColor = iconColor; self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack { Circle().fill(iconColor.opacity(0.18)).frame(width: 40, height: 40); Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(iconColor) }
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black); Spacer()
            }
            content
        }.padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.96)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1)))
    }
}
private struct HealthBulletRow: View {
    @Environment(\.colorScheme) private var cs; let text: String
    var body: some View { HStack(alignment: .top, spacing: 8) { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(Color(hex: "#F97316")).padding(.top, 5); Text(text).font(.system(size: 13)).foregroundColor(cs == .dark ? .white.opacity(0.8) : .black.opacity(0.8)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) } }
}
private struct HealthToolRow: View {
    @Environment(\.colorScheme) private var cs; let systemIcon: String; let title: String; let subtitle: String
    var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: systemIcon).font(.system(size: 18)).foregroundColor(Color(hex: "#38BDF8")).frame(width: 24); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(cs == .dark ? .white : .black); Text(subtitle).font(.system(size: 13)).foregroundColor(cs == .dark ? .white.opacity(0.7) : .black.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }; Spacer(minLength: 0) } }
}
private struct HealthHeaderPill: View { let icon: String; let text: String; var body: some View { HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 13, weight: .semibold)); Text(text).font(.system(size: 13, weight: .medium)) }.foregroundColor(.white).padding(.vertical, 5).padding(.horizontal, 10).background(Color.white.opacity(0.12)).clipShape(Capsule()) } }
private struct WrapTagCloud: View {
    @Environment(\.colorScheme) private var cs; let items: [String]
    var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) { ForEach(items, id: \.self) { item in Text(item).font(.system(size: 12, weight: .medium)).foregroundColor(cs == .dark ? .white.opacity(0.8) : .black.opacity(0.8)).padding(.vertical, 5).padding(.horizontal, 10).background(Capsule().fill(Color.white.opacity(0.04))) } } }
}
