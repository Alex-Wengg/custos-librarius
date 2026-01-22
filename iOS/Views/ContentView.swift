import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            SearchView()
                .tabItem {
                    Label(Tab.search.rawValue, systemImage: Tab.search.icon)
                }
                .tag(Tab.search)

            QuizView()
                .tabItem {
                    Label(Tab.quiz.rawValue, systemImage: Tab.quiz.icon)
                }
                .tag(Tab.quiz)

            FlashcardsView()
                .tabItem {
                    Label(Tab.flashcards.rawValue, systemImage: Tab.flashcards.icon)
                }
                .tag(Tab.flashcards)

            StudyProgressView()
                .tabItem {
                    Label(Tab.progress.rawValue, systemImage: Tab.progress.icon)
                }
                .tag(Tab.progress)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
