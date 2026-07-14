import SwiftUI
import DamSetCore

@main
struct DamSetApp: App {
    var body: some Scene {
        WindowGroup {
            RoutineListView(viewModel: WorkoutViewModel())
                .preferredColorScheme(.dark)
        }
    }
}

// iOS-only chrome guarded so the SwiftPM macOS shell target keeps compiling.
extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func workoutSessionCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}
