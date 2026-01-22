import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// Simple standalone test for loading Qwen and generating text

func runLLMTest() async {
    print("=== MLX LLM Quick Test ===\n")

    do {
        // 1. Load model
        let modelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"
        print("1. Loading model: \(modelId)")
        print("   This may download ~4GB on first run...\n")

        let config = ModelConfiguration(id: modelId)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
            if progress.fractionCompleted < 1.0 && Int(progress.fractionCompleted * 100) % 10 == 0 {
                print("   Downloading: \(Int(progress.fractionCompleted * 100))%")
            }
        }
        print("   ✓ Model loaded!\n")

        // 2. Simple generation test
        print("2. Testing simple generation...")
        let prompt = "What is the capital of France? Answer in one sentence."
        print("   Prompt: \"\(prompt)\"\n")

        let messages: [Chat.Message] = [
            .system("You are a helpful assistant. Be concise."),
            .user(prompt)
        ]

        let userInput = UserInput(chat: messages)
        var output = ""
        var tokenCount = 0
        let startTime = Date()

        try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: 100, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    output += chunk
                    tokenCount += 1
                    print(chunk, terminator: "")
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("\n\n   Tokens: \(tokenCount), Time: \(String(format: "%.2f", elapsed))s, Speed: \(String(format: "%.1f", Double(tokenCount)/elapsed)) tok/s")
        print("   ✓ Generation works!\n")

        // 3. Quiz generation test
        print("3. Testing quiz generation...")
        let quizPrompt = """
        Create a multiple choice question about this text:

        "The Great Wall of China was built over many centuries, with construction beginning in the 7th century BC. It stretches over 13,000 miles and was primarily built to protect against invasions from northern nomadic groups."

        Output valid JSON only:
        {"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "..."}
        """

        let quizMessages: [Chat.Message] = [
            .system("You create educational quiz questions. Output valid JSON only."),
            .user(quizPrompt)
        ]

        let quizInput = UserInput(chat: quizMessages)
        var quizOutput = ""

        try await container.perform { context in
            let input = try await context.processor.prepare(input: quizInput)
            let parameters = GenerateParameters(maxTokens: 300, temperature: 0.7)

            for await item in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if case .chunk(let chunk) = item {
                    quizOutput += chunk
                }
            }
        }

        print("   Raw output:")
        print("   \(quizOutput)\n")

        // Try to parse JSON
        if let start = quizOutput.firstIndex(of: "{"),
           let end = quizOutput.lastIndex(of: "}") {
            let jsonStr = String(quizOutput[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let question = json["question"] as? String,
               let options = json["options"] as? [String] {
                print("   ✓ Valid JSON parsed!")
                print("   Question: \(question)")
                print("   Options: \(options)")
            } else {
                print("   ⚠️ JSON parsing failed")
            }
        }

        print("\n=== All Tests Complete! ===")

    } catch {
        print("❌ Error: \(error)")
    }
}

// Entry point
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runLLMTest()
    semaphore.signal()
}
semaphore.wait()
