import SwiftUI

/// View for running LLM output tests from within the app
struct LLMTestView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRunning = false
    @State private var testResults: [TestResult] = []
    @State private var currentTest = ""
    @State private var overallStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LLM Output Tests")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(currentTest)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            Text("Tests actual LLM generation for quiz questions, open-ended questions, and discussions.")
                .foregroundColor(.secondary)
                .font(.caption)

            Divider()

            if testResults.isEmpty && !isRunning {
                VStack(spacing: 12) {
                    Image(systemName: "testtube.2")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("Click 'Run Tests' to test LLM output quality")
                        .foregroundColor(.secondary)

                    if appState.currentProject == nil {
                        Text("⚠️ Open a project with indexed documents first")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(testResults) { result in
                            TestResultRow(result: result)
                        }
                    }
                }
            }

            Divider()

            HStack {
                if !overallStatus.isEmpty {
                    Text(overallStatus)
                        .font(.headline)
                        .foregroundColor(overallStatus.contains("passed") ? .green : .orange)
                }

                Spacer()

                Button("Clear") {
                    testResults = []
                    overallStatus = ""
                }
                .disabled(isRunning || testResults.isEmpty)

                Button("Run Tests") {
                    Task {
                        await runTests()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || appState.chatService == nil)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }

    func runTests() async {
        guard let chatService = appState.chatService else { return }

        isRunning = true
        testResults = []
        overallStatus = ""

        // Test 1: Easy Quiz
        currentTest = "Testing Easy Quiz..."
        let easyResult = await testQuizGeneration(chatService: chatService, difficulty: .easy, name: "Easy Quiz")
        testResults.append(easyResult)

        // Test 2: Medium Quiz
        currentTest = "Testing Medium Quiz..."
        let mediumResult = await testQuizGeneration(chatService: chatService, difficulty: .medium, name: "Medium Quiz")
        testResults.append(mediumResult)

        // Test 3: Hard Quiz
        currentTest = "Testing Hard Quiz..."
        let hardResult = await testQuizGeneration(chatService: chatService, difficulty: .hard, name: "Hard Quiz")
        testResults.append(hardResult)

        // Test 4: Open-Ended
        currentTest = "Testing Open-Ended..."
        let openEndedResult = await testOpenEndedGeneration(chatService: chatService)
        testResults.append(openEndedResult)

        // Test 5: Discussion
        currentTest = "Testing Discussion..."
        let discussionResult = await testDiscussion(chatService: chatService)
        testResults.append(discussionResult)

        // Summary
        let passed = testResults.filter { $0.passed }.count
        let total = testResults.count
        overallStatus = "\(passed)/\(total) tests passed"

        currentTest = ""
        isRunning = false
    }

    func testQuizGeneration(chatService: ChatService, difficulty: QuizDifficulty, name: String) async -> TestResult {
        do {
            let questions = try await chatService.generateQuiz(count: 1, difficulty: difficulty)

            guard let q = questions.first else {
                return TestResult(name: name, passed: false, details: "No question generated", output: "")
            }

            // Validate
            var issues: [String] = []

            if q.question.isEmpty {
                issues.append("Question is empty")
            }

            if q.options.count != 4 {
                issues.append("Expected 4 options, got \(q.options.count)")
            }

            let placeholders = ["option1", "option2", "option3", "option4", "option 1", "option 2"]
            for opt in q.options {
                if placeholders.contains(opt.lowercased()) {
                    issues.append("Placeholder found: \(opt)")
                }
                if opt.count <= 1 {
                    issues.append("Option too short: \(opt)")
                }
            }

            if Set(q.options).count != q.options.count {
                issues.append("Duplicate options")
            }

            if q.correctIndex < 0 || q.correctIndex >= q.options.count {
                issues.append("Invalid correct index")
            }

            let output = """
            Q: \(q.question)
            Options: \(q.options.joined(separator: " | "))
            Answer: \(q.options[q.correctIndex])
            Explanation: \(q.explanation)
            """

            if issues.isEmpty {
                return TestResult(name: name, passed: true, details: "Valid question generated", output: output)
            } else {
                return TestResult(name: name, passed: false, details: issues.joined(separator: ", "), output: output)
            }
        } catch {
            return TestResult(name: name, passed: false, details: "Error: \(error.localizedDescription)", output: "")
        }
    }

    func testOpenEndedGeneration(chatService: ChatService) async -> TestResult {
        do {
            let questions = try await chatService.generateOpenEndedQuiz(count: 1, difficulty: .medium)

            guard let q = questions.first else {
                return TestResult(name: "Open-Ended Question", passed: false, details: "No question generated", output: "")
            }

            var issues: [String] = []

            if q.question.isEmpty {
                issues.append("Question is empty")
            }

            if q.idealAnswer.isEmpty {
                issues.append("Ideal answer is empty")
            }

            if q.idealAnswer.count < 20 {
                issues.append("Ideal answer too short")
            }

            let output = """
            Q: \(q.question)
            Ideal: \(q.idealAnswer.prefix(200))...
            Key points: \(q.keyPoints.joined(separator: ", "))
            """

            if issues.isEmpty {
                return TestResult(name: "Open-Ended Question", passed: true, details: "Valid question generated", output: output)
            } else {
                return TestResult(name: "Open-Ended Question", passed: false, details: issues.joined(separator: ", "), output: output)
            }
        } catch {
            return TestResult(name: "Open-Ended Question", passed: false, details: "Error: \(error.localizedDescription)", output: "")
        }
    }

    func testDiscussion(chatService: ChatService) async -> TestResult {
        let question = OpenEndedQuestion(
            question: "What are the main types of machine learning?",
            idealAnswer: "Supervised, unsupervised, and reinforcement learning.",
            keyPoints: ["supervised", "unsupervised", "reinforcement"],
            source: "Test",
            context: "Machine learning has three main types."
        )

        do {
            let response = try await chatService.discussAnswer(
                question: question,
                userAnswer: "I think there's supervised learning where you use labeled data.",
                previousMessages: []
            )

            if response.isEmpty {
                return TestResult(name: "Discussion", passed: false, details: "Empty response", output: "")
            }

            if response.count < 50 {
                return TestResult(name: "Discussion", passed: false, details: "Response too short (\(response.count) chars)", output: response)
            }

            let output = """
            User: I think there's supervised learning where you use labeled data.
            AI: \(response.prefix(300))...
            """

            return TestResult(name: "Discussion", passed: true, details: "Valid response (\(response.count) chars)", output: output)
        } catch {
            return TestResult(name: "Discussion", passed: false, details: "Error: \(error.localizedDescription)", output: "")
        }
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let details: String
    let output: String
}

struct TestResultRow: View {
    let result: TestResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.passed ? .green : .red)

                Text(result.name)
                    .fontWeight(.medium)

                Spacer()

                Text(result.details)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }

            if isExpanded && !result.output.isEmpty {
                Text(result.output)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}
