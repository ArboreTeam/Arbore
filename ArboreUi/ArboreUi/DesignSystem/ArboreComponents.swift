import SwiftUI
import UIKit

struct AppBackground<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            ArboreDesign.Colors.background.ignoresSafeArea()
            content
        }
    }
}

struct AppHeader: View {
    let title: String
    var subtitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                Text(title)
                    .font(ArboreDesign.Typography.pageTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ArboreDesign.Spacing.sm)

            if let actionSystemImage, let action {
                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .frame(width: 42, height: 42)
                        .background(ArboreDesign.Colors.softSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .padding(.vertical, ArboreDesign.Spacing.md)
    }
}

enum AppButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

struct AppButtonStyle: ButtonStyle {
    var variant: AppButtonVariant = .primary
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArboreDesign.Typography.button)
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .stroke(borderColor, lineWidth: variant == .ghost ? 1 : 0)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.48)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var height: CGFloat {
        variant == .ghost ? 48 : 52
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .danger:
            return .white
        case .secondary, .ghost:
            return ArboreDesign.Colors.primaryGreen
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return ArboreDesign.Colors.softSurface }

        switch variant {
        case .primary:
            return ArboreDesign.Colors.primaryButton
        case .secondary:
            return ArboreDesign.Colors.softSurface
        case .ghost:
            return .clear
        case .danger:
            return ArboreDesign.Colors.danger
        }
    }

    private var borderColor: Color {
        variant == .ghost ? ArboreDesign.Colors.border : .clear
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var arborePrimary: AppButtonStyle { AppButtonStyle(variant: .primary) }
    static var arboreSecondary: AppButtonStyle { AppButtonStyle(variant: .secondary) }
    static var arboreGhost: AppButtonStyle { AppButtonStyle(variant: .ghost) }
    static var arboreDanger: AppButtonStyle { AppButtonStyle(variant: .danger) }
}

struct AppTextField: View {
    @Binding var text: String
    let placeholder: String
    var systemImage: String?
    var isSecure = false
    var keyboardType: UIKeyboardType = .default

    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isFocused ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.textSecondary)
                    .frame(width: 22)
            }

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(ArboreDesign.Typography.body)
                        .foregroundColor(ArboreDesign.Colors.placeholder)
                }

                field
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .keyboardType(keyboardType)
                    .focused($isFocused)
                    .tint(ArboreDesign.Colors.primaryGreen)
            }

            if isSecure {
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 50)
        .padding(.horizontal, ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                .stroke(isFocused ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.border, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private var field: some View {
        if isSecure && !isPasswordVisible {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}

struct AppCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(ArboreDesign.Spacing.cardPadding)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
            .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String?
    var isSelected = false

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(isSelected ? .white : ArboreDesign.Colors.primaryGreen)
        .padding(.horizontal, ArboreDesign.Spacing.sm)
        .frame(height: 34)
        .background(isSelected ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.softSurface)
        .clipShape(Capsule())
    }
}

struct SettingsRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color = ArboreDesign.Colors.primaryGreen

    var body: some View {
        HStack(spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ArboreDesign.Typography.cardTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: ArboreDesign.Icons.chevron)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(ArboreDesign.Typography.sectionTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
            }
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: ArboreDesign.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 64, height: 64)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Circle())

            VStack(spacing: ArboreDesign.Spacing.xs) {
                Text(title)
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(message)
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.arborePrimary)
            }
        }
        .padding(ArboreDesign.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingView: View {
    var title = "Chargement..."

    var body: some View {
        VStack(spacing: ArboreDesign.Spacing.sm) {
            ProgressView()
                .tint(ArboreDesign.Colors.primaryGreen)

            Text(title)
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(ArboreDesign.Spacing.xl)
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    var contentSpacing: CGFloat = ArboreDesign.Spacing.xl
    private let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        contentSpacing: CGFloat = ArboreDesign.Spacing.xl,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.content = content()
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                SettingsTopBar(title: title) {
                    dismiss()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        content
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.lg)
                    .padding(.bottom, ArboreDesign.Spacing.xxl)
                }
            }
        }
    }
}

struct SettingsTopBar: View {
    let title: String
    let dismissAction: () -> Void

    var body: some View {
        HStack {
            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(ArboreDesign.Colors.softSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Color.clear
                .frame(width: 38, height: 38)
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .frame(height: 58)
        .background(ArboreDesign.Colors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ArboreDesign.Colors.border)
                .frame(height: 1)
        }
    }
}

struct SettingsIntroCard: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = ArboreDesign.Colors.primaryGreen

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: systemImage, tint: tint, size: 48)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(title)
                        .font(ArboreDesign.Typography.sectionTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    var tint: Color = ArboreDesign.Colors.primaryGreen
    private let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = ArboreDesign.Colors.primaryGreen,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                HStack(spacing: ArboreDesign.Spacing.sm) {
                    if let systemImage {
                        SettingsIconBadge(systemImage: systemImage, tint: tint, size: 34)
                    }

                    Text(title)
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                content
            }
        }
    }
}

struct SettingsIconBadge: View {
    let systemImage: String
    var tint: Color = ArboreDesign.Colors.primaryGreen
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size <= 36 ? 15 : 18, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: min(ArboreDesign.Radius.medium, size / 3), style: .continuous))
    }
}

struct SettingsInfoRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color = ArboreDesign.Colors.primaryGreen

    var body: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(systemImage: systemImage, tint: tint, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct SettingsToggleRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var tint: Color = ArboreDesign.Colors.primaryGreen

    var body: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(systemImage: systemImage, tint: tint, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ArboreDesign.Spacing.sm)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ArboreDesign.Colors.primaryGreen)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(ArboreDesign.Colors.border)
    }
}
