import SwiftUI

struct ContentView: View {
    @StateObject private var rootViewModel = AppRootViewModel()

    var body: some View {
        Group {
            if !rootViewModel.hasCompletedOnboarding {
                AppOnboardingView {
                    rootViewModel.completeOnboarding()
                }
                .transition(.opacity)
            } else if !rootViewModel.hasCompletedStyleQuiz {
                StyleQuizView { result in
                    rootViewModel.completeStyleQuiz(with: result)
                }
                .transition(.move(edge: .trailing))
            } else {
                DesignsListView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: rootViewModel.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: rootViewModel.hasCompletedStyleQuiz)
    }
}
