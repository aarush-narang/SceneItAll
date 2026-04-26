import SwiftUI
import Combine

final class AppRootViewModel: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("hasCompletedStyleQuiz") var hasCompletedStyleQuiz = false

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
        withAnimation {
            hasCompletedStyleQuiz = true
        }
    }
}
