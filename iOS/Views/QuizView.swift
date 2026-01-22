import SwiftUI

struct QuizView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedQuizSet: QuizSet?
    @State private var currentQuestions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedAnswer: Int?
    @State private var hasAnswered = false
    @State private var score = 0
    @State private var quizComplete = false

    var body: some View {
        NavigationStack {
            Group {
                if currentQuestions.isEmpty {
                    quizSelectionView
                } else if quizComplete {
                    resultsView
                } else {
                    quizContentView
                }
            }
            .navigationTitle("Quiz")
        }
    }

    // MARK: - Quiz Selection

    var quizSelectionView: some View {
        Group {
            if appState.quizSets.isEmpty {
                emptyStateView
            } else {
                List(appState.quizSets) { quizSet in
                    QuizSetRow(quizSet: quizSet) {
                        startQuiz(quizSet)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Quizzes Available")
                .font(.title2)
                .fontWeight(.bold)

            Text("Generate quizzes on your Mac and they'll sync here automatically")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Quiz Content

    var quizContentView: some View {
        VStack(spacing: 16) {
            // Progress
            HStack {
                Text("Question \(currentIndex + 1) of \(currentQuestions.count)")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(score)")
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal)

            SwiftUI.ProgressView(value: Double(currentIndex + 1), total: Double(currentQuestions.count))
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Question
                    Text(currentQuestions[currentIndex].question)
                        .font(.title3)
                        .fontWeight(.medium)
                        .padding()

                    // Options
                    ForEach(0..<currentQuestions[currentIndex].options.count, id: \.self) { index in
                        OptionButton(
                            text: currentQuestions[currentIndex].options[index],
                            index: index,
                            selectedAnswer: selectedAnswer,
                            correctAnswer: currentQuestions[currentIndex].correctIndex,
                            hasAnswered: hasAnswered
                        ) {
                            if !hasAnswered {
                                selectAnswer(index)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Explanation
                    if hasAnswered && !currentQuestions[currentIndex].explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: selectedAnswer == currentQuestions[currentIndex].correctIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(selectedAnswer == currentQuestions[currentIndex].correctIndex ? .green : .red)
                                Text(selectedAnswer == currentQuestions[currentIndex].correctIndex ? "Correct!" : "Incorrect")
                                    .fontWeight(.medium)
                            }

                            Text(currentQuestions[currentIndex].explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
            }

            // Navigation
            HStack {
                if hasAnswered {
                    if currentIndex == currentQuestions.count - 1 {
                        Button("See Results") {
                            quizComplete = true
                            updateProgress()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Next Question") {
                            nextQuestion()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Exit") {
                    resetQuiz()
                }
            }
        }
    }

    // MARK: - Results

    var resultsView: some View {
        VStack(spacing: 24) {
            let percentage = Double(score) / Double(currentQuestions.count) * 100

            Image(systemName: percentage >= 70 ? "star.fill" : "star")
                .font(.system(size: 64))
                .foregroundStyle(percentage >= 70 ? .yellow : .secondary)

            Text("Quiz Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("\(score) out of \(currentQuestions.count)")
                .font(.title2)

            Text(String(format: "%.0f%%", percentage))
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(percentage >= 70 ? .green : percentage >= 50 ? .orange : .red)

            Button("Done") {
                resetQuiz()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    func startQuiz(_ quizSet: QuizSet) {
        selectedQuizSet = quizSet
        currentQuestions = quizSet.questions.shuffled()
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        hasAnswered = false
        quizComplete = false
    }

    func selectAnswer(_ index: Int) {
        selectedAnswer = index
        hasAnswered = true
        currentQuestions[currentIndex].userAnswer = index

        if index == currentQuestions[currentIndex].correctIndex {
            score += 1
        }
    }

    func nextQuestion() {
        currentIndex += 1
        selectedAnswer = nil
        hasAnswered = false
    }

    func resetQuiz() {
        currentQuestions = []
        selectedQuizSet = nil
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        hasAnswered = false
        quizComplete = false
    }

    func updateProgress() {
        appState.progress.quizzesTaken += 1
        appState.progress.totalScore += score
        appState.progress.totalQuestions += currentQuestions.count
        appState.progress.lastStudied = Date()
        appState.saveProgress()
    }
}

// MARK: - Supporting Views

struct QuizSetRow: View {
    let quizSet: QuizSet
    let onStart: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(quizSet.name)
                    .font(.headline)
                HStack {
                    Text(quizSet.difficulty.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(difficultyColor.opacity(0.2))
                        .foregroundStyle(difficultyColor)
                        .cornerRadius(8)

                    Text("\(quizSet.questions.count) questions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Start", action: onStart)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    var difficultyColor: Color {
        switch quizSet.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

struct OptionButton: View {
    let text: String
    let index: Int
    let selectedAnswer: Int?
    let correctAnswer: Int
    let hasAnswered: Bool
    let action: () -> Void

    var backgroundColor: Color {
        if !hasAnswered {
            return selectedAnswer == index ? Color.accentColor.opacity(0.2) : Color(.systemGray6)
        } else {
            if index == correctAnswer {
                return Color.green.opacity(0.2)
            } else if index == selectedAnswer {
                return Color.red.opacity(0.2)
            }
            return Color(.systemGray6)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(["A", "B", "C", "D"][index])
                    .fontWeight(.bold)
                    .frame(width: 30)

                Text(text)
                    .multilineTextAlignment(.leading)

                Spacer()

                if hasAnswered {
                    if index == correctAnswer {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if index == selectedAnswer {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
    }
}

#Preview {
    QuizView()
        .environmentObject(AppState())
}
