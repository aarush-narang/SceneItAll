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
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPresented {
                chatPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                assistantButton
                Spacer(minLength: 0)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPresented)
        .padding(.leading, 16)
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

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(maxWidth: 340, minHeight: 340, maxHeight: 680)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
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
