import SwiftUI

struct FlashcardsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSet: FlashcardSet?
    @State private var currentCards: [Flashcard] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var offset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if currentCards.isEmpty {
                    flashcardSelectionView
                } else {
                    flashcardStudyView
                }
            }
            .navigationTitle("Flashcards")
        }
    }

    // MARK: - Selection View

    var flashcardSelectionView: some View {
        Group {
            if appState.flashcardSets.isEmpty {
                emptyStateView
            } else {
                List(appState.flashcardSets) { flashcardSet in
                    FlashcardSetRow(flashcardSet: flashcardSet) {
                        startStudying(flashcardSet)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Flashcards Available")
                .font(.title2)
                .fontWeight(.bold)

            Text("Generate flashcards on your Mac and they'll sync here automatically")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Study View

    var flashcardStudyView: some View {
        VStack(spacing: 16) {
            // Progress
            HStack {
                Text("Card \(currentIndex + 1) of \(currentCards.count)")
                    .font(.headline)
                Spacer()
                Button {
                    resetStudy()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            SwiftUI.ProgressView(value: Double(currentIndex + 1), total: Double(currentCards.count))
                .padding(.horizontal)

            Spacer()

            // Card with swipe gesture
            FlashcardCardView(
                flashcard: currentCards[currentIndex],
                showAnswer: showAnswer
            )
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        offset = gesture.translation
                    }
                    .onEnded { gesture in
                        if abs(gesture.translation.width) > 100 {
                            // Swipe detected
                            withAnimation {
                                offset = CGSize(
                                    width: gesture.translation.width > 0 ? 500 : -500,
                                    height: 0
                                )
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                nextCard()
                            }
                        } else {
                            withAnimation {
                                offset = .zero
                            }
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.spring()) {
                    showAnswer.toggle()
                }
            }

            Spacer()

            // Instructions
            Text("Tap to flip • Swipe to continue")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Navigation buttons
            HStack(spacing: 32) {
                Button {
                    if currentIndex > 0 {
                        currentIndex -= 1
                        showAnswer = false
                        offset = .zero
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(currentIndex == 0)

                Button {
                    withAnimation(.spring()) {
                        showAnswer.toggle()
                    }
                } label: {
                    Image(systemName: showAnswer ? "eye.slash.circle.fill" : "eye.circle.fill")
                        .font(.system(size: 44))
                }

                Button {
                    nextCard()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(currentIndex == currentCards.count - 1)
            }
            .padding()
        }
    }

    // MARK: - Actions

    func startStudying(_ flashcardSet: FlashcardSet) {
        selectedSet = flashcardSet
        currentCards = flashcardSet.cards.shuffled()
        currentIndex = 0
        showAnswer = false
        offset = .zero
    }

    func nextCard() {
        if currentIndex < currentCards.count - 1 {
            currentIndex += 1
            showAnswer = false
            offset = .zero

            // Update progress
            appState.progress.flashcardsReviewed += 1
            appState.progress.lastStudied = Date()
            appState.saveProgress()
        }
    }

    func resetStudy() {
        currentCards = []
        selectedSet = nil
        currentIndex = 0
        showAnswer = false
        offset = .zero
    }
}

// MARK: - Supporting Views

struct FlashcardSetRow: View {
    let flashcardSet: FlashcardSet
    let onStart: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(flashcardSet.name)
                    .font(.headline)
                Text("\(flashcardSet.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Study", action: onStart)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct FlashcardCardView: View {
    let flashcard: Flashcard
    let showAnswer: Bool

    var body: some View {
        ZStack {
            // Back (Answer)
            cardContent(
                title: "Answer",
                text: flashcard.answer,
                showSource: true
            )
            .rotation3DEffect(
                .degrees(showAnswer ? 0 : 180),
                axis: (x: 0, y: 1, z: 0)
            )
            .opacity(showAnswer ? 1 : 0)

            // Front (Question)
            cardContent(
                title: "Question",
                text: flashcard.question,
                showSource: false
            )
            .rotation3DEffect(
                .degrees(showAnswer ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .opacity(showAnswer ? 0 : 1)
        }
        .animation(.spring(), value: showAnswer)
    }

    func cardContent(title: String, text: String, showSource: Bool) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(text)
                .font(.title3)
                .multilineTextAlignment(.center)

            Spacer()

            if showSource {
                HStack {
                    Image(systemName: "doc.text")
                    Text(flashcard.source)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 300, height: 400)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

#Preview {
    FlashcardsView()
        .environmentObject(AppState())
}
