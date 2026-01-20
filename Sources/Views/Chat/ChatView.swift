import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if appState.messages.isEmpty {
                            EmptyStateView()
                                .padding(.top, 100)
                        } else {
                            ForEach(appState.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if appState.isGenerating {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading)
                            .padding(.top, 8)
                        }
                        
                        Color.clear
                            .frame(height: 80) // Spacer for input bar
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

            // Input
            VStack(spacing: 0) {
                Divider()
                    .opacity(0) // Hide default divider, we'll use shadow or background
                
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask a question about your documents...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isInputFocused ? Theme.copper : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
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
                            .font(.system(size: 32))
                            .foregroundStyle(inputText.isEmpty || appState.isGenerating ? Color.secondary.opacity(0.5) : Theme.copper)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || appState.isGenerating)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
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
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Theme.copper)
                        .help("Model Loaded")
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

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Theme.copper.opacity(0.8))
            Text("Start a conversation")
                .font(Theme.headerFont)
            Text("Ask questions about your documents and get AI-powered answers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.copper.gradient)
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user ?
                        Theme.bubbleUser.opacity(0.9) :
                        Theme.bubbleAssistant
                    )
                    .background(
                         message.role == .user ? AnyShapeStyle(Theme.bubbleUser) : AnyShapeStyle(.thinMaterial)
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: message.role == .user ? 18 : 0,
                            bottomTrailingRadius: message.role == .user ? 0 : 18,
                            topTrailingRadius: 18
                        )
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: message.role == .user ? 18 : 0,
                            bottomTrailingRadius: message.role == .user ? 0 : 18,
                            topTrailingRadius: 18
                        )
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.navy)
            } else {
                Spacer()
            }
        }
    }
}
