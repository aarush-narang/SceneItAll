import SwiftUI

struct ImportedRoomAssistantRequest {
    let prompt: String
    let sanitizedJSONString: String
}

struct ImportedRoomAssistantMessage: Identifiable, Equatable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
}

struct ImportedRoomAssistantOverlay: View {
    @Binding var isPresented: Bool
    @Binding var draft: String
    let messages: [ImportedRoomAssistantMessage]
    let isChatLoading: Bool
    let isCleanupLoading: Bool
    let hasPendingPlacementPreview: Bool
    let onSend: () -> Void
    let onPlacementCleanup: () -> Void
    let onAcceptPlacementChanges: () -> Void
    let onDeclinePlacementChanges: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if isPresented {
                    chatPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 12) {
                    assistantButton
                    cleanupButton
                }
            }
            Spacer(minLength: 0)

            if hasPendingPlacementPreview {
                placementDecisionPanel
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hasPendingPlacementPreview)
    }

    // MARK: - Agent Button

    private var assistantButton: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color(red: 0.204, green: 0.471, blue: 0.965), Color(red: 0.353, green: 0.784, blue: 0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: Color(red: 0.204, green: 0.471, blue: 0.965).opacity(0.35), radius: 16, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cleanup Button

    private var cleanupButton: some View {
        Button(action: onPlacementCleanup) {
            Group {
                if isCleanupLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 52, height: 52)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [Color.teal, Color.green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || hasPendingPlacementPreview)
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                    Text("Room Assistant")
                        .font(.system(size: 16, weight: .semibold))
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            AssistantBubble(message: message)
                        }
                        if isBusy {
                            LoadingBubble()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .onChange(of: messages) { _, updated in
                    guard let lastID = updated.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your room...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                    .disabled(isBusy)

                Button(action: onSend) {
                    Group {
                        if isChatLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isSendDisabled ? Color.gray.opacity(0.5) : Color.blue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSendDisabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: 340, minHeight: 340, maxHeight: 420)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
    }

    // MARK: - Placement Decision

    private var placementDecisionPanel: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button("Accept") { onAcceptPlacementChanges() }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.green, in: Capsule())
                .buttonStyle(.plain)

            Button("Decline") { onDeclinePlacementChanges() }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.red, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    // MARK: - Helpers

    private var isSendDisabled: Bool {
        isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBusy: Bool {
        isChatLoading || isCleanupLoading
    }
}

// MARK: - Chat Bubbles

private struct AssistantBubble: View {
    let message: ImportedRoomAssistantMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)
                bubble
            }
        }
        .id(message.id)
    }

    private var bubble: some View {
        Text(message.text)
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(message.role == .assistant ? Color.primary : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bubbleBackground: AnyShapeStyle {
        if message.role == .assistant {
            AnyShapeStyle(Color(.tertiarySystemFill))
        } else {
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.204, green: 0.471, blue: 0.965), Color(red: 0.353, green: 0.784, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

private struct LoadingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Working...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 32)
        }
    }
}
