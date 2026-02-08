//
//  ManageGardenView.swift
//  ArboreUi
//
//  Created on November 25, 2025.
//

import SwiftUI

// MARK: - Models

struct PurchaseItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let priceRange: String
    let imageName: String?        // asset name (optional)
    let systemIcon: String?       // fallback icon (optional)
    let priority: Int             // for sorting (1 = high)
}

// MARK: - View

struct ManageGardenView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var projectService = GardenProjectService()

    @State private var selectedTab: Tab = .purchase
    @State private var selectedGardenName: String = "My Garden"
    @State private var showGardenPicker = false
    @State private var showAdvancedManage = false
    @State private var showDeleteAlert = false
    @State private var sortByPriority = true

    private let primary = Color(red: 0.05, green: 0.95, blue: 0.27) // #0df246

    enum Tab: String, CaseIterable {
        case plan2D = "2D Planning"
        case tasks = "Tasks"
        case purchase = "Purchase"
    }

    // Mock data (à remplacer par tes vraies plantes + magasins)
    @State private var items: [PurchaseItem] = [
        .init(name: "Monstera Deliciosa", subtitle: "Garden Center • In Stock", priceRange: "$25 - $40", imageName: "monstera", systemIcon: nil, priority: 1),
        .init(name: "Snake Plant", subtitle: "Home Depot, Lowes", priceRange: "$15 - $30", imageName: "snakeplant", systemIcon: nil, priority: 2),
        .init(name: "Fiddle Leaf Fig", subtitle: "Local Nursery", priceRange: "$40 - $80", imageName: "fiddleleaf", systemIcon: nil, priority: 3),
        .init(name: "Golden Pothos", subtitle: "IKEA, Local Shop", priceRange: "$10 - $20", imageName: "pothos", systemIcon: nil, priority: 4),
        .init(name: "Organic Potting Mix", subtitle: "Any Garden Center", priceRange: "$8 - $12", imageName: nil, systemIcon: "leaf.fill", priority: 2)
    ]

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topAppBar
                    tabsBar

                    ScrollView {
                        VStack(spacing: 12) {
                            sectionHeader

                            switch selectedTab {
                            case .purchase:
                                purchaseList
                            case .plan2D:
                                placeholder(title: "2D Planning", subtitle: "Plan du jardin + détail plante en dessous")
                            case .tasks:
                                placeholder(title: "Tasks", subtitle: "Calendrier + tâches à cocher")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 96) // space for FAB
                    }
                }

                fab
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .navigationBarHidden(true)
            .alert("Delete garden?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    // TODO: suppression jardin
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showGardenPicker) {
                GardenPickerSheet(
                    selectedGardenName: $selectedGardenName,
                    onDeleteTap: { showDeleteAlert = true }
                )
                .presentationDetents([.medium])
            }
            .navigationDestination(isPresented: $showAdvancedManage) {
                Text("Advanced Garden Management")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(themeManager.backgroundColor)
            }
        }
    }

    // MARK: - Top App Bar

    private var topAppBar: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 44)

            HStack {
                Button {
                    showGardenPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedGardenName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(themeManager.textColor)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(themeManager.textColor)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        showAdvancedManage = true
                    } label: {
                        Text("Edit")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete garden")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            Divider()
                .opacity(0.3)
        }
        .background(TopBarBackground(isDark: isDark))
    }

    // MARK: - Tabs

    private var tabsBar: some View {
        HStack(spacing: 0) {
            tabButton(.plan2D)
            tabButton(.tasks)
            tabButton(.purchase)
        }
        .padding(.horizontal, 16)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 10) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: tab == selectedTab ? .bold : .semibold))
                    .foregroundStyle(tab == selectedTab ? themeManager.textColor : .secondary)

                Rectangle()
                    .fill(tab == selectedTab ? primary : .clear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack {
            Text("TO BUY (\(items.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.1)

            Spacer()

            Button {
                sortByPriority.toggle()
            } label: {
                Text("Sort by Priority")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Purchase list

    private var purchaseList: some View {
        VStack(spacing: 12) {
            ForEach(sortedItems) { item in
                PurchaseRow(item: item, primary: primary, isDark: isDark) {
                    // TODO: action Buy (ouvrir lien, store sheet, etc.)
                }
            }
        }
    }

    private var sortedItems: [PurchaseItem] {
        if sortByPriority {
            return items.sorted { $0.priority < $1.priority }
        } else {
            return items
        }
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            // TODO: add item
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isDark ? Color.black : Color.white)
                .frame(width: 56, height: 56)
                .background(isDark ? Color.white : Color.black)
                .clipShape(Circle())
                .shadow(radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }

    // MARK: - Placeholder

    private func placeholder(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(CardContainer(isDark: isDark, cornerRadius: 16))
    }
}

// MARK: - Row

private struct PurchaseRow: View {
    let item: PurchaseItem
    let primary: Color
    let isDark: Bool
    let onBuy: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.priceRange)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primary)
            }

            Spacer(minLength: 8)

            Button(action: onBuy) {
                Text("Buy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.06, green: 0.13, blue: 0.08))
                    .frame(minWidth: 80, minHeight: 36)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: primary.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(CardContainer(isDark: isDark, cornerRadius: 18))
        .shadow(color: isDark ? Color.black.opacity(0.22) : Color.black.opacity(0.06),
                radius: 8, x: 0, y: 4)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                .frame(width: 64, height: 64)

            // IMPORTANT: éviter le UIImage(named:) dans une grosse expression -> on garde simple
            if let imageName = item.imageName, !imageName.isEmpty {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let icon = item.systemIcon {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(primary.opacity(0.6))
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(primary.opacity(0.6))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Small reusable building blocks (fixes compiler timeouts)

private struct CardContainer: View {
    let isDark: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let fillColor = isDark ? Color.white.opacity(0.06) : Color.white
        let strokeColor = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

private struct TopBarBackground: View {
    let isDark: Bool

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(isDark ? 0.15 : 0.25)
    }
}

// MARK: - Garden picker sheet (simple)

private struct GardenPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGardenName: String
    let onDeleteTap: () -> Void

    private let gardens = ["My Garden", "Backyard Oasis", "Balcony Herbs"]

    var body: some View {
        NavigationStack {
            List {
                Section("Choose active garden") {
                    ForEach(gardens, id: \.self) { g in
                        HStack {
                            Text(g)
                            Spacer()
                            if g == selectedGardenName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedGardenName = g
                            dismiss()
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        onDeleteTap()
                    } label: {
                        Label("Delete garden", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Gardens")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ManageGardenView()
        .environmentObject(ThemeManager())
}
