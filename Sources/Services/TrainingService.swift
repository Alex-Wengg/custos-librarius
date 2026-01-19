import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXOptimizers

/// Service for LoRA fine-tuning with early stopping
class TrainingService {
    private let projectPath: URL
    private var shouldStop = false

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    func train(
        trainFile: URL,
        validFile: URL,
        iterations: Int,
        patience: Int,
        learningRate: Float,
        loraLayers: Int,
        onProgress: @escaping (TrainingProgress) -> Void
    ) async throws {
        shouldStop = false

        // Load config
        let configPath = projectPath.appendingPathComponent("librarian.json")
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(AppProjectConfig.self, from: data)

        // Load model
        let modelConfig = ModelConfiguration(id: config.model)
        let context = try await LLMModelFactory.shared.load(configuration: modelConfig)

        let model = context.model
        let tokenizer = context.tokenizer

        // Apply LoRA
        let loraConfig = LoRAConfiguration(
            numLayers: loraLayers,
            fineTuneType: .lora,
            loraParameters: .init(rank: 8, scale: 10.0)
        )
        _ = try LoRAContainer.from(model: model, configuration: loraConfig)

        // Load training data
        let trainData = try loadTrainingData(from: trainFile)
        let validData = try loadTrainingData(from: validFile)

        // Setup optimizer
        let optimizer = Adam(learningRate: learningRate)
        let adapterPath = projectPath.appendingPathComponent("data/adapters.safetensors")
        let bestAdapterPath = projectPath.appendingPathComponent("data/adapters-best.safetensors")

        let parameters = LoRATrain.Parameters(
            batchSize: 1,
            iterations: iterations,
            stepsPerReport: 10,
            stepsPerEval: 50,
            validationBatches: 5,
            saveEvery: 50,
            adapterURL: adapterPath
        )

        // Early stopping state
        var bestValidLoss: Float = .infinity
        var patienceCounter = 0
        var bestIteration = 0

        try LoRATrain.train(
            model: model,
            train: trainData,
            validate: validData,
            optimizer: optimizer,
            tokenizer: tokenizer,
            parameters: parameters
        ) { progress in
            if self.shouldStop {
                return .stop
            }

            let progressStr = String(describing: progress)

            // Parse progress
            var currentIteration = 0
            var trainLoss: Float = 0
            var validLoss: Float?

            // Extract iteration
            if let iterRange = progressStr.range(of: "Iteration "),
               let colonRange = progressStr.range(of: ":") {
                let iterStr = String(progressStr[iterRange.upperBound..<colonRange.lowerBound])
                currentIteration = Int(iterStr) ?? 0
            }

            // Extract training loss
            if let range = progressStr.range(of: "training loss ") {
                let afterLoss = progressStr[range.upperBound...]
                if let commaIndex = afterLoss.firstIndex(of: ",") {
                    let lossStr = String(afterLoss[..<commaIndex])
                    trainLoss = Float(lossStr) ?? 0
                }
            }

            // Extract validation loss
            if progressStr.contains("validation loss") {
                if let range = progressStr.range(of: "validation loss "),
                   let endRange = progressStr.range(of: ", validation time") {
                    let lossStr = String(progressStr[range.upperBound..<endRange.lowerBound])
                    if let loss = Float(lossStr) {
                        validLoss = loss

                        // Early stopping check
                        if loss < bestValidLoss - 0.001 {
                            bestValidLoss = loss
                            patienceCounter = 0
                            bestIteration = currentIteration
                            try? LoRATrain.saveLoRAWeights(model: model, url: bestAdapterPath)
                        } else {
                            patienceCounter += 1
                            if patienceCounter >= patience {
                                // Restore best weights
                                let fileManager = FileManager.default
                                if fileManager.fileExists(atPath: bestAdapterPath.path) {
                                    try? fileManager.removeItem(at: adapterPath)
                                    try? fileManager.copyItem(at: bestAdapterPath, to: adapterPath)
                                }
                                return .stop
                            }
                        }
                    }
                }
            }

            // Report progress
            let progressReport = TrainingProgress(
                iteration: currentIteration,
                totalIterations: iterations,
                trainingLoss: trainLoss,
                validationLoss: validLoss,
                bestLoss: bestValidLoss,
                patienceCounter: patienceCounter
            )

            DispatchQueue.main.async {
                onProgress(progressReport)
            }

            return .more
        }

        // Save final weights
        try LoRATrain.saveLoRAWeights(model: model, url: adapterPath)
    }

    func stopTraining() {
        shouldStop = true
    }

    private func loadTrainingData(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        return lines.compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONDecoder().decode(TrainingLine.self, from: data) else {
                return nil
            }
            return json.text
        }
    }
}

struct TrainingLine: Codable {
    let text: String
}
