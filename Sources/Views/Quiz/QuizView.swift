import SwiftUI
import AppKit

struct QuizView: View {
    @EnvironmentObject var appState: AppState

    // Multiple Choice State
    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var hasAnswered = false
    @State private var score = 0
    @State private var isGenerating = false
    @State private var quizComplete = false
    @State private var showReview = false

    // Open-Ended/Discussion State
    @State private var openEndedQuestions: [OpenEndedQuestion] = []
    @State private var currentMessage = ""
    @State private var isResponding = false

    // MCQ Discussion State
    @State private var mcqDiscussionMessage = ""
    @State private var isMCQDiscussing = false
    @State private var showMCQDiscussion = false

    // Settings
    @State private var quizType: QuizType = .multipleChoice
    @State private var questionCount = 5
    @State private var difficulty: QuizDifficulty = .medium
    @State private var selectedSources: Set<String> = []
    @State private var availableSources: [String] = []
    @State private var showSettings = false

    // Generation Progress
    @State private var generationProgress: QuizGenerationProgress?

    var body: some View {
        VStack(spacing: 0) {
            if (questions.isEmpty && openEndedQuestions.isEmpty) && !isGenerating {
                quizSetup
            } else if isGenerating {
                generatingView
            } else if showReview {
                reviewView
            } else if quizComplete {
                if quizType == .multipleChoice {
                    resultsView
                } else {
                    openEndedResultsView
                }
            } else {
                if quizType == .multipleChoice {
                    quizContent
                } else {
                    openEndedContent
                }
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

                // Quiz Type
                GroupBox("Quiz Type") {
                    Picker("Type", selection: $quizType) {
                        ForEach(QuizType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)

                    Text(quizType == .multipleChoice
                        ? "Select the correct answer from 4 options"
                        : "Discuss topics with AI - explore ideas through conversation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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
        VStack(spacing: 20) {
            if let progress = generationProgress {
                // Progress bar
                VStack(spacing: 12) {
                    ProgressView(value: progress.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)

                    Text(progress.displayText)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                // Animated indicator
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Please wait...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Preparing quiz...")
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
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

            // Scrollable Question Card
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(questions[currentIndex].question)
                        .font(.title3)
                        .fontWeight(.medium)
                        .textSelection(.enabled)

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
                                .textSelection(.enabled)
                                .padding()
                                .background(Color(.systemGray).opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    // Discussion Section (shown after answering)
                    if hasAnswered {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .padding(.top, 8)

                            // Toggle discussion
                            Button {
                                withAnimation {
                                    showMCQDiscussion.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                    Text(showMCQDiscussion ? "Hide Discussion" : "Ask a Question")
                                    if !questions[currentIndex].discussion.isEmpty {
                                        Text("(\(questions[currentIndex].discussion.count))")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: showMCQDiscussion ? "chevron.up" : "chevron.down")
                                }
                                .font(.callout)
                            }
                            .buttonStyle(.plain)

                            if showMCQDiscussion {
                                // Discussion messages
                                if !questions[currentIndex].discussion.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(questions[currentIndex].discussion) { message in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: message.isUser ? "person.circle.fill" : "brain")
                                                    .foregroundColor(message.isUser ? .blue : .purple)

                                                Text(message.content)
                                                    .font(.callout)
                                                    .textSelection(.enabled)
                                                    .padding(10)
                                                    .background(message.isUser ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                                                    .cornerRadius(12)
                                            }
                                            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }

                                // Input field
                                HStack(spacing: 8) {
                                    TextField("Ask about this question...", text: $mcqDiscussionMessage)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isMCQDiscussing)

                                    Button {
                                        sendMCQDiscussionMessage()
                                    } label: {
                                        if isMCQDiscussing {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(mcqDiscussionMessage.isEmpty || isMCQDiscussing)
                                }

                                // Suggested questions
                                if questions[currentIndex].discussion.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Suggested questions:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        ForEach(suggestedMCQQuestions, id: \.self) { suggestion in
                                            Button {
                                                mcqDiscussionMessage = suggestion
                                            } label: {
                                                Text(suggestion)
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .background(Color(.systemGray).opacity(0.1))
                .cornerRadius(16)
            }

            // Navigation
            HStack {
                if currentIndex > 0 {
                    Button {
                        currentIndex -= 1
                        selectedAnswer = questions[currentIndex].userAnswer
                        hasAnswered = questions[currentIndex].userAnswer != nil
                        showMCQDiscussion = false
                        mcqDiscussionMessage = ""
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                }

                Spacer()

                if hasAnswered {
                    if currentIndex == questions.count - 1 {
                        Button("See Results") {
                            quizComplete = true
                            showMCQDiscussion = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            currentIndex += 1
                            selectedAnswer = questions[currentIndex].userAnswer
                            hasAnswered = questions[currentIndex].userAnswer != nil
                            showMCQDiscussion = false
                            mcqDiscussionMessage = ""
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

    // MARK: - Discussion Content

    var openEndedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Topic \(currentIndex + 1) of \(openEndedQuestions.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(openEndedQuestions[currentIndex].source)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if openEndedQuestions[currentIndex].isComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Button {
                    markTopicComplete()
                } label: {
                    Text(openEndedQuestions[currentIndex].isComplete ? "Next Topic" : "Done with Topic")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemGray).opacity(0.05))

            Divider()

            // Discussion area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Topic question
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Discussion Topic", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption)
                                .foregroundColor(.accentColor)

                            Text(openEndedQuestions[currentIndex].question)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)

                        // Discussion messages
                        ForEach(openEndedQuestions[currentIndex].discussion) { message in
                            DiscussionBubble(message: message)
                        }

                        // Typing indicator
                        if isResponding {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: openEndedQuestions[currentIndex].discussion.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Share your thoughts...", text: $currentMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .disabled(currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
            }
            .padding()
        }
        .frame(maxWidth: 700)
    }

    // MARK: - Discussion Results

    var openEndedResultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                let completedCount = openEndedQuestions.filter { $0.isComplete }.count

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Discussion Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\(completedCount) of \(openEndedQuestions.count) topics explored")
                    .font(.title2)
                    .foregroundColor(.secondary)

                // Topics summary
                VStack(spacing: 12) {
                    ForEach(Array(openEndedQuestions.enumerated()), id: \.element.id) { index, question in
                        HStack {
                            Text("Topic \(index + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)

                            Text(question.question)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: question.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(question.isComplete ? .green : .secondary)

                            Text("\(question.discussion.count) messages")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray).opacity(0.1))
                .cornerRadius(12)

                Button {
                    resetQuiz()
                } label: {
                    Label("New Discussion", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
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
        Task {
            do {
                availableSources = try await appState.chatService?.getAvailableSources() ?? []
            } catch {
                print("Error loading sources: \(error)")
            }
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

    // MARK: - MCQ Discussion

    var suggestedMCQQuestions: [String] {
        let isCorrect = selectedAnswer == questions[currentIndex].correctIndex
        if isCorrect {
            return [
                "Why is this the correct answer?",
                "Can you explain this concept in more detail?",
                "What are related topics I should know?"
            ]
        } else {
            return [
                "Why was my answer wrong?",
                "Can you explain the correct answer?",
                "What should I study to understand this better?"
            ]
        }
    }

    func sendMCQDiscussionMessage() {
        guard currentIndex < questions.count else { return }
        let messageText = mcqDiscussionMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        // Add user message
        let userMessage = DiscussionMessage(content: messageText, isUser: true)
        questions[currentIndex].discussion.append(userMessage)
        mcqDiscussionMessage = ""

        isMCQDiscussing = true

        Task { @MainActor in
            do {
                let question = questions[currentIndex]
                let previousMessages = Array(question.discussion.dropLast()) // Exclude the message we just added

                let response = try await appState.chatService?.discussMCQ(
                    question: question,
                    userMessage: messageText,
                    previousMessages: previousMessages
                ) ?? "Sorry, I couldn't generate a response."

                let aiMessage = DiscussionMessage(content: response, isUser: false)
                questions[currentIndex].discussion.append(aiMessage)
            } catch {
                print("Error in MCQ discussion: \(error)")
                let errorMessage = DiscussionMessage(content: "Sorry, I encountered an error. Please try again.", isUser: false)
                questions[currentIndex].discussion.append(errorMessage)
            }

            isMCQDiscussing = false
        }
    }

    func generateQuiz() {
        isGenerating = true
        generationProgress = nil

        Task { @MainActor in
            do {
                let sources = selectedSources.isEmpty ? nil : Array(selectedSources)

                if quizType == .multipleChoice {
                    let generated = try await appState.chatService?.generateQuiz(
                        count: questionCount,
                        difficulty: difficulty,
                        sources: sources
                    ) { [self] progress in
                        Task { @MainActor in
                            self.generationProgress = progress
                        }
                    } ?? []
                    questions = generated
                    openEndedQuestions = []
                } else {
                    let generated = try await appState.chatService?.generateOpenEndedQuiz(
                        count: questionCount,
                        difficulty: difficulty,
                        sources: sources
                    ) { [self] progress in
                        Task { @MainActor in
                            self.generationProgress = progress
                        }
                    } ?? []
                    openEndedQuestions = generated
                    questions = []
                }

                currentIndex = 0
                score = 0
                selectedAnswer = nil
                hasAnswered = false
                quizComplete = false
                showReview = false
                currentMessage = ""
            } catch {
                print("Error generating quiz: \(error)")
            }
            isGenerating = false
            generationProgress = nil
        }
    }

    func resetQuiz() {
        questions = []
        openEndedQuestions = []
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        hasAnswered = false
        quizComplete = false
        showReview = false
        currentMessage = ""
        mcqDiscussionMessage = ""
        showMCQDiscussion = false
        isMCQDiscussing = false
    }

    func sendMessage() {
        guard currentIndex < openEndedQuestions.count else { return }
        let messageText = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        // Add user message
        let userMessage = DiscussionMessage(content: messageText, isUser: true)
        openEndedQuestions[currentIndex].discussion.append(userMessage)
        currentMessage = ""
        isResponding = true

        Task { @MainActor in
            do {
                let response = try await appState.chatService?.discussAnswer(
                    question: openEndedQuestions[currentIndex],
                    userAnswer: messageText,
                    previousMessages: Array(openEndedQuestions[currentIndex].discussion.dropLast())
                ) ?? "I'm having trouble responding. Please try again."

                let aiMessage = DiscussionMessage(content: response, isUser: false)
                openEndedQuestions[currentIndex].discussion.append(aiMessage)
            } catch {
                print("Error in discussion: \(error)")
                let errorMessage = DiscussionMessage(content: "Sorry, I encountered an error. Please try again.", isUser: false)
                openEndedQuestions[currentIndex].discussion.append(errorMessage)
            }
            isResponding = false
        }
    }

    func markTopicComplete() {
        openEndedQuestions[currentIndex].isComplete = true

        if currentIndex < openEndedQuestions.count - 1 {
            currentIndex += 1
            currentMessage = ""
        } else {
            quizComplete = true
        }
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
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792 // Letter size
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)

        // yFromTop tracks position from TOP of page (for our logic)
        // We convert to PDF coordinates (from bottom) when drawing
        var yFromTop: CGFloat = margin

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()

        // Helper to calculate text height
        func textHeight(_ text: String, attrs: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
            let attrString = NSAttributedString(string: text, attributes: attrs)
            let boundingRect = attrString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return ceil(boundingRect.height)
        }

        // Helper to draw wrapped text - converts from top-down to PDF bottom-up coordinates
        func drawWrappedText(_ text: String, yTop: CGFloat, attrs: [NSAttributedString.Key: Any], indent: CGFloat = 0) -> CGFloat {
            let width = contentWidth - indent
            let attrString = NSAttributedString(string: text, attributes: attrs)
            let boundingRect = attrString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let height = ceil(boundingRect.height)
            // Convert: PDF y = pageHeight - topY - textHeight
            let pdfY = pageHeight - yTop - height
            attrString.draw(in: CGRect(x: margin + indent, y: pdfY, width: width, height: height))
            return height
        }

        // Start a new page and reset position
        func newPage() {
            UIGraphicsEndPDFPage()
            UIGraphicsBeginPDFPage()
            yFromTop = margin
        }

        // Check if we need a new page
        func ensureSpace(_ neededHeight: CGFloat) -> Bool {
            if yFromTop + neededHeight > pageHeight - margin {
                newPage()
                return true
            }
            return false
        }

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        yFromTop += drawWrappedText("Quiz Results - \(difficulty.rawValue)", yTop: yFromTop, attrs: titleAttrs) + 10

        // Score
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.darkGray
        ]
        let percentage = questions.count > 0 ? Int(Double(score) / Double(questions.count) * 100) : 0
        yFromTop += drawWrappedText("Score: \(score)/\(questions.count) (\(percentage)%)", yTop: yFromTop, attrs: scoreAttrs) + 10

        // Date
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.gray
        ]
        yFromTop += drawWrappedText("Date: \(Date().formatted(date: .long, time: .shortened))", yTop: yFromTop, attrs: dateAttrs) + 30

        // Question styling
        let questionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.black
        ]
        let optionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        let correctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemGreen
        ]
        let wrongAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemRed
        ]
        let explanationAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ]

        // Export ALL questions
        for (i, question) in questions.enumerated() {
            // Calculate total height needed for this question
            let questionText = "\(i + 1). \(question.question)"
            let questionHeight = textHeight(questionText, attrs: questionAttrs, width: contentWidth)

            var optionsHeight: CGFloat = 0
            for (j, option) in question.options.enumerated() {
                let prefix = ["A", "B", "C", "D"][j]
                let optText = "\(prefix). \(option)"
                optionsHeight += textHeight(optText, attrs: optionAttrs, width: contentWidth - 15) + 4
            }

            let explanationHeight = question.explanation.isEmpty ? 0 :
                textHeight("Explanation: \(question.explanation)", attrs: explanationAttrs, width: contentWidth - 15) + 10

            let totalHeight = questionHeight + 8 + optionsHeight + explanationHeight + 20

            // If question doesn't fit on current page and we're not at top, start new page
            if yFromTop > margin && yFromTop + totalHeight > pageHeight - margin {
                newPage()
            }

            // Draw question number and text
            yFromTop += drawWrappedText(questionText, yTop: yFromTop, attrs: questionAttrs) + 8

            // Draw options
            for (j, option) in question.options.enumerated() {
                let prefix = ["A", "B", "C", "D"][j]
                let isCorrect = j == question.correctIndex
                let wasSelected = j == question.userAnswer
                let attrs = isCorrect ? correctAttrs : (wasSelected ? wrongAttrs : optionAttrs)
                let marker = isCorrect ? " ✓" : (wasSelected ? " ✗" : "")

                // Check if this option needs new page
                let optText = "\(prefix). \(option)\(marker)"
                let optHeight = textHeight(optText, attrs: attrs, width: contentWidth - 15)
                _ = ensureSpace(optHeight + 4)

                yFromTop += drawWrappedText(optText, yTop: yFromTop, attrs: attrs, indent: 15) + 4
            }

            // Draw explanation
            if !question.explanation.isEmpty {
                let explText = "Explanation: \(question.explanation)"
                let explHeight = textHeight(explText, attrs: explanationAttrs, width: contentWidth - 15)
                _ = ensureSpace(explHeight + 10)

                yFromTop += 5
                yFromTop += drawWrappedText(explText, yTop: yFromTop, attrs: explanationAttrs, indent: 15) + 5
            }

            yFromTop += 20
        }

        UIGraphicsEndPDFContext()

        do {
            try pdfData.write(to: url)
            print("PDF saved successfully with \(questions.count) questions")
        } catch {
            print("Error saving PDF: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct DiscussionBubble: View {
    let message: DiscussionMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? Color.accentColor : Color(.systemGray).opacity(0.2))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

struct QuizOptionButton: View {
    let text: String
    let index: Int
    let selectedAnswer: Int?
    let correctAnswer: Int
    let hasAnswered: Bool
    let action: () -> Void

    @State private var isHovering = false

    var backgroundColor: Color {
        if !hasAnswered {
            if isHovering {
                return Color.accentColor.opacity(0.15)
            }
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
            if selectedAnswer == index {
                return Color.accentColor
            }
            return isHovering ? Color.accentColor.opacity(0.5) : Color(.systemGray).opacity(0.3)
        } else {
            if index == correctAnswer {
                return Color.green
            } else if index == selectedAnswer {
                return Color.red
            }
            return Color(.systemGray).opacity(0.2)
        }
    }

    var body: some View {
        HStack {
            // Letter badge - clear click target indicator
            Text(["A", "B", "C", "D"][index])
                .fontWeight(.bold)
                .foregroundColor(!hasAnswered ? .accentColor : .primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(!hasAnswered && (isHovering || selectedAnswer == index)
                            ? Color.accentColor.opacity(0.2)
                            : Color(.systemGray).opacity(0.15))
                )

            Text(text.isEmpty ? " " : text)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(minHeight: 20)

            Spacer()

            if hasAnswered {
                if index == correctAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if index == selectedAnswer {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            } else {
                // Tap indicator for unanswered options
                Image(systemName: "hand.tap")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(isHovering ? 0.8 : 0.4))
            }
        }
        .padding()
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: hasAnswered ? 2 : 1.5)
        )
        .cornerRadius(12)
        .shadow(color: isHovering && !hasAnswered ? Color.accentColor.opacity(0.2) : Color.clear, radius: 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if !hasAnswered {
                action()
            }
        }
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
                .textSelection(.enabled)

            ForEach(0..<question.options.count, id: \.self) { i in
                HStack {
                    Text(["A", "B", "C", "D"][i])
                        .fontWeight(.bold)
                        .frame(width: 24)

                    Text(question.options[i])
                        .textSelection(.enabled)

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
                    .textSelection(.enabled)
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
private var pdfPageRect: CGRect = .zero

func UIGraphicsBeginPDFContextToData(_ data: NSMutableData, _ bounds: CGRect, _ documentInfo: [String: Any]?) {
    pdfPageRect = bounds
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    var mediaBox = bounds
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
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
    NSGraphicsContext.current = nil
}
#endif
