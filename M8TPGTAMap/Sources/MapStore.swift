import SwiftUI
import UIKit
import ImageIO

@MainActor
final class MapStore: ObservableObject {
    @Published private(set) var snapshot: MapSnapshot
    @Published private(set) var image: UIImage?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published var statusMessage: String?
    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("M8TPGTAMap", isDirectory: true)
        let fallback: MapDataset
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                throw MapError.invalid("Bundled catalog is missing.")
            }
            fallback = try MapJSON.decodeDataset(Data(contentsOf: url))
        } catch {
            fallback = MapDataset(schemaVersion: 1, id: "empty", mapID: "gtav-atlas-v1",
                title: "GTA Online", coordinateSpace: "normalized-image-v1", source: "No dataset installed",
                isDemo: false, categories: [], markers: [])
        }
        snapshot = MapSnapshot(dataset: fallback)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let saved = try JSONDecoder().decode(MapSnapshot.self, from: Data(contentsOf: stateURL))
                snapshot = try saved.validated()
                if saved.dataset.id == "gta-online-catalog-v1", saved.dataset.markers.isEmpty {
                    let legacy = directory.appendingPathComponent("legacy-v1-state.json")
                    if !FileManager.default.fileExists(atPath: legacy.path) {
                        try MapJSON.encode(saved).write(to: legacy, options: .atomic)
                    }
                    snapshot = MapSnapshot(dataset: fallback)
                    try MapJSON.encode(snapshot).write(to: stateURL, options: .atomic)
                    statusMessage = "New community locations installed. Previous pins are backed up in Data → Restore v1 pins."
                }
            }
        } catch {
            errorMessage = "Saved data could not be loaded. It has not been overwritten. \(error.localizedDescription)"
        }
        refreshImage()
    }

    var markers: [MapMarker] { snapshot.allMarkers }
    var categories: [MapCategory] {
        let personal = MapCategory(id: "personal", title: "My pins", symbol: "mappin", color: "B8F86F")
        return snapshot.dataset.categories.filter { $0.id != "personal" } + [personal]
    }
    func category(for marker: MapMarker) -> MapCategory {
        categories.first { $0.id == marker.categoryID } ??
            MapCategory(id: marker.categoryID, title: marker.categoryID, symbol: "mappin", color: "B8F86F")
    }
    func isCompleted(_ marker: MapMarker) -> Bool { snapshot.completed.contains(marker.id) }
    func isFavorite(_ marker: MapMarker) -> Bool { snapshot.favorites.contains(marker.id) }

    private func commit(_ next: MapSnapshot) throws {
        let valid = try next.validated()
        try MapJSON.encode(valid).write(to: stateURL, options: .atomic)
        snapshot = valid
    }
    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
    func toggleCompleted(_ marker: MapMarker) {
        perform {
            var next = snapshot
            if !next.completed.insert(marker.id).inserted { next.completed.remove(marker.id) }
            try commit(next)
        }
    }
    func toggleFavorite(_ marker: MapMarker) {
        perform {
            var next = snapshot
            if !next.favorites.insert(marker.id).inserted { next.favorites.remove(marker.id) }
            try commit(next)
        }
    }
    func addPin(title: String, details: String, x: Double, y: Double) {
        perform {
            var next = snapshot
            next.personalMarkers.append(MapMarker(id: "personal-\(UUID().uuidString)", categoryID: "personal",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), x: x, y: y,
                details: details, guideURL: nil))
            try commit(next)
        }
    }
    func deletePin(_ marker: MapMarker) {
        perform {
            var next = snapshot
            next.personalMarkers.removeAll { $0.id == marker.id }
            next.completed.remove(marker.id); next.favorites.remove(marker.id)
            next.routeIDs = (next.routeIDs ?? []).filter { $0 != marker.id }
            try commit(next)
        }
    }
    func resetProgress() {
        perform { var next = snapshot; next.completed = []; try commit(next) }
    }
    func installDataset(_ data: Data) throws {
        let dataset = try MapJSON.decodeDataset(data)
        var next = MapSnapshot(dataset: dataset)
        if dataset.id == snapshot.dataset.id && dataset.mapID == snapshot.dataset.mapID {
            next.personalMarkers = snapshot.personalMarkers
            let ids = Set(next.allMarkers.map(\.id))
            next.completed = snapshot.completed.intersection(ids)
            next.favorites = snapshot.favorites.intersection(ids)
            next.routeIDs = (snapshot.routeIDs ?? []).filter { ids.contains($0) }
            next.excludedRouteCategories = snapshot.excludedRouteCategories
            next.mapTone = snapshot.mapTone; next.feedURL = snapshot.feedURL
            next.dailyResetKey = snapshot.dailyResetKey; next.profileName = snapshot.profileName
        }
        if dataset.mapID == snapshot.dataset.mapID { next.customImageFilename = snapshot.customImageFilename }
        try commit(next)
        refreshImage()
    }
    func loadDemo() throws {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "json") else {
            throw MapError.invalid("Demo dataset is missing.")
        }
        try installDataset(Data(contentsOf: url))
    }
    func loadCatalog() throws {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw MapError.invalid("Catalog is missing.")
        }
        try installDataset(Data(contentsOf: url))
    }
    func importImage(_ data: Data) throws {
        guard let jpeg = resizedJPEG(data) else { throw MapError.invalid("Choose a valid image up to 30 MB.") }
        let filename = "map-\(UUID().uuidString).jpg"
        let destination = directory.appendingPathComponent(filename)
        try jpeg.write(to: destination, options: .atomic)
        var next = snapshot
        let previous = next.customImageFilename
        next.customImageFilename = filename
        do { try commit(next) } catch { try? FileManager.default.removeItem(at: destination); throw error }
        if let previous { removeUnreferencedImage(previous) }
        refreshImage()
    }
    func exportBackup() throws -> Data {
        let imageData = try snapshot.customImageFilename.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        return try MapJSON.encode(MapBackup(backupVersion: 1, snapshot: snapshot, imageData: imageData))
    }
    func restoreBackup(_ data: Data) throws {
        guard data.count <= 70 * 1_024 * 1_024 else { throw MapError.invalid("Backup is larger than 70 MB.") }
        let backup = try JSONDecoder().decode(MapBackup.self, from: data)
        guard backup.backupVersion == 1 else { throw MapError.invalid("Unsupported backup version.") }
        var next = try backup.snapshot.validated()
        let previous = snapshot.customImageFilename
        var imageURL: URL?
        if let imageData = backup.imageData {
            guard let jpeg = resizedJPEG(imageData) else { throw MapError.invalid("Backup map image is invalid.") }
            let filename = "map-\(UUID().uuidString).jpg"
            let url = directory.appendingPathComponent(filename)
            try jpeg.write(to: url, options: .atomic)
            imageURL = url; next.customImageFilename = filename
        } else { next.customImageFilename = nil }
        do { try commit(next) } catch {
            if let imageURL { try? FileManager.default.removeItem(at: imageURL) }
            throw error
        }
        if let previous { removeUnreferencedImage(previous) }
        refreshImage()
    }
    private func resizedJPEG(_ data: Data) -> Data? {
        guard data.count <= 30 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
    }
    private func removeUnreferencedImage(_ filename: String) {
        for backupName in ["legacy-v1-state.json", "before-legacy-restore.json"] {
            let file = directory.appendingPathComponent(backupName)
            if let data = try? Data(contentsOf: file),
               let saved = try? JSONDecoder().decode(MapSnapshot.self, from: data),
               saved.customImageFilename == filename { return }
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
    private func refreshImage() {
        if let filename = snapshot.customImageFilename {
            image = UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
            if image == nil { errorMessage = "The saved map image is missing. Import it again." }
        } else if snapshot.dataset.isDemo {
            image = UIImage(named: "DemoMap")
        } else if snapshot.dataset.mapID == "gtav-community-8192-v1" {
            if let url = Bundle.main.url(forResource: "GTAVCommunity", withExtension: "jpg") {
                image = UIImage(contentsOfFile: url.path)
            } else { image = nil }
        } else if snapshot.dataset.mapID == "gtav-atlas-v1" {
            if let url = Bundle.main.url(forResource: "GTAVAtlas", withExtension: "jpg") {
                image = UIImage(contentsOfFile: url.path)
            } else { image = nil }
        } else { image = nil }
    }
}

extension MapStore {
    func writeSmokeReadinessIfRequested() {
        guard ProcessInfo.processInfo.environment["M8TP_SMOKE_TEST"] == "1" else { return }
        let report: [String: Any] = ["markerCount": markers.count, "imageLoaded": image != nil,
                                     "isDemo": snapshot.dataset.isDemo, "datasetID": snapshot.dataset.id]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: docs.appendingPathComponent("smoke-ready.json"), options: .atomic)
        }
    }
    var route: [MapMarker] {
        let lookup = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        return (snapshot.routeIDs ?? []).compactMap { lookup[$0] }
    }
    var hasLegacyPins: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("legacy-v1-state.json").path) }
    var feedIsExpired: Bool {
        guard let raw = snapshot.dataset.validUntil, let expiry = ISO8601DateFormatter().date(from: raw) else { return false }
        return expiry <= Date()
    }
    func setTone(_ tone: String) {
        perform { var next = snapshot; next.mapTone = tone; try commit(next) }
    }
    func setProfileName(_ name: String) {
        perform { var next = snapshot; next.profileName = name; try commit(next) }
    }
    func toggleRoute(_ marker: MapMarker) {
        perform {
            var next = snapshot; var route = next.routeIDs ?? []
            if route.contains(marker.id) { route.removeAll { $0 == marker.id } }
            else {
                guard route.count < 300 else { throw MapError.invalid("A route can include up to 300 locations.") }
                route.append(marker.id)
            }
            next.routeIDs = route; try commit(next)
        }
    }
    func setRoute(_ candidates: [MapMarker], optimize: Bool = false) {
        perform {
            guard candidates.count <= 300 else { throw MapError.invalid("Select a category or filter with 300 locations or fewer.") }
            var next = snapshot
            let eligible = optimize ? candidates.filter { !(next.excludedRouteCategories ?? []).contains($0.categoryID) } : candidates
            next.routeIDs = (optimize ? MapRouting.nearestFirst(eligible) : eligible).map(\.id)
            try commit(next)
        }
    }
    func moveRoute(from offsets: IndexSet, to destination: Int) {
        perform { var next = snapshot; var ids = next.routeIDs ?? []; ids.move(fromOffsets: offsets, toOffset: destination); next.routeIDs = ids; try commit(next) }
    }
    func excludeFromRoute(_ category: MapCategory) {
        perform {
            var next = snapshot; var excluded = next.excludedRouteCategories ?? []
            if !excluded.insert(category.id).inserted { excluded.remove(category.id) }
            next.excludedRouteCategories = excluded; try commit(next)
        }
    }
    func markCategory(_ category: MapCategory, completed: Bool) {
        perform {
            let ids = Set(markers.filter { $0.categoryID == category.id }.map(\.id))
            var next = snapshot
            if completed { next.completed.formUnion(ids) } else { next.completed.subtract(ids) }
            try commit(next)
        }
    }
    func rolloverDaily() {
        let today = DailyWindow.key(at: Date())
        guard snapshot.dailyResetKey != today else { return }
        perform {
            var next = snapshot
            if next.dailyResetKey != nil {
                let daily = Set(categories.filter { $0.cadence == "daily" }.map(\.id))
                next.completed.subtract(markers.filter { daily.contains($0.categoryID) }.map(\.id))
            }
            next.dailyResetKey = today; try commit(next)
        }
    }
    func restoreLegacyPins() throws {
        let file = directory.appendingPathComponent("legacy-v1-state.json")
        let saved = try JSONDecoder().decode(MapSnapshot.self, from: Data(contentsOf: file)).validated()
        try MapJSON.encode(snapshot).write(to: directory.appendingPathComponent("before-legacy-restore.json"), options: .atomic)
        try commit(saved); refreshImage()
    }
    func refreshFeed(_ raw: String) async throws {
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { throw MapError.invalid("Enter an HTTPS dataset URL.") }
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw MapError.invalid("The data provider did not return a successful response.") }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20 * 1_024 * 1_024 else { throw MapError.invalid("Data feed exceeds 20 MB.") }
        let data = try Data(contentsOf: file)
        let incoming = try MapJSON.decodeDataset(data)
        guard incoming.id == snapshot.dataset.id, incoming.mapID == snapshot.dataset.mapID else { throw MapError.invalid("Feed dataset and map IDs must match the active dataset. Import other datasets through Data.") }
        guard let deadline = incoming.validUntil, let expiry = ISO8601DateFormatter().date(from: deadline), expiry > Date() else {
            throw MapError.invalid("A live feed needs a future validUntil ISO-8601 timestamp. Expired or undated feeds are not presented as current.")
        }
        try installDataset(data)
        var next = snapshot; next.feedURL = raw; try commit(next)
        rolloverDaily(); statusMessage = "Data feed updated."
    }
}
