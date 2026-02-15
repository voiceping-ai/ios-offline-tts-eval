import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            NavigationStack {
                SpeakView()
            }
            .tabItem { Label("Speak", systemImage: "text.bubble.fill") }

            NavigationStack {
                BenchmarkView()
            }
            .tabItem { Label("Benchmark", systemImage: "gauge.with.dots.needle.67percent") }

            NavigationStack {
                ModelsView()
            }
            .tabItem { Label("Models", systemImage: "shippingbox.fill") }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { app.lastError != nil },
                set: { if !$0 { app.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { app.lastError = nil }
        } message: {
            Text(app.lastError ?? "")
        }
    }
}
