import SwiftUI
import PhotosUI
import UIKit

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @State private var isShowingCreatePost = false

    var body: some View {
        NavigationStack {
            AppBackground {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        AppHeader(
                            title: "Communauté",
                            subtitle: "Partagez vos jardins, transformations et astuces avec Arbore.",
                            actionSystemImage: "plus",
                            action: { isShowingCreatePost = true }
                        )

                        content
                    }

                    Button {
                        isShowingCreatePost = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 58, height: 58)
                            .background(ArboreDesign.Colors.primaryButton)
                            .clipShape(Circle())
                            .shadow(color: ArboreDesign.Colors.primaryGreen.opacity(0.28), radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Créer un post")
                    .padding(.trailing, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.bottom, ArboreDesign.Spacing.xl)
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.fetchFeed()
            }
            .refreshable {
                await viewModel.fetchFeed()
            }
            .sheet(isPresented: $isShowingCreatePost) {
                CreatePostView(viewModel: viewModel)
            }
            .alert("Communauté", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            Spacer()
            ProgressView()
                .tint(ArboreDesign.Colors.primaryGreen)
            Spacer()
        } else if viewModel.posts.isEmpty {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: ArboreDesign.Spacing.lg) {
                    ForEach(viewModel.posts) { post in
                        CommunityPostCard(post: post)
                    }
                }
                .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                .padding(.bottom, 110)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ArboreDesign.Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 72, height: 72)
                .background(ArboreDesign.Colors.softSurface)
                .clipShape(Circle())

            Text("Aucun post pour le moment")
                .font(ArboreDesign.Typography.sectionTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Text("Soyez le premier à partager une transformation, un jardin rêvé ou une astuce.")
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingCreatePost = true
            } label: {
                Label("Publier", systemImage: "plus")
            }
            .buttonStyle(.arborePrimary)
            .padding(.top, ArboreDesign.Spacing.sm)
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !isShowingCreatePost },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct CommunityPostCard: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            ZStack {
                Rectangle()
                    .fill(ArboreDesign.Colors.softSurface)
                    .aspectRatio(4 / 3, contentMode: .fit)

                if let url = URL(string: post.imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(ArboreDesign.Colors.primaryGreen)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))
            .clipped()

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                HStack(spacing: ArboreDesign.Spacing.sm) {
                    Label(post.type.title, systemImage: post.type.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .padding(.horizontal, ArboreDesign.Spacing.sm)
                        .frame(height: 30)
                        .background(ArboreDesign.Colors.softSurface)
                        .clipShape(Capsule())

                    Spacer()

                    Text(post.createdAt, style: .relative)
                        .font(ArboreDesign.Typography.caption)
                        .foregroundColor(ArboreDesign.Colors.textMuted)
                }

                Text(post.title)
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(post.description)
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Image(systemName: "heart")
                    Text("\(post.likesCount)")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .padding(.top, ArboreDesign.Spacing.xs)
            }
        }
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

struct CreatePostView: View {
    @ObservedObject var viewModel: CommunityViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedType: CommunityPostType = .beforeAfter
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
                        typePicker
                        titleField
                        descriptionField
                        imagePicker

                        if let message = localError ?? viewModel.errorMessage {
                            errorBanner(message)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: ArboreDesign.Spacing.sm) {
                                if viewModel.isUploading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(viewModel.isUploading ? "Publication..." : "Publier")
                            }
                        }
                        .buttonStyle(AppButtonStyle(variant: .primary, isEnabled: !isSubmitDisabled))
                        .disabled(isSubmitDisabled)
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.vertical, ArboreDesign.Spacing.lg)
                }
            }
            .navigationTitle("Nouveau post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { await loadSelectedImage(from: newItem) }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(image: $selectedImage)
                    .ignoresSafeArea()
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text("Type")
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Picker("Type", selection: $selectedType) {
                ForEach(CommunityPostType.allCases) { type in
                    Label(type.title, systemImage: type.systemImage)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text("Titre")
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            TextField("Ex. Mon érable après 3 mois", text: $title)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .tint(ArboreDesign.Colors.primaryGreen)
                .padding(ArboreDesign.Spacing.md)
                .background(ArboreDesign.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                        .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                )
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text("Description")
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            TextEditor(text: $description)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .tint(ArboreDesign.Colors.primaryGreen)
                .frame(minHeight: 130)
                .padding(ArboreDesign.Spacing.sm)
                .scrollContentBackground(.hidden)
                .background(ArboreDesign.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                        .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                )
        }
    }

    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text("Image")
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            ZStack {
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous)
                    .fill(ArboreDesign.Colors.softSurface)
                    .aspectRatio(4 / 3, contentMode: .fit)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))
                } else {
                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        Text("Ajoutez une photo")
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))

            HStack(spacing: ArboreDesign.Spacing.sm) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Galerie", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.arboreSecondary)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Caméra", systemImage: "camera")
                    }
                    .buttonStyle(.arboreSecondary)
                }
            }
        }
    }

    private var isSubmitDisabled: Bool {
        viewModel.isUploading ||
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedImage == nil
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(ArboreDesign.Colors.danger)

            Text(message)
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ArboreDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArboreDesign.Colors.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
    }

    private func loadSelectedImage(from item: PhotosPickerItem?) async {
        localError = nil
        guard let item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
            } else {
                localError = "Cette image ne peut pas être chargée."
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func submit() async {
        localError = nil

        guard let selectedImage else {
            localError = "Sélectionnez une image avant de publier."
            return
        }

        let success = await viewModel.uploadPost(
            title: title,
            description: description,
            type: selectedType,
            image: selectedImage
        )

        if success {
            dismiss()
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
