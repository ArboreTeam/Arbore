import SwiftUI

#if DEBUG

@MainActor
struct DebugThumbnailGeneratorView: View {
    @StateObject private var generator = PlantThumbnailGenerator()
    @State private var plants: [Plant] = []
    @State private var isLoading = false
    @State private var selectedPlants: Set<String> = []
    @State private var generationProgress = ""
    @State private var showFileExportInfo = false

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 8) {
                    Text("🔧 Debug Thumbnail Generator")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("⚠️ Dev/Admin only - Hidden in production")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // Status Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plants: \(plants.count)")
                        .font(.caption)
                    Text("With Thumbnails: \(plants.filter { PlantThumbnailCache.exists(for: $0.id) }.count)")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Missing: \(plants.filter { !PlantThumbnailCache.exists(for: $0.id) }.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    if !generationProgress.isEmpty {
                        Text(generationProgress)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)

                // Action Buttons
                VStack(spacing: 8) {
                    Button(action: generateAllMissing) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate Missing Thumbnails")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(plants.filter { !PlantThumbnailCache.exists(for: $0.id) }.isEmpty)

                    Button(action: { showFileExportInfo = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Thumbnails to Files")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }

                    Button(action: cacheClear) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Cached Thumbnails")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.red.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                // Plant List
                List {
                    ForEach(plants) { plant in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plant.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(plant.id)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if PlantThumbnailCache.exists(for: plant.id) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("✓")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.orange)
                                    Text("✗")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Thumbnail Debug")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadPlants()
                // Monitor generation
                generator.onThumbnailGenerated = {
                    generationProgress = "Generated at \(Date().formatted(date: .omitted, time: .standard))"
                }
            }
            .alert("Export Location", isPresented: $showFileExportInfo) {
                Alert(
                    title: Text("Thumbnails Location"),
                    message: Text(
                        "Generated PNGs are in iOS app cache:\n\n" +
                        "Library/Caches/PlantThumbs/\n\n" +
                        "Use Xcode File Inspector or macOS Finder to export."
                    ),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func loadPlants() {
        Task {
            isLoading = true
            do {
                let allPlants = try await loadAllPlants()
                self.plants = allPlants.sorted { $0.name < $1.name }
            } catch {
                print("❌ Failed to load plants:", error)
            }
            isLoading = false
        }
    }

    private func generateAllMissing() {
        let missing = plants.filter { !PlantThumbnailCache.exists(for: $0.id) }
        print("🎬 Starting generation of \(missing.count) thumbnails...")
        generationProgress = "Generating \(missing.count) thumbnails..."
        generator.enqueue(plants: missing)
    }

    private func cacheClear() {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlantThumbs", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        generationProgress = "Cache cleared"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            loadPlants()
        }
    }

    private func loadAllPlants() async throws -> [Plant] {
        return try await NetworkManager.shared.request(
            endpoint: "/plants",
            method: .GET
        )
    }
}

#Preview {
    DebugThumbnailGeneratorView()
}

#endif
