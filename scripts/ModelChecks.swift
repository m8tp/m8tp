import Foundation

@main
struct ModelChecks {
    static func main() throws {
        let catalog = try MapJSON.decodeDataset(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let demo = try MapJSON.decodeDataset(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        precondition(!catalog.isDemo && catalog.markers.count == 933)
        precondition(demo.isDemo && !demo.markers.isEmpty)
        var snapshot = MapSnapshot(dataset: demo)
        snapshot.completed.insert(demo.markers[0].id)
        snapshot.favorites.insert(demo.markers[0].id)
        _ = try snapshot.validated()
        let backup = MapBackup(backupVersion: 1, snapshot: snapshot, imageData: nil)
        let restored = try JSONDecoder().decode(MapBackup.self, from: MapJSON.encode(backup))
        precondition(restored.snapshot.completed == snapshot.completed)
        precondition(restored.snapshot.favorites == snapshot.favorites)
        try expectInvalid { var bad = snapshot; bad.completed.insert("does-not-exist"); _ = try bad.validated() }
        try expectInvalid { var bad = snapshot; bad.personalMarkers = [demo.markers[0]]; _ = try bad.validated() }
        try expectInvalid {
            try MapMarker(id: "bad", categoryID: demo.categories[0].id, title: "Bad", x: -0.1, y: 0.5,
                          details: "", guideURL: nil).validate(categoryIDs: Set(demo.categories.map(\.id)))
        }
        try expectInvalid {
            try MapMarker(id: "bad", categoryID: demo.categories[0].id, title: "Bad", x: 0.5, y: 0.5,
                          details: "", guideURL: "javascript:alert(1)").validate(categoryIDs: Set(demo.categories.map(\.id)))
        }
        try expectInvalid { var bad = snapshot; bad.customImageFilename = "../map-evil.jpg"; _ = try bad.validated() }
        try expectInvalid { var bad = snapshot; bad.routeIDs = [demo.markers[0].id, demo.markers[0].id]; _ = try bad.validated() }
        let route = MapRouting.nearestFirst(Array(catalog.markers.prefix(12)))
        precondition(route.count == 12 && Set(route.map(\.id)) == Set(catalog.markers.prefix(12).map(\.id)))
        let iso = ISO8601DateFormatter()
        let before = iso.date(from: "2026-10-04T05:59:59Z")!
        let after = iso.date(from: "2026-10-04T06:00:00Z")!
        precondition(DailyWindow.key(at: before) == "2026-10-03")
        precondition(DailyWindow.key(at: after) == "2026-10-04")
        precondition(DailyWindow.nextReset(after: before) == after)
        precondition(DailyWindow.nextReset(after: after) == iso.date(from: "2026-10-05T06:00:00Z")!)
        snapshot.routeIDs = [demo.markers[0].id]
        let routeBackup = try JSONDecoder().decode(MapSnapshot.self, from: MapJSON.encode(snapshot))
        precondition(routeBackup.routeIDs == snapshot.routeIDs)
        print("Model checks passed: normalized coordinates, references, IDs, URL validation and backup round trip.")
    }
    static func expectInvalid(_ work: () throws -> Void) throws {
        do { try work() } catch { return }
        throw MapError.invalid("Invalid input was unexpectedly accepted.")
    }
}
