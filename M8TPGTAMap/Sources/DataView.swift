import SwiftUI
import UniformTypeIdentifiers

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private enum ImportKind { case dataset, image, backup }
private enum DataAction { case importDataset, importBackup, demo, catalog, reset, legacy }

@MainActor
struct DataView: View {
    @EnvironmentObject private var store: MapStore
    @State private var showImporter = false
    @State private var importKind: ImportKind = .dataset
    @State private var showExporter = false
    @State private var exportDocument = JSONFile(data: Data())
    @State private var showConfirmation = false
    @State private var action: DataAction = .demo
    @State private var successMessage: String?
    @State private var profileName = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("YOUR EXPLORATION").font(.caption.bold()).foregroundStyle(Theme.accent)
                        Text("\(store.snapshot.completed.count) / \(store.markers.count)")
                            .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                        ProgressView(value: Double(store.snapshot.completed.count), total: Double(max(1, store.markers.count)))
                        Text("\(store.snapshot.favorites.count) favorites · \(store.snapshot.personalMarkers.count) personal pins")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("Local profile") {
                    TextField("Explorer name", text: $profileName)
                        .onSubmit { store.setProfileName(String(profileName.prefix(64))) }
                    Button("Save profile name") { store.setProfileName(String(profileName.prefix(64))); successMessage = "Profile name saved locally." }
                    Text("Local profile and file backups. GTAWeb account sync is not connected.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Map & location data") {
                    LabeledContent("Dataset", value: store.snapshot.dataset.title)
                    LabeledContent("Mode", value: store.snapshot.dataset.isDemo ? "Demonstration" : "Personal / imported data")
                    Text("The bundled community dataset contains 933 locations in 38 populated sections. It is not the full GTAWeb database. Seasonal and live daily positions require additional verified data.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { request(.importDataset) } label: { Label("Import location JSON", systemImage: "square.and.arrow.down") }
                    Button { importKind = .image; showImporter = true } label: { Label("Import map image", systemImage: "photo") }
                    Text("A replacement image must use exactly the same geographic extent as the active dataset. Imported images are resized to at most 4096 pixels.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Try interface demo") { request(.demo) }
                    Button("Install bundled community locations") { request(.catalog) }
                    if store.hasLegacyPins { Button("Restore v1 pins on their original map") { request(.legacy) } }
                }
                Section("Backup & progress") {
                    Button { exportBackup() } label: { Label("Export backup", systemImage: "square.and.arrow.up") }
                    Button { request(.importBackup) } label: { Label("Restore backup", systemImage: "arrow.clockwise") }
                    Button("Reset collected progress", role: .destructive) { request(.reset) }
                    Text("Backups include your active dataset, personal pins, favorites, progress and any imported map image. Export before switching datasets.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("By category") {
                    ForEach(store.categories) { category in
                        let markers = store.markers.filter { $0.categoryID == category.id }
                        let done = markers.filter { store.isCompleted($0) }.count
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .foregroundStyle(Color(hex: category.color))
                            Spacer()
                            Text("\(done)/\(markers.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Sources & privacy") {
                    Text(store.snapshot.dataset.source).font(.caption).textSelection(.enabled)
                    Text("Coordinates and matching satellite map: Ravanger / vibe-code-gta-5-map. Photo links retain their original providers. The v1 atlas remains available for legacy pins: CreepPork / GTAV-Maps, © 2019 Ralfs Garkaklis, MIT repository license. GTA game imagery belongs to Rockstar Games.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Map source & license", destination: URL(string: "https://github.com/CreepPork/GTAV-Maps")!)
                    Link("Community coordinate source", destination: URL(string: "https://github.com/Ravanger/vibe-code-gta-5-map")!)
                    Text("Unofficial companion. No ads, analytics or account tracking. Photos and requested data-feed updates use the internet. Progress stays on this device unless exported. This app does not read or change your GTA Online account.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("M8TP GTA Map · v2.0 · iOS 17+").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Data & progress")
                .scrollContentBackground(.hidden).background(Theme.background)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importKind == .image ? [.image] : [.json],
                      allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let limit = (importKind == .backup ? 70 : importKind == .image ? 30 : 20) * 1_024 * 1_024
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
                    throw MapError.invalid("Selected file exceeds the allowed size.")
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                switch importKind {
                case .dataset: try store.installDataset(data)
                case .image: try store.importImage(data)
                case .backup: try store.restoreBackup(data)
                }
                successMessage = "Import completed and saved on this device."
            } catch { store.errorMessage = error.localizedDescription }
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "M8TP-GTA-Map-backup") { result in
            switch result {
            case .success: successMessage = "Backup exported. Keep it before changing datasets."
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(action == .reset ? "Reset progress" : "Continue", role: .destructive) { runAction() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Export a backup first if you want to keep the current data and progress.") }
        .alert("Saved", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button("OK") { successMessage = nil }
        } message: { Text(successMessage ?? "") }
        .onAppear { profileName = store.snapshot.profileName ?? "" }
        .modifier(StoreAlert())
    }
    private var confirmationTitle: String {
        switch action {
        case .reset: return "Reset all collected marks?"
        case .importBackup: return "Replace the active data with a backup?"
        case .importDataset: return "Import a new location dataset?"
        case .demo: return "Switch to demo data? Demo positions are not GTA locations."
        case .catalog: return "Install the bundled community dataset?"
        case .legacy: return "Restore your v1 pins on the original atlas?"
        }
    }
    private func request(_ next: DataAction) { action = next; showConfirmation = true }
    private func runAction() {
        do {
            switch action {
            case .importDataset: importKind = .dataset; showImporter = true
            case .importBackup: importKind = .backup; showImporter = true
            case .demo: try store.loadDemo()
            case .catalog: try store.loadCatalog()
            case .reset: store.resetProgress()
            case .legacy: try store.restoreLegacyPins()
            }
        } catch { store.errorMessage = error.localizedDescription }
    }
    private func exportBackup() {
        do { exportDocument = JSONFile(data: try store.exportBackup()); showExporter = true }
        catch { store.errorMessage = error.localizedDescription }
    }
}
