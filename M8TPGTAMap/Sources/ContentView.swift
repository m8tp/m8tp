import SwiftUI
import Combine

struct PendingPin: Identifiable { let id = UUID(); let x: Double; let y: Double; var title: String? = nil }
struct MarkerCluster: Identifiable { let id = UUID(); let markers: [MapMarker] }
enum AppPanel: String, Identifiable {
    case categories, locations, favorites, route, daily, data
    var id: String { rawValue }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var selectedCategories: Set<String> = []
    @State private var hideCompleted = false
    @State private var favoritesOnly = false
    @State private var panel: AppPanel?
    @State private var selectedMarker: MapMarker?
    @State private var cluster: MarkerCluster?
    @State private var pendingPin: PendingPin?
    @State private var focus = MapFocus(marker: nil)

    private var baseFiltered: [MapMarker] {
        store.markers.filter { marker in
            (selectedCategories.isEmpty || selectedCategories.contains(marker.categoryID)) &&
            (!hideCompleted || !store.isCompleted(marker)) &&
            (!favoritesOnly || store.isFavorite(marker))
        }
    }
    private var filtered: [MapMarker] {
        baseFiltered.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
            store.category(for: $0).title.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let image = store.image {
                NativeMapView(image: image, markers: filtered, categories: store.categories,
                    completed: store.snapshot.completed, focus: focus, route: store.route,
                    tone: store.snapshot.mapTone ?? "satellite",
                    onSelect: showMarker,
                    onCluster: { cluster = MarkerCluster(markers: $0) },
                    onAdd: { pendingPin = PendingPin(x: $0, y: $1) })
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "map").font(.system(size: 48)).foregroundStyle(Theme.accent)
                    Text("Add a map image").font(.title2.bold())
                    Button("Open Data") { panel = .data }.buttonStyle(.borderedProminent)
                }
            }
            VStack(spacing: 0) {
                LinearGradient(colors: [Theme.background.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                Spacer()
                LinearGradient(colors: [.clear, Theme.background.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 210)
            }.ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 12) {
                header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                    TextField("Search Los Santos", text: $search).font(.subheadline)
                        .submitLabel(.search).onSubmit { panel = .locations }
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
                    Button { panel = .categories } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent) }
                }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
                HStack {
                    Label("\(filtered.count) locations", systemImage: "mappin.and.ellipse")
                    Spacer()
                    if store.snapshot.dataset.isDemo { Text("DEMO").foregroundStyle(.orange) }
                    else { Text("LOS SANTOS").tracking(1.5) }
                }.font(.caption2.bold()).padding(.horizontal, 4).foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !store.route.isEmpty {
                            Button { panel = .route } label: {
                                HStack {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Route ready").font(.caption.bold())
                                        Text("\(store.route.count) stops · direct lines").font(.caption2)
                                    }
                                    Image(systemName: "chevron.right").font(.caption2)
                                }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        if store.feedIsExpired {
                            Label("Daily feed expired", systemImage: "clock.badge.exclamationmark")
                                .font(.caption2.bold()).foregroundStyle(.orange)
                                .padding(10).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    Spacer()
                    VStack(spacing: 10) {
                        ControlButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Fit map") { focus = MapFocus(marker: nil, fitAll: true) }
                        Menu {
                            Button("Satellite") { store.setTone("satellite") }
                            Button("Night contrast") { store.setTone("night") }
                            Button("High contrast") { store.setTone("contrast") }
                        } label: {
                            Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }.accessibilityLabel("Map appearance")
                        ControlButton(symbol: hideCompleted ? "eye.slash.fill" : "eye", label: "Toggle collected visibility") { hideCompleted.toggle() }
                    }
                }
                bottomBar
            }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
        }
        .sheet(item: $panel) { destination in
            switch destination {
            case .categories:
                CategoriesPanel(selected: $selectedCategories, hideCompleted: $hideCompleted,
                                favoritesOnly: $favoritesOnly, onOpenLocations: { panel = .locations })
                    .presentationDetents([.medium, .large])
            case .locations:
                LocationsPanel(markers: baseFiltered, title: "Locations", search: $search, onSelect: showMarker)
                    .presentationDetents([.medium, .large])
            case .favorites:
                LocationsPanel(markers: store.markers.filter { store.isFavorite($0) }, title: "Saved places", search: .constant(""), onSelect: showMarker)
                    .presentationDetents([.medium, .large])
            case .route:
                RoutePanel(candidates: filtered.filter { !store.isCompleted($0) }, onFocus: { marker in
                    panel = nil; focusMarker(marker)
                }).presentationDetents([.medium, .large])
            case .daily: DailyPanel().presentationDetents([.medium, .large])
            case .data: DataView().presentationDetents([.large])
            }
        }
        .sheet(item: $selectedMarker) { marker in
            MarkerDetailView(marker: marker) {
                selectedMarker = nil; focusMarker(marker)
            }.presentationDetents([.medium, .large])
        }
        .sheet(item: $pendingPin) { pin in AddPinView(pin: pin).presentationDetents([.medium]) }
        .sheet(item: $cluster) { group in
            LocationsPanel(markers: group.markers, title: "Nearby locations", search: .constant(""), onSelect: showMarker)
                .presentationDetents([.medium, .large])
        }
        .alert("Unable to complete action", isPresented: Binding(
            get: { store.errorMessage != nil && panel == nil && selectedMarker == nil && cluster == nil && pendingPin == nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let message = store.statusMessage {
                HStack(alignment: .top) {
                    Text(message).font(.caption)
                    Button { store.statusMessage = nil } label: { Image(systemName: "xmark") }
                }.padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 18).padding(.top, 130)
            }
        }
        .task { store.rolloverDaily(); store.writeSmokeReadinessIfRequested() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in store.rolloverDaily() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.rolloverDaily() } }
        .onChange(of: store.snapshot.dataset.id) { _, _ in
            selectedCategories = []; search = ""; focus = MapFocus(marker: nil)
            hideCompleted = false; favoritesOnly = false
        }
        .onOpenURL { url in
            guard url.scheme == "m8tpgta", url.host == "marker",
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
            func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
            if let map = value("map"), map != store.snapshot.dataset.mapID {
                store.errorMessage = "This shared location uses a different map. Import the matching map dataset first."
                return
            }
            if let id = value("id"), let marker = store.markers.first(where: { $0.id == id }),
               value("dataset") == nil || value("dataset") == store.snapshot.dataset.id {
                focusMarker(marker); showMarker(marker)
            } else if value("personal") == "1", let rawX = value("x"), let rawY = value("y"),
                      let x = Double(rawX), let y = Double(rawY), x.isFinite, y.isFinite,
                      (0...1).contains(x), (0...1).contains(y) {
                pendingPin = PendingPin(x: x, y: y, title: String((value("title") ?? "Shared pin").prefix(80)))
            } else {
                store.errorMessage = "This location is not in the active dataset. Import the matching dataset to open it."
            }
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "map.fill").font(.title3).foregroundStyle(Theme.background)
                .frame(width: 42, height: 42).background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("M8TP").font(.caption2.bold()).tracking(3).foregroundStyle(Theme.accent)
                Text("GTA Map").font(.title3.bold())
            }
            Spacer()
            ControlButton(symbol: "calendar.badge.clock", label: "Daily activities") { panel = .daily }
        }
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("Explore", "square.grid.2x2.fill", .categories)
            barButton("List", "list.bullet", .locations)
            barButton("Route", "point.topleft.down.to.point.bottomright.curvepath", .route)
            barButton("Saved", "star.fill", .favorites)
            barButton("Data", "person.crop.circle", .data)
        }.padding(.vertical, 13).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
    }
    private func barButton(_ title: String, _ symbol: String, _ target: AppPanel) -> some View {
        Button { panel = target } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }.frame(maxWidth: .infinity).foregroundStyle(target == .categories ? Theme.accent : .white)
        }
    }
    private func showMarker(_ marker: MapMarker) {
        if panel != nil || cluster != nil {
            panel = nil; cluster = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { selectedMarker = marker }
        } else { selectedMarker = marker }
    }
    private func focusMarker(_ marker: MapMarker) {
        selectedCategories = []; search = ""; hideCompleted = false; favoritesOnly = false
        focus = MapFocus(marker: marker)
    }
}

