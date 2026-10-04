import Foundation

struct MapCategory: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let color: String
    var group: String? = nil
    var summary: String? = nil
    var cadence: String? = nil
}

struct MapMarker: Codable, Identifiable, Hashable {
    let id: String
    let categoryID: String
    var title: String
    let x: Double
    let y: Double
    var details: String
    var guideURL: String?
    var imageURL: String? = nil
}

struct MapDataset: Codable {
    let schemaVersion: Int
    let id: String
    let mapID: String
    let title: String
    let coordinateSpace: String
    let source: String
    let isDemo: Bool
    let categories: [MapCategory]
    let markers: [MapMarker]
    var generatedAt: String? = nil
    var validUntil: String? = nil

    func validated() throws -> MapDataset {
        guard schemaVersion == 1, coordinateSpace == "normalized-image-v1" else {
            throw MapError.invalid("Use schemaVersion 1 and normalized-image-v1 coordinates.")
        }
        guard !id.isEmpty, !mapID.isEmpty, !title.isEmpty, !source.isEmpty else {
            throw MapError.invalid("Dataset ID, map ID, title and source are required.")
        }
        for raw in [generatedAt, validUntil].compactMap({ $0 }) {
            guard ISO8601DateFormatter().date(from: raw) != nil else {
                throw MapError.invalid("Dataset timestamps must use ISO-8601 UTC format.")
            }
        }
        guard categories.count <= 200, markers.count <= 20_000 else {
            throw MapError.invalid("Dataset exceeds 200 categories or 20,000 markers.")
        }
        let categoryIDs = Set(categories.map(\.id))
        guard categoryIDs.count == categories.count,
              categories.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty &&
                  $0.color.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else {
            throw MapError.invalid("Categories need unique IDs, titles and six-digit hex colors.")
        }
        guard Set(markers.map(\.id)).count == markers.count else {
            throw MapError.invalid("Marker IDs must be unique.")
        }
        for marker in markers {
            try marker.validate(categoryIDs: categoryIDs)
        }
        return self
    }
}

extension MapMarker {
    func validate(categoryIDs: Set<String>) throws {
        guard !id.isEmpty, !title.isEmpty, categoryIDs.contains(categoryID),
              x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw MapError.invalid("Marker \(id) needs a title, a known category and x/y between 0 and 1.")
        }
        for raw in [guideURL, imageURL].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            guard let url = URL(string: raw), url.scheme == "https", url.host != nil else {
                throw MapError.invalid("Marker media and guide links must be HTTPS URLs.")
            }
        }
    }
}

enum MapError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct MapSnapshot: Codable {
    var dataset: MapDataset
    var completed: Set<String> = []
    var favorites: Set<String> = []
    var personalMarkers: [MapMarker] = []
    var customImageFilename: String?
    var routeIDs: [String]? = nil
    var excludedRouteCategories: Set<String>? = nil
    var mapTone: String? = nil
    var feedURL: String? = nil
    var dailyResetKey: String? = nil
    var profileName: String? = nil

    var allMarkers: [MapMarker] { dataset.markers + personalMarkers }
    func validated() throws -> MapSnapshot {
        _ = try dataset.validated()
        let allIDs = Set(allMarkers.map(\.id))
        guard allIDs.count == allMarkers.count else {
            throw MapError.invalid("Personal and dataset markers must have distinct IDs.")
        }
        guard personalMarkers.count <= 5_000 else {
            throw MapError.invalid("Too many personal markers.")
        }
        let categoryIDs = Set(dataset.categories.map(\.id)).union(["personal"])
        for marker in personalMarkers { try marker.validate(categoryIDs: categoryIDs) }
        guard completed.isSubset(of: allIDs), favorites.isSubset(of: allIDs) else {
            throw MapError.invalid("Progress references unknown markers.")
        }
        let route = routeIDs ?? []
        guard route.count <= 300, Set(route).count == route.count, Set(route).isSubset(of: allIDs) else {
            throw MapError.invalid("Route must contain at most 300 distinct, known marker IDs.")
        }
        if let feedURL, !feedURL.isEmpty {
            guard let url = URL(string: feedURL), url.scheme == "https", url.host != nil else {
                throw MapError.invalid("A data feed must be an HTTPS URL.")
            }
        }
        if let filename = customImageFilename {
            guard filename == (filename as NSString).lastPathComponent,
                  filename.hasPrefix("map-"), filename.hasSuffix(".jpg") else {
                throw MapError.invalid("Invalid map image filename.")
            }
        }
        return self
    }
}

enum MapRouting {
    static func nearestFirst(_ markers: [MapMarker], startingAt start: MapMarker? = nil) -> [MapMarker] {
        var remaining = Array(markers.prefix(300))
        var output: [MapMarker] = []
        var point = start ?? remaining.first
        while !remaining.isEmpty, let from = point {
            let index = remaining.indices.min { a, b in
                distanceSquared(from, remaining[a]) < distanceSquared(from, remaining[b])
            } ?? 0
            let next = remaining.remove(at: index)
            output.append(next); point = next
        }
        return output
    }
    private static func distanceSquared(_ a: MapMarker, _ b: MapMarker) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}

enum DailyWindow {
    // GTAWeb's daily collection window rolls over at 06:00 UTC.
    static func key(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date.addingTimeInterval(-6 * 60 * 60))
    }
    static func nextReset(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = calendar.startOfDay(for: date).addingTimeInterval(6 * 60 * 60)
        return reset > date ? reset : reset.addingTimeInterval(24 * 60 * 60)
    }
}

struct MapBackup: Codable {
    let backupVersion: Int
    var snapshot: MapSnapshot
    let imageData: Data?
}

enum MapJSON {
    static func decodeDataset(_ data: Data) throws -> MapDataset {
        guard data.count <= 20 * 1_024 * 1_024 else { throw MapError.invalid("Dataset is larger than 20 MB.") }
        return try JSONDecoder().decode(MapDataset.self, from: data).validated()
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
