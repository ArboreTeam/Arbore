import SwiftUI
import SwiftData
import PhotosUI
import Combine

struct ChatBotView: View {
    let showsDismissButton: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]
    @State private var activeConversationId: UUID? = nil
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var conversationToRename: ChatConversation? = nil
    @State private var renameText = ""
    @State private var apiErrorMessage: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingImageData: Data? = nil
    @EnvironmentObject var themeManager: ThemeManager
    @FocusState private var isFocused: Bool

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let activeConversationId, let conv = conversations.first(where: { $0.id == activeConversationId }) {
                    chatView(conversation: conv)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    historyView
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeConversationId)
        }
    }

    // MARK: - History

    private var historyView: some View {
        AppBackground {
            VStack(spacing: 0) {
                // Header matching HomeView style
                HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                    if showsDismissButton {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.textPrimary)
                                .frame(width: 42, height: 42)
                                .background(ArboreDesign.Colors.softSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fermer le Chat")
                    }

                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                        Text("Chat")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Text("Posez vos questions à Arbore, votre assistant jardinage.")
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                    }

                    Spacer(minLength: ArboreDesign.Spacing.sm)

                    if !conversations.isEmpty {
                        Button {
                            let conv = ChatConversation(title: "Nouvelle discussion")
                            modelContext.insert(conv)
                            activeConversationId = conv.id
                        } label: {
                            Image(systemName: "plus")
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

                if conversations.isEmpty {
                    emptyHistory
                } else {
                    conversationList
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Renommer la conversation", isPresented: .init(get: {
            conversationToRename != nil
        }, set: { newValue in
            if !newValue { conversationToRename = nil }
        })) {
            TextField("Titre", text: $renameText)
            Button("Annuler", role: .cancel) {
                conversationToRename = nil
            }
            Button("OK") {
                if let conv = conversationToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    conv.title = renameText.trimmingCharacters(in: .whitespaces)
                    conv.updatedAt = Date()
                }
                conversationToRename = nil
            }
        } message: {
            Text("Entrez un nouveau nom pour cette discussion.")
        }
    }

    // MARK: - Empty History

    private var emptyHistory: some View {
        VStack(spacing: ArboreDesign.Spacing.xl) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 64, height: 64)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Circle())

            VStack(spacing: ArboreDesign.Spacing.xs) {
                Text("Aucune conversation")
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text("Commencez une nouvelle discussion\navec l'assistant jardinage.")
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                let conv = ChatConversation(title: "Nouvelle discussion")
                modelContext.insert(conv)
                activeConversationId = conv.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Nouveau chat")
                        .font(ArboreDesign.Typography.button)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(ArboreDesign.Colors.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ArboreDesign.Spacing.xxl)

            Spacer()
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: ArboreDesign.Spacing.sm) {
                ForEach(conversations) { conv in
                    Button {
                        activeConversationId = conv.id
                    } label: {
                        HStack(spacing: ArboreDesign.Spacing.md) {
                            // Icon badge matching SettingsRow style
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                .frame(width: 42, height: 42)
                                .background(ArboreDesign.Colors.primaryGreen.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(ArboreDesign.Typography.cardTitle)
                                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                                    .lineLimit(1)

                                HStack(spacing: ArboreDesign.Spacing.xs) {
                                    Text("\(conv.messages.count) messages")
                                        .font(ArboreDesign.Typography.caption)
                                        .foregroundColor(ArboreDesign.Colors.textSecondary)

                                    Text("·")
                                        .foregroundColor(ArboreDesign.Colors.textMuted)

                                    Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(ArboreDesign.Typography.caption)
                                        .foregroundColor(ArboreDesign.Colors.textMuted)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
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
                        .shadow(color: ArboreDesign.Colors.shadow, radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(conv)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button {
                            conversationToRename = conv
                            renameText = conv.title
                        } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                        .tint(ArboreDesign.Colors.primaryGreen)
                    }
                }
            }
            .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
            .padding(.top, ArboreDesign.Spacing.xs)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Chat View

    private func chatView(conversation: ChatConversation) -> some View {
        let sortedMessages = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })

        return AppBackground {
            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: ArboreDesign.Spacing.sm) {
                    Button {
                        activeConversationId = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(conversation.title)
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    // Balance spacer
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

                // Error banner
                if let error = apiErrorMessage {
                    HStack(spacing: ArboreDesign.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(ArboreDesign.Colors.danger)

                        Text(error)
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.danger)
                            .lineLimit(3)
                    }
                    .padding(ArboreDesign.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ArboreDesign.Colors.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.small, style: .continuous))
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.xs)
                }

                if sortedMessages.isEmpty {
                    emptyChat
                        .safeAreaInset(edge: .bottom) {
                            bottomBar
                        }
                } else {
                    chatList(messages: sortedMessages)
                        .safeAreaInset(edge: .bottom) {
                            bottomBar
                        }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Empty Chat

    private var emptyChat: some View {
        VStack(spacing: ArboreDesign.Spacing.md) {
            Spacer()

            Image(systemName: "leaf.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 56, height: 56)
                .background(ArboreDesign.Colors.primaryGreen.opacity(0.14))
                .clipShape(Circle())

            VStack(spacing: ArboreDesign.Spacing.xs) {
                Text("Posez votre question")
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text("Je peux vous aider sur le jardinage,\nles plantes, l'entretien, et plus encore.")
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Suggestion chips
            VStack(spacing: ArboreDesign.Spacing.xs) {
                suggestionChip("🌱 Comment arroser mes tomates ?")
                suggestionChip("🌿 Identifier une plante malade")
                suggestionChip("☀️ Quelles plantes pour un balcon sud ?")
            }
            .padding(.top, ArboreDesign.Spacing.sm)

            Spacer()
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            sendMessage(text)
        } label: {
            Text(text)
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .padding(.horizontal, ArboreDesign.Spacing.md)
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                        .stroke(ArboreDesign.Colors.primaryGreen.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isTyping)
    }

    // MARK: - Chat Messages List

    private func chatList(messages: [ChatMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ArboreDesign.Spacing.sm) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 10)),
                                removal: .opacity
                            ))
                    }

                    if isTyping {
                        HStack {
                            TypingIndicator()
                                .padding(ArboreDesign.Spacing.sm)
                                .background(ArboreDesign.Colors.card)
                                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                                        .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                                )
                            Spacer()
                        }
                        .padding(.horizontal, ArboreDesign.Spacing.md)
                        .id("typing")
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    }
                }
                .padding(.vertical, ArboreDesign.Spacing.md)
            }
            .onChange(of: conversations.first(where: { $0.id == activeConversationId })?.messages.count ?? 0) { _, _ in
                withAnimation {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Pending image preview
            if let imgData = pendingImageData, let uiImage = UIImage(data: imgData) {
                HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo sélectionnée")
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                        Text("Appuyez sur envoyer pour analyser")
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.textMuted)
                    }

                    Spacer()

                    Button {
                        pendingImageData = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(ArboreDesign.Colors.softSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(ArboreDesign.Spacing.sm)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                .padding(.horizontal, ArboreDesign.Spacing.md)
                .padding(.top, ArboreDesign.Spacing.sm)
            }

            HStack(spacing: ArboreDesign.Spacing.sm) {
                // Photo picker button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isTyping ? ArboreDesign.Colors.textMuted : ArboreDesign.Colors.primaryGreen)
                        .frame(width: 40, height: 40)
                        .background(ArboreDesign.Colors.softSurface)
                        .clipShape(Circle())
                }
                .disabled(isTyping)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let newItem,
                           let data = try? await newItem.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                if let uiImage = UIImage(data: data),
                                   let compressed = Self.compressImage(uiImage, maxDimension: 800, quality: 0.7) {
                                    pendingImageData = compressed
                                } else {
                                    pendingImageData = data
                                }
                            }
                        }
                        await MainActor.run { selectedPhotoItem = nil }
                    }
                }

                // Text field
                HStack {
                    TextField("Votre question...", text: $inputText)
                        .font(ArboreDesign.Typography.body)
                        .focused($isFocused)
                }
                .padding(.horizontal, ArboreDesign.Spacing.md)
                .frame(height: 44)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.full, style: .continuous))

                // Send button
                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasText = !text.isEmpty
                    let hasImage = pendingImageData != nil
                    guard hasText || hasImage else { return }
                    sendMessage(hasText ? text : "Analyse cette plante", imageData: pendingImageData)
                    pendingImageData = nil
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImageData == nil)
                            ? ArboreDesign.Colors.textMuted
                            : ArboreDesign.Colors.primaryButton
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled((inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImageData == nil) || isTyping)
            }
            .padding(.horizontal, ArboreDesign.Spacing.md)
            .padding(.vertical, ArboreDesign.Spacing.sm)
        }
        .padding(.top, 40)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        )
    }

    // MARK: - Helpers

    private static func compressImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String, imageData: Data? = nil) {
        guard let conv = conversations.first(where: { $0.id == activeConversationId }) else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            let userMsg = ChatMessage(content: text, isUser: true, imageData: imageData)
            userMsg.conversation = conv
            modelContext.insert(userMsg)

            if conv.messages.count <= 1 {
                let prefix = String(text.prefix(40))
                conv.title = prefix + (text.count > 40 ? "..." : "")
            }
            conv.updatedAt = Date()

            inputText = ""
            isFocused = false
            apiErrorMessage = nil

            isTyping = true
        }
        let historyMessages = conv.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .dropLast()

        Task {
            do {
                let service = GeminiService()
                let reply = try await service.sendMessage(
                    history: historyMessages.map { MessageDTO(content: $0.content, isUser: $0.isUser) },
                    newMessage: text,
                    imageData: imageData
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        let botMsg = ChatMessage(content: reply, isUser: false)
                        botMsg.conversation = conv
                        modelContext.insert(botMsg)
                        conv.updatedAt = Date()
                        isTyping = false
                    }
                }
            } catch GeminiError.noAPIKey {
                await MainActor.run {
                    isTyping = false
                    apiErrorMessage = "Clé API Gemini manquante. Obtenez-en une sur https://aistudio.google.com/apikey"
                }
            } catch GeminiError.blocked {
                await MainActor.run {
                    isTyping = false
                    apiErrorMessage = "Réponse bloquée pour des raisons de sécurité."
                }
            } catch GeminiError.invalidResponse {
                await MainActor.run {
                    isTyping = false
                    apiErrorMessage = "Réponse invalide de l'API Gemini."
                }
            } catch GeminiError.requestFailed(let underlying) {
                await MainActor.run {
                    isTyping = false
                    apiErrorMessage = "Erreur Gemini : \((underlying as? LocalizedError)?.errorDescription ?? underlying.localizedDescription)"
                }
            } catch {
                await MainActor.run {
                    isTyping = false
                    apiErrorMessage = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - DTO for Gemini API (lightweight, non-SwiftData)

struct MessageDTO {
    let content: String
    let isUser: Bool
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: ArboreDesign.Spacing.xs) {
            if message.isUser {
                Spacer(minLength: 50)
            } else {
                // Bot avatar
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .frame(width: 28, height: 28)
                    .background(ArboreDesign.Colors.primaryGreen.opacity(0.14))
                    .clipShape(Circle())
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                // Display image if present
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(ArboreDesign.Typography.body)
                        .foregroundColor(message.isUser ? .white : ArboreDesign.Colors.textPrimary)
                }
            }
            .padding(ArboreDesign.Spacing.sm)
            .background(
                message.isUser
                ? ArboreDesign.Colors.primaryButton
                : ArboreDesign.Colors.card
            )
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
            .overlay(
                Group {
                    if !message.isUser {
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                            .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                    }
                }
            )
            .shadow(color: message.isUser ? .clear : ArboreDesign.Colors.shadow, radius: 4, x: 0, y: 2)

            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, ArboreDesign.Spacing.md)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ArboreDesign.Colors.primaryGreen)
                        .frame(width: 7, height: 7)
                        .opacity(i < dotCount ? 1 : 0.25)
                        .animation(.easeInOut(duration: 0.3), value: dotCount)
                }
            }
        }
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}
