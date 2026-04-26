import SwiftUI

struct FurnitureSearchView: View {
    let onFurnitureSelected: (Furniture) -> Void
    let onError: (String) -> Void

    @State private var query = ""
    @State private var limitText = "10"
    @State private var results: [Furniture] = []
    @State private var isLoading = false
    @State private var selectedCategory = "All"

    private let categories = ["All", "Seating", "Tables", "Storage", "Lighting", "Decor"]

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
            let searchQuery = selectedCategory == "All"
                ? trimmedQuery
                : "\(selectedCategory.lowercased()) \(trimmedQuery)"
            results = try await FurnitureAPIClient.shared.searchFurniture(query: searchQuery, limit: limit)
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
