import SwiftUI

struct AppOnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("cube.transparent", "Design Your Space", "Scan any room with LiDAR and reimagine it with real furniture from our catalog.", .blue),
        ("camera.viewfinder", "Scan in Seconds", "Walk around your room and let RoomPlan capture every wall, window, and door.", .green),
        ("sparkles", "AI-Powered Styling", "Ask our assistant for suggestions — it knows your style and thousands of pieces.", .purple),
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(pages[currentPage].color.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(pages[currentPage].color)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.bottom, 40)

                Text(pages[currentPage].title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .id("title-\(currentPage)")
                    .transition(.push(from: .trailing))

                Text(pages[currentPage].subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                    .id("subtitle-\(currentPage)")
                    .transition(.push(from: .trailing))

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? pages[currentPage].color : Color(.tertiaryLabel))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.3), value: currentPage)
                .padding(.bottom, 20)

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentPage += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)

                if currentPage < pages.count - 1 {
                    Button("Skip") { onComplete() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 20)
            }
        }
    }
}
