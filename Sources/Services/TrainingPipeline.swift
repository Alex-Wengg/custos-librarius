import Foundation

/// Orchestrates the complete training pipeline:
/// 1. Load chunks from processed documents
/// 2. Generate training data using LOCAL Qwen model
/// 3. Export to Qwen format
/// 4. Train LoRA adapter
actor TrainingPipeline {
    private let projectPath: URL
    private var dataGenerator: TrainingDataGenerator?
    private var trainingService: TrainingService?

    init(projectPath: URL) {
        self.projectPath = projectPath
        self.trainingService = TrainingService(projectPath: projectPath)
    }

    // MARK: - Full Pipeline

    /// Run the complete training pipeline using LOCAL model
    func runFullPipeline(
        targetExamples: Int = 250,
        trainingIterations: Int = 200,
        patience: Int = 5,
        learningRate: Float = 1e-5,
        loraLayers: Int = 4,
        onProgress: @escaping (PipelineProgress) -> Void
    ) async throws -> PipelineResult {
        // Phase 1: Load chunks
        onProgress(PipelineProgress(phase: .loadingChunks, detail: "Loading processed documents...", percentComplete: 0))

        let chunks = try await loadChunks()
        guard !chunks.isEmpty else {
            throw PipelineError.noChunksAvailable
        }

        onProgress(PipelineProgress(phase: .loadingChunks, detail: "Loaded \(chunks.count) chunks", percentComplete: 5))

        // Phase 2: Load model and generate training data
        onProgress(PipelineProgress(phase: .generatingData, detail: "Loading local model...", percentComplete: 10))

        dataGenerator = TrainingDataGenerator(projectPath: projectPath)
        try await dataGenerator!.loadModel()

        onProgress(PipelineProgress(phase: .generatingData, detail: "Generating training data...", percentComplete: 15))

        let dataResult = try await dataGenerator!.generateTrainingData(
            chunks: chunks,
            targetCount: targetExamples,
            difficulties: [.easy, .medium, .hard]
        ) { progress in
            let overallPercent = 15 + Int(progress.percentComplete * 0.35) // 15-50%
            onProgress(PipelineProgress(
                phase: .generatingData,
                detail: progress.currentStatus,
                percentComplete: overallPercent
            ))
        }

        guard !dataResult.examples.isEmpty else {
            throw PipelineError.noExamplesGenerated
        }

        // Save examples for future use
        try await dataGenerator!.saveExamples(dataResult.examples)

        onProgress(PipelineProgress(
            phase: .generatingData,
            detail: "Generated \(dataResult.examples.count) training examples",
            percentComplete: 50
        ))

        // Phase 3: Export to training format
        onProgress(PipelineProgress(phase: .exportingData, detail: "Exporting to Qwen format...", percentComplete: 55))

        let (trainURL, validURL) = try await dataGenerator!.exportToJSONL(
            examples: dataResult.examples,
            trainRatio: 0.8
        )

        let trainCount = Int(Double(dataResult.examples.count) * 0.8)
        let validCount = dataResult.examples.count - trainCount

        onProgress(PipelineProgress(
            phase: .exportingData,
            detail: "Exported \(trainCount) train / \(validCount) validation examples",
            percentComplete: 60
        ))

        // Phase 4: Train LoRA adapter
        onProgress(PipelineProgress(phase: .training, detail: "Starting LoRA training...", percentComplete: 65))

        var finalTrainingProgress: TrainingProgress?

        try await trainingService?.train(
            trainFile: trainURL,
            validFile: validURL,
            iterations: trainingIterations,
            patience: patience,
            learningRate: learningRate,
            loraLayers: loraLayers
        ) { progress in
            finalTrainingProgress = progress
            let trainingPercent = 65 + Int(progress.percentComplete * 0.35) // 65-100%
            onProgress(PipelineProgress(
                phase: .training,
                detail: "Iteration \(progress.iteration)/\(progress.totalIterations) - Loss: \(String(format: "%.4f", progress.trainingLoss))",
                percentComplete: trainingPercent,
                trainingProgress: progress
            ))
        }

        // Phase 5: Complete
        onProgress(PipelineProgress(phase: .complete, detail: "Training complete!", percentComplete: 100))

        return PipelineResult(
            examplesGenerated: dataResult.examples.count,
            trainExamples: trainCount,
            validExamples: validCount,
            finalTrainingLoss: finalTrainingProgress?.trainingLoss ?? 0,
            finalValidationLoss: finalTrainingProgress?.validationLoss,
            bestLoss: finalTrainingProgress?.bestLoss ?? 0,
            adapterPath: projectPath.appendingPathComponent("data/adapters.safetensors"),
            errors: dataResult.errors
        )
    }

    // MARK: - Individual Steps

    /// Generate training data only (without training) - uses LOCAL model
    func generateTrainingDataOnly(
        targetExamples: Int = 250,
        onProgress: @escaping (TrainingDataProgress) -> Void
    ) async throws -> TrainingDataResult {
        let chunks = try await loadChunks()
        guard !chunks.isEmpty else {
            throw PipelineError.noChunksAvailable
        }

        dataGenerator = TrainingDataGenerator(projectPath: projectPath)
        try await dataGenerator!.loadModel()

        let result = try await dataGenerator!.generateTrainingData(
            chunks: chunks,
            targetCount: targetExamples,
            difficulties: [.easy, .medium, .hard],
            onProgress: onProgress
        )

        // Save examples
        try await dataGenerator!.saveExamples(result.examples)

        return result
    }

    /// Train from existing examples
    func trainFromExistingExamples(
        iterations: Int = 200,
        patience: Int = 5,
        learningRate: Float = 1e-5,
        loraLayers: Int = 4,
        onProgress: @escaping (TrainingProgress) -> Void
    ) async throws {
        // Load existing examples
        dataGenerator = TrainingDataGenerator(projectPath: projectPath)
        let examples = try await dataGenerator!.loadExamples()

        guard !examples.isEmpty else {
            throw PipelineError.noExamplesAvailable
        }

        // Export to JSONL
        let (trainURL, validURL) = try await dataGenerator!.exportToJSONL(
            examples: examples,
            trainRatio: 0.8
        )

        // Train
        try await trainingService?.train(
            trainFile: trainURL,
            validFile: validURL,
            iterations: iterations,
            patience: patience,
            learningRate: learningRate,
            loraLayers: loraLayers,
            onProgress: onProgress
        )
    }

    /// Check if training examples exist
    func hasExistingExamples() async -> Bool {
        let url = projectPath.appendingPathComponent("data/training_examples.json")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Get count of existing examples
    func getExistingExampleCount() async -> Int {
        dataGenerator = TrainingDataGenerator(projectPath: projectPath)
        guard let examples = try? await dataGenerator!.loadExamples() else {
            return 0
        }
        return examples.count
    }

    /// Check if trained adapter exists
    nonisolated func hasTrainedAdapter() -> Bool {
        let adapterPath = projectPath.appendingPathComponent("data/adapters.safetensors")
        return FileManager.default.fileExists(atPath: adapterPath.path)
    }

    /// Stop training
    func stopTraining() {
        trainingService?.stopTraining()
    }

    // MARK: - Helpers

    private func loadChunks() async throws -> [SemanticChunk] {
        let service = DocumentProcessingService(projectPath: projectPath)
        return try await service.loadChunks()
    }
}

// MARK: - Pipeline Types

enum PipelinePhase: String {
    case loadingChunks = "Loading Documents"
    case generatingData = "Generating Training Data"
    case exportingData = "Exporting Data"
    case training = "Training Model"
    case complete = "Complete"
}

struct PipelineProgress {
    let phase: PipelinePhase
    let detail: String
    let percentComplete: Int
    var trainingProgress: TrainingProgress?
}

struct PipelineResult {
    let examplesGenerated: Int
    let trainExamples: Int
    let validExamples: Int
    let finalTrainingLoss: Float
    let finalValidationLoss: Float?
    let bestLoss: Float
    let adapterPath: URL
    let errors: [String]

    var hasErrors: Bool { !errors.isEmpty }
}

enum PipelineError: Error, LocalizedError {
    case noChunksAvailable
    case noExamplesGenerated
    case noExamplesAvailable
    case trainingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noChunksAvailable:
            return "No processed documents available. Please process documents first."
        case .noExamplesGenerated:
            return "Failed to generate any training examples."
        case .noExamplesAvailable:
            return "No existing training examples found. Generate examples first."
        case .trainingFailed(let reason):
            return "Training failed: \(reason)"
        }
    }
}
