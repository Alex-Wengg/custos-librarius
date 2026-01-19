import SwiftUI
import AppKit

struct QuizView: View {
    @EnvironmentObject var appState: AppState
    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var hasAnswered = false
    @State private var score = 0
    @State private var isGenerating = false
    @State private var quizComplete = false
    @State private var showReview = false

    // Settings
    @State private var questionCount = 5
    @State private var difficulty: QuizDifficulty = .medium
    @State private var selectedSources: Set<String> = []
    @State private var availableSources: [String] = []
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if questions.isEmpty && !isGenerating {
                quizSetup
            } else if isGenerating {
                generatingView
            } else if showReview {
                reviewView
            } else if quizComplete {
                resultsView
            } else {
                quizContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Quiz")
        .onAppear {
            loadSources()
        }
    }

    // MARK: - Quiz Setup

    var quizSetup: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Test Your Knowledge")
                    .font(.title)
                    .fontWeight(.bold)

                // Question Count
                GroupBox("Number of Questions") {
                    Picker("Questions", selection: $questionCount) {
                        Text("5 Questions").tag(5)
                        Text("10 Questions").tag(10)
                        Text("20 Questions").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                }

                // Difficulty
                GroupBox("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(QuizDifficulty.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                }

                // Topic Filter
                if !availableSources.isEmpty {
                    GroupBox("Topics (optional)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select specific documents to quiz on, or leave empty for all")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            FlowLayout(spacing: 8) {
                                ForEach(availableSources, id: \.self) { source in
                                    SourceChip(
                                        source: source,
                                        isSelected: selectedSources.contains(source)
                                    ) {
                                        if selectedSources.contains(source) {
                                            selectedSources.remove(source)
                                        } else {
                                            selectedSources.insert(source)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                Button {
                    generateQuiz()
                } label: {
                    Label("Start Quiz", systemImage: "play.fill")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: 500)
        }
    }

    var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Generating quiz questions...")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Quiz Content

    var quizContent: some View {
        VStack(spacing: 16) {
            // Progress bar
            HStack {
                Text("Question \(currentIndex + 1) of \(questions.count)")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("\(score)")
                        .fontWeight(.bold)
                }
            }

            ProgressView(value: Double(currentIndex + 1), total: Double(questions.count))

            // Difficulty badge
            HStack {
                Text(difficulty.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyColor.opacity(0.2))
                    .foregroundColor(difficultyColor)
                    .cornerRadius(8)

                Spacer()

                Text(questions[currentIndex].source)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Question Card
            VStack(alignment: .leading, spacing: 16) {
                Text(questions[currentIndex].question)
                    .font(.title3)
                    .fontWeight(.medium)

                // Options
                ForEach(0..<questions[currentIndex].options.count, id: \.self) { index in
                    QuizOptionButton(
                        text: questions[currentIndex].options[index],
                        index: index,
                        selectedAnswer: selectedAnswer,
                        correctAnswer: questions[currentIndex].correctIndex,
                        hasAnswered: hasAnswered
                    ) {
                        if !hasAnswered {
                            selectAnswer(index)
                        }
                    }
                }

                // Explanation (shown after answering)
                if hasAnswered && !questions[currentIndex].explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()

                        HStack {
                            Image(systemName: selectedAnswer == questions[currentIndex].correctIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(selectedAnswer == questions[currentIndex].correctIndex ? .green : .red)
                            Text(selectedAnswer == questions[currentIndex].correctIndex ? "Correct!" : "Incorrect")
                                .fontWeight(.medium)
                        }

                        Text(questions[currentIndex].explanation)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color(.systemGray).opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(24)
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(16)

            Spacer()

            // Navigation
            HStack {
                if currentIndex > 0 {
                    Button {
                        currentIndex -= 1
                        selectedAnswer = questions[currentIndex].userAnswer
                        hasAnswered = questions[currentIndex].userAnswer != nil
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                }

                Spacer()

                if hasAnswered {
                    if currentIndex == questions.count - 1 {
                        Button("See Results") {
                            quizComplete = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            currentIndex += 1
                            selectedAnswer = questions[currentIndex].userAnswer
                            hasAnswered = questions[currentIndex].userAnswer != nil
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 700)
    }

    // MARK: - Results View

    var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                let percentage = Double(score) / Double(questions.count) * 100
                let missedQuestions = questions.filter { $0.userAnswer != $0.correctIndex }

                Image(systemName: percentage >= 70 ? "star.fill" : "star")
                    .font(.system(size: 64))
                    .foregroundColor(percentage >= 70 ? .yellow : .secondary)

                Text("Quiz Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\(score) out of \(questions.count)")
                    .font(.title2)

                Text(String(format: "%.0f%%", percentage))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(percentage >= 70 ? .green : percentage >= 50 ? .orange : .red)

                // Stats
                HStack(spacing: 32) {
                    VStack {
                        Text("\(score)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Correct")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(questions.count - score)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Text("Incorrect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text(difficulty.rawValue)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Difficulty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray).opacity(0.1))
                .cornerRadius(12)

                // Action buttons
                HStack(spacing: 16) {
                    if !missedQuestions.isEmpty {
                        Button {
                            showReview = true
                        } label: {
                            Label("Review Missed (\(missedQuestions.count))", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        exportToPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        resetQuiz()
                    } label: {
                        Label("New Quiz", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
        }
    }

    // MARK: - Review View

    var reviewView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showReview = false
                } label: {
                    Label("Back to Results", systemImage: "chevron.left")
                }
                Spacer()
                Text("Review Missed Questions")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 16) {
                    let missedQuestions = questions.filter { $0.userAnswer != $0.correctIndex }

                    ForEach(Array(missedQuestions.enumerated()), id: \.element.id) { index, question in
                        ReviewCard(question: question, number: index + 1)
                    }
                }
                .padding()
            }
        }
    }

    var difficultyColor: Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }

    // MARK: - Functions

    func loadSources() {
        do {
            availableSources = try appState.chatService?.getAvailableSources() ?? []
        } catch {
            print("Error loading sources: \(error)")
        }
    }

    func selectAnswer(_ index: Int) {
        selectedAnswer = index
        hasAnswered = true
        questions[currentIndex].userAnswer = index

        if index == questions[currentIndex].correctIndex {
            score += 1
        }
    }

    func generateQuiz() {
        isGenerating = true

        Task { @MainActor in
            do {
                let sources = selectedSources.isEmpty ? nil : Array(selectedSources)
                let generated = try await appState.chatService?.generateQuiz(
                    count: questionCount,
                    difficulty: difficulty,
                    sources: sources
                ) ?? []
                questions = generated
                currentIndex = 0
                score = 0
                selectedAnswer = nil
                hasAnswered = false
                quizComplete = false
                showReview = false
            } catch {
                print("Error generating quiz: \(error)")
            }
            isGenerating = false
        }
    }

    func resetQuiz() {
        questions = []
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        hasAnswered = false
        quizComplete = false
        showReview = false
    }

    func exportToPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Quiz_\(difficulty.rawValue)_\(Date().formatted(date: .numeric, time: .omitted)).pdf"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            createPDF(at: url)
        }
    }

    func createPDF(at url: URL) {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)

        var yPosition: CGFloat = 50
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - (margin * 2)

        func newPageIfNeeded(_ height: CGFloat) {
            if yPosition + height > pageRect.height - 50 {
                UIGraphicsEndPDFPage()
                UIGraphicsBeginPDFPage()
                yPosition = 50
            }
        }

        // Title page
        UIGraphicsBeginPDFPage()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        let title = "Quiz Results - \(difficulty.rawValue)"
        title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttrs)
        yPosition += 40

        let scoreText = "Score: \(score)/\(questions.count) (\(Int(Double(score)/Double(questions.count)*100))%)"
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.darkGray
        ]
        scoreText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: scoreAttrs)
        yPosition += 50

        // Questions
        let questionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        let optionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray
        ]
        let correctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemGreen
        ]
        let wrongAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemRed
        ]

        for (i, question) in questions.enumerated() {
            newPageIfNeeded(150)

            let qText = "\(i + 1). \(question.question)"
            qText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: questionAttrs)
            yPosition += 25

            for (j, option) in question.options.enumerated() {
                let prefix = ["A", "B", "C", "D"][j]
                let isCorrect = j == question.correctIndex
                let wasSelected = j == question.userAnswer
                let attrs = isCorrect ? correctAttrs : (wasSelected ? wrongAttrs : optionAttrs)
                let marker = isCorrect ? " ✓" : (wasSelected ? " ✗" : "")

                let optText = "   \(prefix). \(option)\(marker)"
                optText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: attrs)
                yPosition += 18
            }

            yPosition += 15
        }

        UIGraphicsEndPDFContext()

        do {
            try pdfData.write(to: url)
        } catch {
            print("Error saving PDF: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct QuizOptionButton: View {
    let text: String
    let index: Int
    let selectedAnswer: Int?
    let correctAnswer: Int
    let hasAnswered: Bool
    let action: () -> Void

    var backgroundColor: Color {
        if !hasAnswered {
            return selectedAnswer == index ? Color.accentColor.opacity(0.2) : Color(.systemGray).opacity(0.1)
        } else {
            if index == correctAnswer {
                return Color.green.opacity(0.2)
            } else if index == selectedAnswer {
                return Color.red.opacity(0.2)
            }
            return Color(.systemGray).opacity(0.1)
        }
    }

    var borderColor: Color {
        if !hasAnswered {
            return selectedAnswer == index ? Color.accentColor : Color.clear
        } else {
            if index == correctAnswer {
                return Color.green
            } else if index == selectedAnswer {
                return Color.red
            }
            return Color.clear
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
                            .foregroundColor(.green)
                    } else if index == selectedAnswer {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
    }
}

struct ReviewCard: View {
    let question: QuizQuestion
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Question \(number)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(question.source)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(question.question)
                .font(.headline)

            ForEach(0..<question.options.count, id: \.self) { i in
                HStack {
                    Text(["A", "B", "C", "D"][i])
                        .fontWeight(.bold)
                        .frame(width: 24)

                    Text(question.options[i])

                    Spacer()

                    if i == question.correctIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if i == question.userAnswer {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(
                    i == question.correctIndex ? Color.green.opacity(0.1) :
                    i == question.userAnswer ? Color.red.opacity(0.1) :
                    Color.clear
                )
                .cornerRadius(8)
            }

            if !question.explanation.isEmpty {
                Text(question.explanation)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray).opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.05))
        .cornerRadius(12)
    }
}

struct SourceChip: View {
    let source: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(source)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray).opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// UIGraphics compatibility for macOS
#if os(macOS)
func UIGraphicsBeginPDFContextToData(_ data: NSMutableData, _ bounds: CGRect, _ documentInfo: [String: Any]?) {
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: nil, nil)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
}

func UIGraphicsBeginPDFPage() {
    NSGraphicsContext.current?.cgContext.beginPDFPage(nil)
}

func UIGraphicsEndPDFPage() {
    NSGraphicsContext.current?.cgContext.endPDFPage()
}

func UIGraphicsEndPDFContext() {
    NSGraphicsContext.current?.cgContext.closePDF()
}
#endif
