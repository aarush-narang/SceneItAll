import SwiftUI

struct FurnitureSearchView: View {
    let onFurnitureSelected: (Furniture) -> Void
    let onError: (String) -> Void

    @State private var query = "black couch"
    @State private var limitText = "10"
    @State private var results: [Furniture] = []
    @State private var isLoading = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                searchControls

                List(results, id: \.id) { furniture in
                    Button {
                        onFurnitureSelected(furniture)
                    } label: {
                        FurnitureSearchResultRow(furniture: furniture)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .overlay {
                    if !isLoading && results.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Run a search to load furniture from the server.")
                        )
                    }
                }
            }

            if isLoading {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                ProgressView("Searching Furniture")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search query", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await search()
                    }
                }

            TextField("Limit", text: $limitText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            Button {
                Task {
                    await search()
                }
            } label: {
                Text("Search")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || trimmedQuery.isEmpty || parsedLimit == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @MainActor
    private func search() async {
        guard !isLoading else {
            return
        }

        guard let limit = parsedLimit else {
            onError("Please enter a valid numeric limit.")
            return
        }

        guard !trimmedQuery.isEmpty else {
            onError("Please enter a search query.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            results = try await FurnitureAPIClient.shared.searchFurniture(
                query: trimmedQuery,
                limit: limit
            )
        } catch {
            results = []
            onError(error.localizedDescription)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedLimit: Int? {
        guard let value = Int(limitText), value > 0 else {
            return nil
        }
        return value
    }
}

private struct FurnitureSearchResultRow: View {
    let furniture: Furniture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(furniture.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(furniture.designSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text(furniture.formattedPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(furniture.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                ResultBadge(text: furniture.taxonomyInferred.category)
                ResultBadge(text: furniture.attributes.materialPrimary)
                ResultBadge(text: furniture.attributes.colorPrimary)
            }

            Text("Tap to open full details")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct ResultBadge: View {
    let text: String

    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }
}
