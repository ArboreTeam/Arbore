import SwiftUI
import FirebaseAuth
import Firebase
import PhotosUI

struct ProfileView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @EnvironmentObject var themeManager: ThemeManager

    @StateObject var userService = UserService()
    @State private var userNameFetchError: String? = nil
    @State private var showUpgradeSheet = false

    // name
    @State private var firstName: String = ""
    @State private var lastName: String = ""

    // profile image
    @State private var profileImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var uploadError: String? = nil

    private var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        header()
                        currentPlanSection()
                        settingsSectionsGroup()
                        footerSection()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .onAppear {
                loadUserData()
                fetchProfileImage()
            }
            .sheet(isPresented: $showImagePicker) {
                PhotoPicker(selectedImage: $profileImage) { image in
                    if let img = image {
                        Task {
                            await uploadProfileImage(img)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header (single line name + editable photo)
    private func header() -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    if let img = profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.7, blue: 0.4),
                                        Color(red: 0.1, green: 0.6, blue: 0.3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(initials.isEmpty ? "U" : initials)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }

                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            Circle().fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.1, green: 0.4, blue: 0.2),
                                        Color(red: 0.05, green: 0.3, blue: 0.12)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ).frame(width: 32, height: 32)
                            Image(systemName: "camera.fill").foregroundColor(.white).font(.system(size: 14))
                        }
                    }
                    .offset(x: 4, y: 4)
                }

                // Name centered - both white
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text(firstName.isEmpty ? "Utilisateur" : firstName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(themeManager.textColor)
                        if !lastName.isEmpty {
                            Text(lastName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                        }
                        Spacer()
                    }

                    if isUploading {
                        Text("Uploading…").font(.caption).foregroundColor(.gray)
                    } else if let err = uploadError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Networking: upload photo (multipart/form-data)
    private func uploadProfileImage(_ image: UIImage) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }

        isUploading = true
        uploadError = nil

        let url = URL(string: "http://localhost:8080/users/\(uid)/photo")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    self.profileImage = image
                    self.isUploading = false
                }
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Erreur"
                DispatchQueue.main.async {
                    self.uploadError = "Upload failed: \(msg)"
                    self.isUploading = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.uploadError = error.localizedDescription
                self.isUploading = false
            }
        }
    }

    private func fetchProfileImage() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let url = URL(string: "http://localhost:8080/users/\(uid)/photo") else { return }

        let task = URLSession.shared.dataTask(with: url) { data, resp, err in
            guard let data = data, err == nil,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self.profileImage = img
            }
        }
        task.resume()
    }

    // MARK: - Load user data (first/last)
    private func loadUserData() {
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }

        userService.fetchUser(by: uid) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    let parts = user.name.split(whereSeparator: \.isWhitespace).map(String.init)
                    if parts.count >= 2 {
                        self.firstName = parts.first ?? ""
                        self.lastName = parts.dropFirst().joined(separator: " ")
                    } else if parts.count == 1 {
                        self.firstName = parts[0]
                        self.lastName = ""
                    } else {
                        self.loadFallbackFromAuth()
                    }
                case .failure:
                    self.loadFallbackFromAuth()
                }
            }
        }
    }

    private func loadFallbackFromAuth() {
        if let display = Auth.auth().currentUser?.displayName, !display.isEmpty {
            let parts = display.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 {
                firstName = parts.first ?? ""
                lastName = parts.dropFirst().joined(separator: " ")
            } else {
                firstName = parts.first ?? ""
            }
            return
        }
        if let email = Auth.auth().currentUser?.email {
            let local = email.split(separator: "@").first.map(String.init) ?? email
            if local.contains(".") || local.contains("_") {
                let sepParts = local.replacingOccurrences(of: "_", with: ".").split(separator: ".").map(String.init)
                if sepParts.count >= 2 {
                    firstName = sepParts.first ?? local
                    lastName = sepParts.dropFirst().joined(separator: " ")
                } else {
                    firstName = local
                }
            } else {
                firstName = local
            }
        }
    }

    // MARK: - Upgrade section (redesigned with glassmorphism)
    private func currentPlanSection() -> some View {
        VStack(spacing: 16) {
            // Current Plan Card - Glassmorphism Gray
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                            
                            Text("Plan Standard")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(themeManager.textColor)
                        }
                        
                        Text("Accès aux fonctionnalités de base")
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.secondaryTextColor)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Gratuit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)
                        
                        Text("Actif")
                            .font(.system(size: 11))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .padding(16)
                .background(
                    ZStack {
                        // Glassmorphism background - Gray transparent
                        Color.gray.opacity(0.08)
                        
                        // Glass effect border
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .cornerRadius(16)
            }

            Button(action: { showUpgradeSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .opacity(0.95)
                    Text("Try Premium")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.8, blue: 0.5),
                            Color(red: 0.0, green: 0.6, blue: 0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .animation(
                        Animation.linear(duration: 8).repeatForever(autoreverses: true),
                        value: UUID()
                    )
                )
                .cornerRadius(24)
                .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .padding(.top, 8)
        .fullScreenCover(isPresented: $showUpgradeSheet) {
            UpgradePlanView().environmentObject(themeManager)
        }
    }

    // MARK: - Settings groups (redesigned with glassmorphism)
    private func settingsSectionsGroup() -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "person.fill", label: "Personal Details", destination: PersonalDetailsView().environmentObject(themeManager)),
                    SettingRowItem(icon: "lock.fill", label: "Change Password", destination: ChangePasswordView().environmentObject(themeManager)),
                    SettingRowItem(icon: "doc.fill", label: "Privacy Policy", destination: PrivacyPolicyView().environmentObject(themeManager)),
                    SettingRowItem(icon: "doc.text.fill", label: "Terms & Conditions", destination: TermsConditionsView().environmentObject(themeManager)),
                    SettingRowItem(icon: "exclamationmark.triangle.fill", label: "Close Account", destination: CloseAccountView().environmentObject(themeManager))
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "eye.slash.fill", label: "Privacy Settings", destination: PrivacySettingsView().environmentObject(themeManager))
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "bell.fill", label: "Notification Settings", destination: NotificationsView().environmentObject(themeManager)),
                    SettingRowItem(icon: "paintbrush.fill", label: "Appearance", destination: AppearanceView().environmentObject(themeManager))
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "accessibility.fill", label: "Accessibility", destination: AccessibilityView().environmentObject(themeManager))
                ])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Information")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal, 4)
                
                settingsSection(items: [
                    SettingRowItem(icon: "info.circle.fill", label: "About Us", destination: AboutUsView().environmentObject(themeManager))
                ])
            }
        }
    }

    private func settingsSection(items: [SettingRowItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                NavigationLink(destination: item.destination) {
                    settingRowContent(item: item)
                }

                if index < items.count - 1 {
                    Divider()
                        .background(Color.gray.opacity(0.2))
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(
            ZStack {
                Color.gray.opacity(0.08)
                
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .cornerRadius(14)
    }

    private func settingRowContent(item: SettingRowItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.green)
            }

            Text(item.label)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(themeManager.textColor)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Footer
    private func footerSection() -> some View {
        VStack(spacing: 12) {
            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryTextColor)

            Button(action: logout) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 40)
    }

    private func logout() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
        } catch {
            print("Erreur de déconnexion Firebase :", error.localizedDescription)
        }
    }
}

// MARK: - SettingRowItem
struct SettingRowItem {
    let icon: String
    let label: String
    let destination: AnyView

    init<V: View>(icon: String, label: String, destination: V) {
        self.icon = icon
        self.label = label
        self.destination = AnyView(destination)
    }
}

// MARK: - PhotoPicker (PHPicker)
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass: UIImage.self) else {
                parent.onComplete(nil)
                return
            }
            item.loadObject(ofClass: UIImage.self) { image, error in
                DispatchQueue.main.async {
                    let uiimage = image as? UIImage
                    self.parent.selectedImage = uiimage
                    self.parent.onComplete(uiimage)
                }
            }
        }
    }
}

// Preview
#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
}