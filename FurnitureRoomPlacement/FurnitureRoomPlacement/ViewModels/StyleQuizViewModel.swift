import SwiftUI
import Combine

struct StyleQuizResult {
    let styleTags: [String]
    let colorPalette: [String]
    let materialPreferences: [String]
    let spatialDensity: String
    let philosophies: [String]

    static let `default` = StyleQuizResult(
        styleTags: ["modern"],
        colorPalette: ["White", "Gray"],
        materialPreferences: ["Wood"],
        spatialDensity: "balanced",
        philosophies: []
    )
}

final class StyleQuizViewModel: ObservableObject {
    @Published var step = 0
    @Published var selectedStyles: Set<String> = []
    @Published var selectedColors: Set<String> = []
    @Published var selectedMaterials: Set<String> = []
    @Published var selectedDensity = "balanced"
    @Published var philosophy = ""

    let totalSteps = 5

    var progress: CGFloat {
        CGFloat(step + 1) / CGFloat(totalSteps)
    }

    var canGoBack: Bool { step > 0 }
    var isLastStep: Bool { step == totalSteps - 1 }

    func advance() {
        guard step < totalSteps - 1 else { return }
        withAnimation { step += 1 }
    }

    func goBack() {
        guard step > 0 else { return }
        withAnimation { step -= 1 }
    }

    func toggleStyle(_ style: String) { toggle(style, in: &selectedStyles) }
    func toggleColor(_ color: String) { toggle(color, in: &selectedColors) }
    func toggleMaterial(_ material: String) { toggle(material, in: &selectedMaterials) }

    func buildResult() -> StyleQuizResult {
        StyleQuizResult(
            styleTags: Array(selectedStyles),
            colorPalette: Array(selectedColors),
            materialPreferences: Array(selectedMaterials),
            spatialDensity: selectedDensity,
            philosophies: philosophy.isEmpty ? [] : [philosophy]
        )
    }

    private func toggle(_ item: String, in set: inout Set<String>) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }

    static let allStyles = [
        "Modern", "Minimalist", "Mid-Century", "Scandinavian", "Industrial",
        "Bohemian", "Coastal", "Japanese", "Rustic", "Art Deco",
    ]

    static let allColors: [(name: String, color: Color)] = [
        ("White", .white), ("Black", .black), ("Gray", .gray),
        ("Beige", Color(red: 0.96, green: 0.93, blue: 0.87)),
        ("Navy", Color(red: 0.15, green: 0.2, blue: 0.4)),
        ("Forest", Color(red: 0.2, green: 0.4, blue: 0.3)),
        ("Terracotta", Color(red: 0.8, green: 0.45, blue: 0.35)),
        ("Dusty Rose", Color(red: 0.85, green: 0.6, blue: 0.65)),
    ]

    static let allMaterials = [
        "Wood", "Metal", "Fabric", "Leather", "Glass",
        "Stone", "Rattan", "Velvet", "Concrete",
    ]

    static let allDensities: [(id: String, icon: String, description: String)] = [
        ("sparse", "square.dashed", "Open and airy — essentials only"),
        ("balanced", "square.grid.2x2", "Well-furnished, not crowded"),
        ("dense", "square.grid.3x3", "Maximalist — richly filled"),
    ]
}
