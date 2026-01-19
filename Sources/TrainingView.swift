import SwiftUI

struct TrainingView: View {
    @EnvironmentObject var appState: AppState
    @State private var trainFile: URL?
    @State private var validFile: URL?
    @State private var iterations = 500
    @State private var patience = 5
    @State private var learningRate = 1e-5
    @State private var loraLayers = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("LoRA Fine-tuning")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Train the model on your Q&A data with early stopping")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Data files
                GroupBox("Training Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        FilePickerRow(label: "Training file:", file: $trainFile, types: ["jsonl", "txt"])
                        FilePickerRow(label: "Validation file:", file: $validFile, types: ["jsonl", "txt"])
                    }
                    .padding(8)
                }

                // Hyperparameters
                GroupBox("Hyperparameters") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Max iterations:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("", value: $iterations, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text("(will stop early if no improvement)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Patience:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("", value: $patience, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text("evaluations without improvement before stopping")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Learning rate:")
                                .frame(width: 120, alignment: .trailing)
                            TextField("", value: $learningRate, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("LoRA layers:")
                                .frame(width: 120, alignment: .trailing)
                            Picker("", selection: $loraLayers) {
                                ForEach([2, 4, 8, 16], id: \.self) { n in
                                    Text("\(n)").tag(n)
                                }
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(8)
                }

                // Progress
                if appState.isTraining, let progress = appState.trainingProgress {
                    GroupBox("Training Progress") {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: Double(progress.iteration), total: Double(progress.totalIterations)) {
                                HStack {
                                    Text("Iteration \(progress.iteration)/\(progress.totalIterations)")
                                    Spacer()
                                    Text("\(Int(Double(progress.iteration) / Double(progress.totalIterations) * 100))%")
                                }
                            }

                            HStack(spacing: 24) {
                                VStack(alignment: .leading) {
                                    Text("Training Loss")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.4f", progress.trainingLoss))
                                        .font(.title3)
                                        .fontWeight(.medium)
                                }

                                if let validLoss = progress.validationLoss {
                                    VStack(alignment: .leading) {
                                        Text("Validation Loss")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.4f", validLoss))
                                            .font(.title3)
                                            .fontWeight(.medium)
                                    }
                                }

                                VStack(alignment: .leading) {
                                    Text("Best Loss")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.4f", progress.bestLoss))
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                }

                                VStack(alignment: .leading) {
                                    Text("Patience")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(progress.patienceCounter)/\(patience)")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                // Actions
                HStack {
                    Spacer()

                    if appState.isTraining {
                        Button("Stop Training") {
                            stopTraining()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Start Training") {
                            startTraining()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trainFile == nil || validFile == nil)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Training")
    }

    func startTraining() {
        guard let train = trainFile, let valid = validFile else { return }

        appState.isTraining = true

        Task {
            do {
                try await appState.trainingService?.train(
                    trainFile: train,
                    validFile: valid,
                    iterations: iterations,
                    patience: patience,
                    learningRate: Float(learningRate),
                    loraLayers: loraLayers
                ) { progress in
                    appState.trainingProgress = progress
                }
            } catch {
                print("Training error: \(error)")
            }
            appState.isTraining = false
        }
    }

    func stopTraining() {
        appState.trainingService?.stopTraining()
        appState.isTraining = false
    }
}

struct FilePickerRow: View {
    let label: String
    @Binding var file: URL?
    let types: [String]

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .trailing)

            if let file = file {
                Text(file.lastPathComponent)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button("Change") {
                    pickFile()
                }
            } else {
                Button("Select File...") {
                    pickFile()
                }
            }

            Spacer()
        }
    }

    func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types.compactMap { ext in
            switch ext {
            case "jsonl": return .json
            case "txt": return .plainText
            default: return nil
            }
        }

        if panel.runModal() == .OK {
            file = panel.url
        }
    }
}
