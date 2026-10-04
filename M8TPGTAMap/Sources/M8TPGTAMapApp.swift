import SwiftUI

@main
@MainActor
struct M8TPGTAMapApp: App {
    @StateObject private var store = MapStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.72, green: 0.97, blue: 0.43)
    static let background = Color(red: 0.04, green: 0.06, blue: 0.07)
    static let panel = Color(red: 0.08, green: 0.11, blue: 0.12)
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0xB8F86F
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}
