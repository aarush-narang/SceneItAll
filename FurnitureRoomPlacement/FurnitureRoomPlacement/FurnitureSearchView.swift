import SwiftUI

struct FurnitureSearchView: View {
    let onFurnitureSelected: (Furniture) -> Void
    let onError: (String) -> Void

    private struct ColorShortcut: Identifiable {
        let name: String
        let swatch: Color

        var id: String { name }
    }

    @State private var query = ""
    @State private var maxPriceText = ""
    @State private var limitText = "10"
    @State private var results: [Furniture] = []
    @State private var isLoading = false
    @State private var selectedCategory = "All"
    @State private var selectedColorName: String?

    private let categories = ["All", "Seating", "Tables", "Storage", "Lighting", "Decor"]
    private let colorShortcuts: [ColorShortcut] = [
        ColorShortcut(name: "Black", swatch: .black),
        ColorShortcut(name: "White", swatch: .white),
        ColorShortcut(name: "Gray", swatch: .gray),
        ColorShortcut(name: "Brown", swatch: .brown),
        ColorShortcut(name: "Beige", swatch: Color(red: 0.87, green: 0.80, blue: 0.68)),
        ColorShortcut(name: "Red", swatch: .red),
        ColorShortcut(name: "Orange", swatch: .orange),
        ColorShortcut(name: "Yellow", swatch: .yellow),
        ColorShortcut(name: "Blue", swatch: .blue),
        ColorShortcut(name: "Green", swatch: .green)
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchHeader
                resultsList
            }

            if isLoading {
                Color.black.opacity(0.12).ignoresSafeArea()
                ProgressView("Searching...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)

                    TextField("Search furniture...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                TextField("Max $", text: $maxPriceText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 92)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: maxPriceText) { _, newValue in
                        maxPriceText = newValue.filter(\.isNumber)
                    }
            }

            HStack(spacing: 0) {
                ForEach(colorShortcuts) { color in
                    Button {
                        selectedColorName = selectedColorName == color.name ? nil : color.name
                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Task { await search() }
                        }
                    } label: {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        selectedColorName == color.name ? Color.accentColor : Color.secondary.opacity(color.name == "White" ? 0.55 : 0.2),
                                        lineWidth: selectedColorName == color.name ? 3 : 1
                                    )
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color.name) furniture")
                }
            }
            .padding(.vertical, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { category in
                        ChipButton(label: category, isSelected: selectedCategory == category) {
                            selectedCategory = category
                            if !query.isEmpty {
                                Task { await search() }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            if results.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Search Furniture",
                    systemImage: "magnifyingglass",
                    description: Text("Type a query and hit search to browse furniture.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(results) { furniture in
                    Button { onFurnitureSelected(furniture) } label: {
                        CatalogItemRow(furniture: furniture)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Search

    @MainActor
    private func search() async {
        guard !isLoading else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            onError("Please enter a search query.")
            return
        }
        let limit = Int(limitText) ?? 10

        isLoading = true
        defer { isLoading = false }

        do {
            let colorQueryPrefix = selectedColorName?.lowercased() ?? ""
            let baseQuery = selectedCategory == "All"
                ? trimmedQuery
                : "\(selectedCategory.lowercased()) \(trimmedQuery)"
            let searchQuery = [colorQueryPrefix, baseQuery]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let fetchedResults = try await FurnitureAPIClient.shared.searchFurniture(query: searchQuery, limit: limit)
            if let maxPrice = Double(maxPriceText), maxPrice > 0 {
                results = fetchedResults.filter { $0.price.value <= maxPrice }
            } else {
                results = fetchedResults
            }
        } catch {
            results = []
            onError(error.localizedDescription)
        }
    }
}

// MARK: - Catalog Item Row

private struct CatalogItemRow: View {
    let furniture: Furniture

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.08))
                Image(systemName: "sofa")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(furniture.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text("\(furniture.formattedPrice) \u{00B7} \(furniture.attributes.materialPrimary)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
