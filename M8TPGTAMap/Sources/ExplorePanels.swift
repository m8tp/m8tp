import SwiftUI

@MainActor
struct StoreAlert: ViewModifier {
    @EnvironmentObject private var store: MapStore
    func body(content: Content) -> some View {
        content.alert("Unable to complete action", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

@MainActor
struct CategoriesPanel: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Set<String>
    @Binding var hideCompleted: Bool
    @Binding var favoritesOnly: Bool
    let onOpenLocations: () -> Void
    @State private var categorySearch = ""
    @State private var info: MapCategory?
    private var groups: [String] {
        let names = Set(store.categories.map { $0.group ?? "Personal" })
        let order = ["Collectibles", "Daily", "Seasonal", "Activities", "Shopping", "Public Places", "Services", "Properties", "Personal"]
        return order.filter { names.contains($0) } + names.subtracting(order).sorted()
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Show all") { selected = [] }
                        Spacer()
                        Button("Hide all") { selected = ["__none__"] }
                    }
                    Toggle("Hide completed", isOn: $hideCompleted)
                    Toggle("Favorites only", isOn: $favoritesOnly)
                    Button("Browse matching locations", action: onOpenLocations)
                }
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(store.categories.filter {
                            ($0.group ?? "Personal") == group &&
                            (categorySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(categorySearch))
                        }) { category in
                            CategorySelectionRow(category: category, selected: $selected, onInfo: { info = category })
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $categorySearch, prompt: "Search categories")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.sheet(item: $info) { category in CategoryInfoPanel(category: category).presentationDetents([.medium, .large]) }
            .modifier(StoreAlert())
    }
}

