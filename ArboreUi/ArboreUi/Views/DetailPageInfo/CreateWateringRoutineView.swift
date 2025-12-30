import SwiftUI

struct CreateWateringRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    // Props from parent
    let plantName: String
    let waterInfo: WaterInfo?
    
    // Form state
    @State private var selectedFrequency: WateringFrequency = .weekly
    @State private var customDays: Int = 7
    @State private var reminderTime = Date()
    @State private var amount: String = ""
    @State private var notes: String = ""
    @State private var showingSuccessAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        frequencySection
                        if selectedFrequency == .custom {
                            customDaysSection
                        }
                        timeSection
                        amountSection
                        notesSection
                        createButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle(NSLocalizedString("ROUTINE_CREATE_TITLE", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(primaryTextColor)
                    }
                }
            }
            .alert(NSLocalizedString("ROUTINE_SUCCESS_TITLE", comment: ""), isPresented: $showingSuccessAlert) {
                Button(NSLocalizedString("ROUTINE_SUCCESS_OK", comment: ""), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("ROUTINE_SUCCESS_MESSAGE", comment: ""))
            }
        }
        .onAppear {
            prefillFromWaterInfo()
        }
    }
    
    // MARK: - Colors
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#38BDF8"), Color(hex: "#0EA5E9")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color(hex: "#38BDF8").opacity(0.4), radius: 12, x: 0, y: 6)
                
                Image(systemName: "drop.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(plantName)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(primaryTextColor)
                .multilineTextAlignment(.center)
            
            Text(NSLocalizedString("ROUTINE_CREATE_SUBTITLE", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Frequency Section
    
    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "calendar",
                title: NSLocalizedString("ROUTINE_FREQUENCY_LABEL", comment: "")
            )
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WateringFrequency.allCases, id: \.self) { freq in
                    FrequencyCard(
                        frequency: freq,
                        isSelected: selectedFrequency == freq
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFrequency = freq
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Custom Days
    
    private var customDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "calendar.badge.plus",
                title: NSLocalizedString("ROUTINE_CUSTOM_DAYS_LABEL", comment: "")
            )
            
            HStack {
                Button(action: {
                    if customDays > 1 {
                        customDays -= 1
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "#38BDF8"))
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("\(customDays)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(primaryTextColor)
                    
                    Text(NSLocalizedString("ROUTINE_DAYS_UNIT", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
                
                Button(action: {
                    if customDays < 365 {
                        customDays += 1
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "#38BDF8"))
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(cardBackgroundColor)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Time Section
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "clock",
                title: NSLocalizedString("ROUTINE_TIME_LABEL", comment: "")
            )
            
            DatePicker(
                "",
                selection: $reminderTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(cardBackgroundColor)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "drop.triangle",
                title: NSLocalizedString("ROUTINE_AMOUNT_LABEL", comment: "")
            )
            
            TextField(
                NSLocalizedString("ROUTINE_AMOUNT_PLACEHOLDER", comment: ""),
                text: $amount
            )
            .padding(16)
            .background(cardBackgroundColor)
            .cornerRadius(12)
            .foregroundColor(primaryTextColor)
            .font(.system(size: 16))
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "note.text",
                title: NSLocalizedString("ROUTINE_NOTES_LABEL", comment: "")
            )
            
            TextEditor(text: $notes)
                .frame(height: 100)
                .padding(12)
                .background(cardBackgroundColor)
                .cornerRadius(12)
                .foregroundColor(primaryTextColor)
                .font(.system(size: 15))
                .overlay(
                    Group {
                        if notes.isEmpty {
                            Text(NSLocalizedString("ROUTINE_NOTES_PLACEHOLDER", comment: ""))
                                .foregroundColor(secondaryTextColor.opacity(0.5))
                                .font(.system(size: 15))
                                .padding(.top, 20)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
    
    // MARK: - Create Button
    
    private var createButton: some View {
        Button(action: createRoutine) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                Text(NSLocalizedString("ROUTINE_CREATE_BUTTON", comment: ""))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#38BDF8"), Color(hex: "#0EA5E9")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color(hex: "#38BDF8").opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
    private func prefillFromWaterInfo() {
        guard let waterInfo = waterInfo else { return }
        
        // Prefill frequency based on water info
        if let frequency = waterInfo.frequency?.lowercased() {
            if frequency.contains("jour") || frequency.contains("day") || frequency.contains("daily") {
                selectedFrequency = .daily
            } else if frequency.contains("semaine") || frequency.contains("week") {
                if frequency.contains("2") || frequency.contains("deux") || frequency.contains("twice") {
                    selectedFrequency = .twiceWeekly
                } else {
                    selectedFrequency = .weekly
                }
            } else if frequency.contains("mois") || frequency.contains("month") {
                selectedFrequency = .monthly
            }
        }
        
        // Prefill amount
        if let waterAmount = waterInfo.amount, !waterAmount.isEmpty {
            amount = waterAmount
        }
    }
    
    private func createRoutine() {
        let finalDays = selectedFrequency == .custom ? customDays : selectedFrequency.days
        
        // TODO: Save routine to UserDefaults or Firebase
        // For now, just show success
        
        showingSuccessAlert = true
    }
}

// MARK: - Subviews

private struct SectionHeaderLabel: View {
    let icon: String
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    
    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#38BDF8"))
            
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(titleColor)
        }
    }
}

private struct FrequencyCard: View {
    let frequency: WateringFrequency
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackgroundColor: Color {
        if isSelected {
            return Color(hex: "#38BDF8")
        }
        return colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        }
        return colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color(hex: "#38BDF8").opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: frequency.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? .white : Color(hex: "#38BDF8"))
                }
                
                Text(frequency.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(cardBackgroundColor)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color(hex: "#38BDF8") : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? Color(hex: "#38BDF8").opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct CreateWateringRoutineView_Previews: PreviewProvider {
    static var previews: some View {
        CreateWateringRoutineView(
            plantName: "Monstera Deliciosa",
            waterInfo: WaterInfo(
                frequency: "1 fois par semaine",
                amount: "200-300ml",
                method: "Arrosage modéré",
                humidity: "60-70%",
                signsLack: "Feuilles tombantes",
                signsExcess: "Feuilles jaunes",
                recommendedWater: "Eau filtrée"
            )
        )
        .environmentObject(ThemeManager())
    }
}
