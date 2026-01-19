import SwiftUI

struct FlashcardsView: View {
    @EnvironmentObject var appState: AppState
    @State private var flashcards: [Flashcard] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 24) {
            if flashcards.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Flashcards")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Generate flashcards from your documents to study key concepts")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        generateFlashcards()
                    } label: {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating...")
                            }
                        } else {
                            Label("Generate Flashcards", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
                .padding(40)
            } else {
                // Flashcard view
                VStack(spacing: 16) {
                    // Progress
                    HStack {
                        Text("Card \(currentIndex + 1) of \(flashcards.count)")
                            .font(.headline)

                        Spacer()

                        Button {
                            flashcards.removeAll()
                            currentIndex = 0
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }

                    ProgressView(value: Double(currentIndex + 1), total: Double(flashcards.count))

                    // Card
                    FlashcardCard(
                        flashcard: flashcards[currentIndex],
                        showAnswer: $showAnswer
                    )

                    // Navigation
                    HStack(spacing: 16) {
                        Button {
                            if currentIndex > 0 {
                                currentIndex -= 1
                                showAnswer = false
                            }
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                        }
                        .disabled(currentIndex == 0)

                        Spacer()

                        Button {
                            showAnswer.toggle()
                        } label: {
                            Text(showAnswer ? "Hide Answer" : "Show Answer")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button {
                            if currentIndex < flashcards.count - 1 {
                                currentIndex += 1
                                showAnswer = false
                            }
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                        }
                        .disabled(currentIndex == flashcards.count - 1)
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Flashcards")
    }

    func generateFlashcards() {
        isGenerating = true

        Task {
            // Generate flashcards from chunks
            // This would call the chat service to generate Q&A pairs
            do {
                let generated = try await appState.chatService?.generateFlashcards(count: 10) ?? []
                flashcards = generated
            } catch {
                print("Error generating flashcards: \(error)")
            }
            isGenerating = false
        }
    }
}

struct Flashcard: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let source: String
}

struct FlashcardCard: View {
    let flashcard: Flashcard
    @Binding var showAnswer: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Question
            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(flashcard.question)
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showAnswer {
                Divider()

                // Answer
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(flashcard.answer)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Source
                HStack {
                    Image(systemName: "doc.text")
                    Text(flashcard.source)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: 600, minHeight: 200)
        .background(Color(.systemGray).opacity(0.1))
        .cornerRadius(16)
        .onTapGesture {
            withAnimation {
                showAnswer.toggle()
            }
        }
    }
}
