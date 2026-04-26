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
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var assistantButton: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPresented ? "Close room assistant" : "Open room assistant")
    }

    private var cleanupButton: some View {
        Button(action: onPlacementCleanup) {
            Group {
                if isCleanupLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(
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
        .accessibilityLabel("Suggest better furniture placement")
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Room Assistant", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            ImportedRoomAssistantBubble(message: message)
                        }

                        if isBusy {
                            ImportedRoomAssistantLoadingBubble()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .background(Color.clear)
                .onChange(of: messages) { _, updatedMessages in
                    guard let lastMessageID = updatedMessages.last?.id else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessageID, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Design your dream blueprint.", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .disabled(isBusy)

                Button(action: onSend) {
                    Group {
                        if isChatLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(sendButtonColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSendDisabled)
            }
            .padding(16)
        }
        .frame(maxWidth: 340, minHeight: 340, maxHeight: 720)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private var isSendDisabled: Bool {
        isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonColor: Color {
        isSendDisabled ? .gray : .blue
    }

    private var isBusy: Bool {
        isChatLoading || isCleanupLoading
    }

    private var placementDecisionPanel: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button("Accept") {
                onAcceptPlacementChanges()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.green, in: Capsule())
            .buttonStyle(.plain)

            Button("Decline") {
                onDeclinePlacementChanges()
            }
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
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }
}

private struct ImportedRoomAssistantBubble: View {
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
            .font(.subheadline)
            .foregroundStyle(message.role == .assistant ? Color.primary : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bubbleBackground: AnyShapeStyle {
        if message.role == .assistant {
            AnyShapeStyle(Color(.secondarySystemBackground))
        } else {
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue, Color.cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

private struct ImportedRoomAssistantLoadingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Working...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 32)
        }
    }
}
