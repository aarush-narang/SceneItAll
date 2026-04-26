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
        .overlay {
            if rootViewModel.isSavingStyleQuiz {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    ProgressView("Saving your preferences...")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .alert("Couldn't Save Preferences", isPresented: $rootViewModel.isShowingStyleQuizSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rootViewModel.styleQuizSaveErrorMessage)
        }
    }
}
