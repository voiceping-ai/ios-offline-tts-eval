import SwiftUI

struct ModelsView: View {
    @Environment(AppModel.self) private var app
    @State private var showAddCustom = false

    var body: some View {
        List {
            Section("Curated (Verified)") {
                ForEach(app.curatedModels, id: \.id) { model in
                    ModelRow(model: model, isCustom: false)
                }
            }

            Section("Community (Unverified)") {
                if app.communityModels.isEmpty {
                    Text("No community models.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.communityModels, id: \.id) { model in
                        ModelRow(model: model, isCustom: false)
                    }
                }
            }

            Section("Custom") {
                if app.customModels.isEmpty {
                    Text("No custom models.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.customModels, id: \.id) { model in
                        ModelRow(model: model, isCustom: true)
                    }
                }

                Button {
                    showAddCustom = true
                } label: {
                    Label("Add Custom Model", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Models")
        .sheet(isPresented: $showAddCustom) {
            NavigationStack {
                CustomModelSheet { newModel in
                    app.addCustomModel(newModel)
                    showAddCustom = false
                } onCancel: {
                    showAddCustom = false
                }
            }
        }
    }
}

private struct ModelRow: View {
    @Environment(AppModel.self) private var app

    let model: TTSModel
    let isCustom: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.engineId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }

            if ModelStorage.isModelDownloaded(model) {
                let bytes = ModelStorage.downloadedSizeBytes(modelId: model.id)
                Text("On disk: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let est = model.estimatedSizeBytes {
                Text("Estimated: \(ByteCountFormatter.string(fromByteCount: est, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !ModelStorage.isModelDownloaded(model), !model.artifacts.isEmpty {
                    Button("Download") {
                        Task { @MainActor in
                            do { try await app.downloadModel(model) } catch { }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if ModelStorage.isModelDownloaded(model), (!model.artifacts.isEmpty || !model.localRequiredPaths.isEmpty) {
                    Button("Delete Files", role: .destructive) {
                        app.deleteDownloaded(modelId: model.id)
                    }
                    .buttonStyle(.bordered)
                }

                if isCustom {
                    Button("Remove Custom", role: .destructive) {
                        app.deleteCustomModel(modelId: model.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch app.status(for: model.id) {
        case .ready:
            Text("Ready")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        case .notDownloaded:
            Text("Not downloaded")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        case .downloading(let progress, _):
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        case .failed:
            Text("Failed")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        case .unknown:
            Text("Unknown")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }
}
