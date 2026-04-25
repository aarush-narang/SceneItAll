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
                        Text(furniture.name)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
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