@MainActor
struct ControlButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                .foregroundStyle(.white).background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.1)))
        }.accessibilityLabel(label)
    }
}

@MainActor
struct MarkerRow: View {
    @EnvironmentObject private var store: MapStore
    let marker: MapMarker
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isCompleted(marker) ? "checkmark.circle.fill" : store.category(for: marker).symbol)
                .font(.headline).frame(width: 38, height: 38)
                .background(Color(hex: store.category(for: marker).color).opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color(hex: store.category(for: marker).color))
            VStack(alignment: .leading, spacing: 4) {
                Text(marker.title).foregroundStyle(.primary).font(.subheadline.bold())
                Text(store.category(for: marker).title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isFavorite(marker) { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

@MainActor
struct MarkerDetailView: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    let marker: MapMarker
    let onFocus: () -> Void
    @State private var confirmDelete = false
    private var shareURL: URL {
        var components = URLComponents(); components.scheme = "m8tpgta"; components.host = "marker"
        var items = [URLQueryItem(name: "id", value: marker.id),
                     URLQueryItem(name: "dataset", value: store.snapshot.dataset.id),
                     URLQueryItem(name: "map", value: store.snapshot.dataset.mapID)]
        if store.snapshot.personalMarkers.contains(where: { $0.id == marker.id }) {
            items += [URLQueryItem(name: "personal", value: "1"), URLQueryItem(name: "x", value: String(marker.x)),
                      URLQueryItem(name: "y", value: String(marker.y)), URLQueryItem(name: "title", value: marker.title)]
        }
        components.queryItems = items
        return components.url!
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let raw = marker.imageURL, let url = URL(string: raw) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo").font(.title)
                                    Text(phase.error == nil ? "Loading location photo…" : "Photo unavailable • check the source link")
                                        .font(.caption).multilineTextAlignment(.center)
                                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                                    .background(Theme.panel)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    Label(store.category(for: marker).title, systemImage: store.category(for: marker).symbol)
                        .font(.caption.bold()).foregroundStyle(Color(hex: store.category(for: marker).color))
                    Text(marker.title).font(.title2.bold())
                    Text(marker.details.isEmpty ? "No description provided." : marker.details).foregroundStyle(.secondary)
                    if store.category(for: marker).cadence == "seasonal" || store.category(for: marker).group == "Seasonal" {
                        Label("Seasonal location • availability depends on the active event", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button { store.toggleCompleted(marker) } label: {
                        Label(store.isCompleted(marker) ? "Completed" : "Mark completed", systemImage: store.isCompleted(marker) ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent)
                    HStack {
                        Button { store.toggleFavorite(marker) } label: {
                            Label(store.isFavorite(marker) ? "Saved" : "Save", systemImage: store.isFavorite(marker) ? "star.fill" : "star")
                        }
                        Button { store.toggleRoute(marker) } label: {
                            Label((store.snapshot.routeIDs ?? []).contains(marker.id) ? "In route" : "Add to route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }.buttonStyle(.bordered)
                    HStack {
                        Button(action: onFocus) { Label("Locate", systemImage: "viewfinder") }.buttonStyle(.bordered)
                        ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    }
                    if let raw = marker.guideURL, let url = URL(string: raw), url.scheme == "https" {
                        Link(destination: url) { Label("Open guide / source", systemImage: "arrow.up.right.square") }
                    }
                    if marker.imageURL != nil { Text("Location photo is loaded from its original provider.").font(.caption2).foregroundStyle(.secondary) }
                    if store.snapshot.personalMarkers.contains(where: { $0.id == marker.id }) {
                        Button("Delete personal pin", role: .destructive) { confirmDelete = true }
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Theme.background)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.confirmationDialog("Delete this personal pin?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete pin", role: .destructive) { store.deletePin(marker); dismiss() }
        }.modifier(StoreAlert())
    }
}

@MainActor
struct AddPinView: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    let pin: PendingPin
    @State private var title = ""
    @State private var details = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Pin name", text: $title)
                TextField("Notes", text: $details, axis: .vertical)
                Text("Personal pins are saved on this device.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Add a pin").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { store.addPin(title: title, details: details, x: pin.x, y: pin.y); dismiss() }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.onAppear { title = pin.title ?? "" }
    }
}