@MainActor
struct CategorySelectionRow: View {
    @EnvironmentObject private var store: MapStore
    let category: MapCategory
    @Binding var selected: Set<String>
    let onInfo: () -> Void
    private var markers: [MapMarker] { store.markers.filter { $0.categoryID == category.id } }
    private var visible: Bool { selected.isEmpty || selected.contains(category.id) }
    var body: some View {
        HStack(spacing: 10) {
            Button {
                if selected.isEmpty { selected = Set(store.categories.map(\.id)) }
                selected.remove("__none__")
                if !selected.insert(category.id).inserted { selected.remove(category.id) }
                if selected.isEmpty { selected = ["__none__"] }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(visible ? Color(hex: category.color) : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title).font(.subheadline.bold()).foregroundStyle(.primary)
                        if markers.isEmpty { Text("Location data needed").font(.caption2).foregroundStyle(.orange) }
                        else {
                            Text("\(markers.filter { store.isCompleted($0) }.count) / \(markers.count) completed")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }.buttonStyle(.plain)
            Button(action: onInfo) { Image(systemName: "info.circle").font(.title3).foregroundStyle(.secondary) }
                .buttonStyle(.borderless).accessibilityLabel("\(category.title) details")
        }.padding(.vertical, 5).listRowBackground(Theme.panel)
    }
}

@MainActor
struct CategoryInfoPanel: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    let category: MapCategory
    @State private var confirm = false
    @State private var markAll = false
    private var markers: [MapMarker] { store.markers.filter { $0.categoryID == category.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(category.title, systemImage: category.symbol).font(.title3.bold())
                        .foregroundStyle(Color(hex: category.color))
                    Text(category.summary ?? "Imported locations in this category.").foregroundStyle(.secondary)
                    LabeledContent("Locations", value: "\(markers.count)")
                    LabeledContent("Completed", value: "\(markers.filter { store.isCompleted($0) }.count)")
                    LabeledContent("Availability", value: (category.cadence ?? "static").capitalized)
                }
                Section("Route") {
                    Button {
                        store.excludeFromRoute(category)
                    } label: {
                        Label((store.snapshot.excludedRouteCategories ?? []).contains(category.id) ? "Excluded from automatic routes" : "Included in automatic routes",
                              systemImage: (store.snapshot.excludedRouteCategories ?? []).contains(category.id) ? "minus.circle" : "checkmark.circle")
                    }
                    Button("Plan remaining locations") { store.setRoute(markers.filter { !store.isCompleted($0) }, optimize: true) }
                        .disabled(markers.isEmpty)
                }
                Section("Progress") {
                    Button("Mark entire section completed") { markAll = true; confirm = true }.disabled(markers.isEmpty)
                    Button("Reset this section", role: .destructive) { markAll = false; confirm = true }.disabled(markers.isEmpty)
                    if category.cadence == "daily" {
                        Text("Daily completion resets at 06:00 UTC. Current positions require a dated, unexpired feed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Category details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.confirmationDialog(markAll ? "Mark this entire section completed?" : "Reset this section’s progress?",
                             isPresented: $confirm, titleVisibility: .visible) {
            Button(markAll ? "Mark completed" : "Reset section", role: .destructive) { store.markCategory(category, completed: markAll) }
        }.modifier(StoreAlert())
    }
}

@MainActor
struct LocationsPanel: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    let markers: [MapMarker]
    let title: String
    @Binding var search: String
    let onSelect: (MapMarker) -> Void
    @State private var localSearch = ""
    private var query: String { title == "Locations" ? search : localSearch }
    private var queryBinding: Binding<String> { title == "Locations" ? $search : $localSearch }
    private var matching: [MapMarker] {
        markers.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
            store.category(for: $0).title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(matching.count) places").font(.caption.bold()).foregroundStyle(.secondary)
                    if matching.isEmpty {
                        Text("No matching places. Check the active filters or import a location dataset.")
                            .foregroundStyle(.secondary).padding(.vertical, 10)
                    }
                    ForEach(matching) { marker in
                        Button { onSelect(marker) } label: { MarkerRow(marker: marker) }
                            .listRowBackground(Theme.panel)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { store.toggleCompleted(marker) } label: { Label("Completed", systemImage: "checkmark") }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { store.toggleFavorite(marker) } label: { Label("Save", systemImage: "star") }.tint(.orange)
                                Button { store.toggleRoute(marker) } label: { Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tint(.blue)
                            }
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .searchable(text: queryBinding, prompt: "Search this list")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.modifier(StoreAlert())
    }
}

@MainActor
struct RoutePanel: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    let candidates: [MapMarker]
    let onFocus: (MapMarker) -> Void
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Plan your next run").font(.title3.bold())
                    Text("Routes connect pins with direct lines. They are not road directions. Up to 300 stops; nearest-first ordering is a heuristic.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Plan visible remaining locations (\(candidates.count))") { store.setRoute(candidates, optimize: true) }
                        .disabled(candidates.isEmpty)
                    Button("Reorder nearest first") { store.setRoute(store.route, optimize: true) }.disabled(store.route.isEmpty)
                }
                Section("\(store.route.count) stops • drag to reorder") {
                    if store.route.isEmpty { Text("Open a location and choose Add to route, or plan a filtered category.").foregroundStyle(.secondary) }
                    ForEach(Array(store.route.enumerated()), id: \.element.id) { index, marker in
                        Button { onFocus(marker) } label: {
                            HStack {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(Theme.accent).frame(width: 24)
                                MarkerRow(marker: marker)
                            }
                        }
                    }
                    .onMove { store.moveRoute(from: $0, to: $1) }
                    .onDelete { offsets in
                        store.setRoute(store.route.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
                    }
                }
                Section {
                    if !store.route.isEmpty {
                        ShareLink(item: store.route.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")) {
                            Label("Share stop list", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Clear route", role: .destructive) { confirmClear = true }.disabled(store.route.isEmpty)
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("Route planner").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                }
        }.confirmationDialog("Clear the current route?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear route", role: .destructive) { store.setRoute([]) }
        }.modifier(StoreAlert())
    }
}

@MainActor
struct DailyPanel: View {
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    @State private var feedURL = ""
    private var dailyCategories: [MapCategory] { store.categories.filter { $0.cadence == "daily" || $0.group == "Seasonal" } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        VStack(alignment: .leading, spacing: 10) {
                            Label("NEXT DAILY RESET", systemImage: "clock").font(.caption.bold()).foregroundStyle(Theme.accent)
                            Text(DailyWindow.nextReset(after: timeline.date), style: .timer).font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("06:00 UTC • completion for daily categories only").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    Text(store.feedIsExpired ? "The data feed has expired. Refresh before relying on daily positions." :
                        store.snapshot.dataset.validUntil == nil ? "Live daily positions are not connected. Empty sections do not indicate that an event is inactive." :
                        "A dated feed is installed. Check its source and validity before your run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Daily & seasonal sections") {
                    ForEach(dailyCategories) { category in
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                            Spacer()
                            let count = store.markers.filter { $0.categoryID == category.id }.count
                            Text(count == 0 ? "Data needed" : "\(count) positions").font(.caption).foregroundStyle(count == 0 ? .orange : .secondary)
                        }
                    }
                }
                Section("Your verified data feed") {
                    TextField("https://…/dataset.json", text: $feedURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button {
                        Task {
                            do { try await store.refreshFeed(feedURL) }
                            catch { store.errorMessage = error.localizedDescription }
                        }
                    } label: {
                        HStack { Text("Refresh dated data"); if store.isRefreshing { ProgressView() } }
                    }.disabled(store.isRefreshing || feedURL.isEmpty)
                    Text("No GTAWeb API is connected. Use a compatible JSON feed with matching dataset/map IDs and a future validity timestamp, or import verified data in Data.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open original GTAWeb map", destination: URL(string: "https://gtaweb.eu/gtao-map/ls/")!)
                }
            }.navigationTitle("Daily & seasonal").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.onAppear { feedURL = store.snapshot.feedURL ?? ""; store.rolloverDaily() }.modifier(StoreAlert())
    }
}
