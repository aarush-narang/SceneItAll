import SwiftUI

struct StyleQuizView: View {
    @StateObject private var viewModel: StyleQuizViewModel
    let showsSkipButton: Bool
    let onComplete: (StyleQuizResult) -> Void

    init(
        initialResult: StyleQuizResult = .default,
        showsSkipButton: Bool = true,
        onComplete: @escaping (StyleQuizResult) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: StyleQuizViewModel(initialResult: initialResult))
        self.showsSkipButton = showsSkipButton
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch viewModel.step {
                        case 0: styleTagsStep
                        case 1: colorStep
                        case 2: materialStep
                        case 3: densityStep
                        case 4: philosophyStep
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.step)
                }

                navigationButtons
            }
            .navigationTitle("Your Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsSkipButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { onComplete(.default) }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill)).frame(height: 4)
                Capsule().fill(Color.black)
                    .frame(width: geo.size.width * viewModel.progress, height: 4)
                    .animation(.spring(response: 0.35), value: viewModel.step)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if viewModel.canGoBack {
                Button { viewModel.goBack() } label: {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                if viewModel.isLastStep {
                    onComplete(viewModel.buildResult())
                } else {
                    viewModel.advance()
                }
            } label: {
                Text(viewModel.isLastStep ? "Finish" : "Next")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Steps

    private var styleTagsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's your style?")
                .font(.system(size: 22, weight: .bold))
            Text("Pick all that resonate.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(StyleQuizViewModel.allStyles, id: \.self) { style in
                    ChipButton(label: style, isSelected: viewModel.selectedStyles.contains(style), color: .blue) {
                        viewModel.toggleStyle(style)
                    }
                }
            }
        }
    }

    private var colorStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colors you love")
                .font(.system(size: 22, weight: .bold))
            Text("Select your palette.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(StyleQuizViewModel.allColors, id: \.name) { item in
                    ColorChipView(
                        name: item.name,
                        color: item.color,
                        isSelected: viewModel.selectedColors.contains(item.name)
                    ) {
                        viewModel.toggleColor(item.name)
                    }
                }
            }
        }
    }

    private var materialStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Materials")
                .font(.system(size: 22, weight: .bold))
            Text("What textures do you like?")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(StyleQuizViewModel.allMaterials, id: \.self) { material in
                    ChipButton(label: material, isSelected: viewModel.selectedMaterials.contains(material), color: .green) {
                        viewModel.toggleMaterial(material)
                    }
                }
            }
        }
    }

    private var densityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Room density")
                .font(.system(size: 22, weight: .bold))
            Text("How full should it feel?")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(StyleQuizViewModel.allDensities, id: \.id) { item in
                    DensityOptionView(
                        icon: item.icon,
                        title: item.id.capitalized,
                        subtitle: item.description,
                        isSelected: viewModel.selectedDensity == item.id
                    ) {
                        viewModel.selectedDensity = item.id
                    }
                }
            }
        }
    }

    private var philosophyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe your dream room")
                .font(.system(size: 22, weight: .bold))
            Text("A sentence or two the AI will follow as a guiding principle.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.philosophy)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if viewModel.philosophy.isEmpty {
                        Text("e.g. \"Cozy and warm, lots of natural wood, nothing too busy\"")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: - Shared Chip Button

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color(.secondarySystemBackground)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Chip

private struct ColorChipView: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle().stroke(isSelected ? Color.black : Color(.separator), lineWidth: isSelected ? 3 : 0.5)
                    )
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isLightColor ? .black : .white)
                        }
                    }
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var isLightColor: Bool {
        name == "White" || name == "Beige"
    }
}

// MARK: - Density Option

private struct DensityOptionView: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(isSelected ? .white : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(
                isSelected ? AnyShapeStyle(Color.black) : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}
