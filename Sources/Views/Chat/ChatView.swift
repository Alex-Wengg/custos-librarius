import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(appState.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if appState.isGenerating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.messages.count) { _, _ in
                    if let last = appState.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Ask a question about your documents...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isInputFocused = true
                        }
                    }
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || appState.isGenerating)
            }
            .padding()
            .background(.background)
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.messages.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(appState.messages.isEmpty)
            }

            ToolbarItem {
                if !appState.modelLoaded {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMessage = ChatMessage(
            role: .user,
            content: inputText,
            timestamp: Date()
        )
        appState.messages.append(userMessage)

        let query = inputText
        inputText = ""

        Task {
            await generateResponse(for: query)
        }
    }

    @MainActor
    func generateResponse(for query: String) async {
        appState.isGenerating = true

        do {
            // Make sure model is loaded
            if appState.chatService == nil {
                guard let project = appState.currentProject else {
                    throw ServiceError.projectNotFound
                }
                appState.chatService = ChatService(projectPath: project.path)
            }

            if !appState.modelLoaded {
                let loadingMessage = ChatMessage(
                    role: .assistant,
                    content: "Loading AI model... (this may take a minute)",
                    timestamp: Date()
                )
                appState.messages.append(loadingMessage)

                try await appState.chatService?.loadModel()
                appState.modelLoaded = true

                // Remove loading message
                appState.messages.removeLast()
            }

            // Generate response (skip search if no index)
            let response = try await appState.chatService?.generate(
                query: query,
                context: []
            ) ?? "No response"

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response,
                timestamp: Date()
            )
            appState.messages.append(assistantMessage)
        } catch {
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Error: \(error)",
                timestamp: Date()
            )
            appState.messages.append(errorMessage)
        }

        appState.isGenerating = false
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor : Color(.systemGray).opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}
