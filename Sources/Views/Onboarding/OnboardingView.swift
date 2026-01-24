import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("modelId") private var modelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    @State private var currentStep = 0
    @State private var selectedRAM: RAMTier = .medium
    @State private var selectedModel: String?
    @State private var isDetectingRAM = true
    @State private var detectedRAM: Int = 16

    enum RAMTier: String, CaseIterable {
        case small = "8GB or less"
        case medium = "16GB"
        case large = "32GB+"

        var recommendedModels: [ModelRecommendation] {
            switch self {
            case .small:
                return [
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
                        name: "DeepSeek R1 1.5B",
                        size: "~1GB",
                        description: "Fast responses, good for quick quizzes",
                        isRecommended: false
                    ),
                    ModelRecommendation(
                        id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                        name: "Qwen 2.5 3B",
                        size: "~2GB",
                        description: "Balanced speed and quality",
                        isRecommended: true
                    ),
                ]
            case .medium:
                return [
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
                        name: "DeepSeek R1 7B",
                        size: "~4GB",
                        description: "Fast, excellent reasoning",
                        isRecommended: false
                    ),
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-3bit",
                        name: "DeepSeek R1 14B (3-bit)",
                        size: "~5GB",
                        description: "14B quality at 7B speed!",
                        isRecommended: true
                    ),
                    ModelRecommendation(
                        id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                        name: "Qwen 2.5 7B",
                        size: "~4GB",
                        description: "Well-rounded, reliable",
                        isRecommended: false
                    ),
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit",
                        name: "DeepSeek R1 14B (4-bit)",
                        size: "~8GB",
                        description: "Best quality, tight on RAM",
                        isRecommended: false
                    ),
                ]
            case .large:
                return [
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit",
                        name: "DeepSeek R1 14B",
                        size: "~8GB",
                        description: "Excellent reasoning quality",
                        isRecommended: true
                    ),
                    ModelRecommendation(
                        id: "mlx-community/Qwen2.5-14B-Instruct-4bit",
                        name: "Qwen 2.5 14B",
                        size: "~8GB",
                        description: "High quality, reliable",
                        isRecommended: false
                    ),
                    ModelRecommendation(
                        id: "mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit",
                        name: "DeepSeek R1 32B",
                        size: "~18GB",
                        description: "Best reasoning, needs RAM",
                        isRecommended: false
                    ),
                    ModelRecommendation(
                        id: "mlx-community/Qwen2.5-32B-Instruct-4bit",
                        name: "Qwen 2.5 32B",
                        size: "~18GB",
                        description: "Top tier quality",
                        isRecommended: false
                    ),
                ]
            }
        }
    }

    struct ModelRecommendation: Identifiable {
        let id: String
        let name: String
        let size: String
        let description: String
        let isRecommended: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.copper)

                Text("Welcome to Custos Librarius")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your AI-powered study companion")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 30)

            // Content
            TabView(selection: $currentStep) {
                // Step 1: Welcome
                welcomeStep
                    .tag(0)

                // Step 2: Select RAM
                ramSelectionStep
                    .tag(1)

                // Step 3: Select Model
                modelSelectionStep
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(maxHeight: .infinity)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Step indicators
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == currentStep ? Theme.copper : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 2 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.copper)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.copper)
                    .disabled(selectedModel == nil)
                }
            }
            .padding(30)
        }
        .frame(width: 600, height: 550)
        .onAppear {
            detectRAM()
        }
    }

    // MARK: - Steps

    var welcomeStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "doc.text.fill",
                    title: "Upload Documents",
                    description: "Add PDFs and text files to build your knowledge base"
                )

                FeatureRow(
                    icon: "brain",
                    title: "AI-Powered Quizzes",
                    description: "Generate quizzes from your documents using local AI"
                )

                FeatureRow(
                    icon: "cpu",
                    title: "100% Local & Private",
                    description: "Everything runs on your Mac - no data leaves your device"
                )

                FeatureRow(
                    icon: "sparkles",
                    title: "Fine-Tune for Better Results",
                    description: "Train the AI on your specific content"
                )
            }
            .padding(.horizontal, 40)
        }
    }

    var ramSelectionStep: some View {
        VStack(spacing: 20) {
            Text("How much RAM does your Mac have?")
                .font(.title2)
                .fontWeight(.semibold)

            if isDetectingRAM {
                ProgressView("Detecting...")
            } else {
                Text("Detected: \(detectedRAM)GB RAM")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(RAMTier.allCases, id: \.self) { tier in
                    RAMTierButton(
                        tier: tier,
                        isSelected: selectedRAM == tier,
                        isDetected: isDetectedTier(tier)
                    ) {
                        selectedRAM = tier
                        // Pre-select recommended model
                        if let recommended = tier.recommendedModels.first(where: { $0.isRecommended }) {
                            selectedModel = recommended.id
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Text("This helps us recommend the best model for your Mac")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    var modelSelectionStep: some View {
        VStack(spacing: 20) {
            Text("Choose your AI model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Recommended for \(selectedRAM.rawValue)")
                .font(.callout)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(selectedRAM.recommendedModels) { model in
                        ModelSelectionButton(
                            model: model,
                            isSelected: selectedModel == model.id
                        ) {
                            selectedModel = model.id
                        }
                    }
                }
                .padding(.horizontal, 40)
            }

            Text("You can change this later in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    func detectRAM() {
        isDetectingRAM = true

        // Get physical memory
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        detectedRAM = Int(physicalMemory / 1_073_741_824) // Convert to GB

        // Auto-select tier based on RAM
        if detectedRAM <= 8 {
            selectedRAM = .small
        } else if detectedRAM <= 16 {
            selectedRAM = .medium
        } else {
            selectedRAM = .large
        }

        // Pre-select recommended model
        if let recommended = selectedRAM.recommendedModels.first(where: { $0.isRecommended }) {
            selectedModel = recommended.id
        }

        isDetectingRAM = false
    }

    func isDetectedTier(_ tier: RAMTier) -> Bool {
        switch tier {
        case .small: return detectedRAM <= 8
        case .medium: return detectedRAM > 8 && detectedRAM <= 16
        case .large: return detectedRAM > 16
        }
    }

    func completeOnboarding() {
        if let model = selectedModel {
            modelId = model
        }
        hasCompletedOnboarding = true
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.copper)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct RAMTierButton: View {
    let tier: OnboardingView.RAMTier
    let isSelected: Bool
    let isDetected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.rawValue)
                            .fontWeight(.medium)
                        if isDetected {
                            Text("(Detected)")
                                .font(.caption)
                                .foregroundColor(Theme.copper)
                        }
                    }
                    Text(tierDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.copper)
                }
            }
            .padding()
            .background(isSelected ? Theme.copper.opacity(0.1) : Color(.systemGray).opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.copper : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    var tierDescription: String {
        switch tier {
        case .small: return "Use smaller, faster models"
        case .medium: return "Good balance of quality and speed"
        case .large: return "Use larger, higher quality models"
        }
    }
}

struct ModelSelectionButton: View {
    let model: OnboardingView.ModelRecommendation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name)
                            .fontWeight(.medium)
                        if model.isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.copper.opacity(0.2))
                                .foregroundColor(Theme.copper)
                                .cornerRadius(4)
                        }
                    }

                    HStack {
                        Text(model.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(model.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.copper)
                }
            }
            .padding()
            .background(isSelected ? Theme.copper.opacity(0.1) : Color(.systemGray).opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.copper : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
