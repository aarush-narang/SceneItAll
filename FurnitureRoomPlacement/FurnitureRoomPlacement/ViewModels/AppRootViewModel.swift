import SwiftUI
import Combine

final class AppRootViewModel: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("hasCompletedStyleQuiz") var hasCompletedStyleQuiz = false
    @Published var isSavingStyleQuiz = false
    @Published var styleQuizSaveErrorMessage = ""
    @Published var isShowingStyleQuizSaveError = false

    func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }

    func completeStyleQuiz(with result: StyleQuizResult) {
        UserDefaults.standard.set(result.styleTags, forKey: "pref_styleTags")
        UserDefaults.standard.set(result.colorPalette, forKey: "pref_colorPalette")
        UserDefaults.standard.set(result.materialPreferences, forKey: "pref_materials")
        UserDefaults.standard.set(result.spatialDensity, forKey: "pref_density")
        UserDefaults.standard.set(result.philosophies, forKey: "pref_philosophies")

        Task {
            await MainActor.run {
                isSavingStyleQuiz = true
                isShowingStyleQuizSaveError = false
                styleQuizSaveErrorMessage = ""
            }

            let preferences = PreferenceProfileUpsert(
                styleTags: result.styleTags,
                colorPalette: result.colorPalette,
                materialPreferences: result.materialPreferences,
                spatialDensity: result.spatialDensity,
                philosophies: result.philosophies,
                hardRequirements: [:]
            )

            do {
                try await FurnitureAPIClient.shared.upsertPreferences(
                    preferences,
                    userID: UserSession.shared.userID
                )
                await MainActor.run {
                    isSavingStyleQuiz = false
                    withAnimation {
                        hasCompletedStyleQuiz = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingStyleQuiz = false
                    styleQuizSaveErrorMessage = error.localizedDescription
                    isShowingStyleQuizSaveError = true
                }
            }
        }
    }
}
