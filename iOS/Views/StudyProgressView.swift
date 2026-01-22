import SwiftUI

// Note: Named StudyProgressView to avoid conflict with SwiftUI's ProgressView
struct StudyProgressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "Quizzes Taken",
                            value: "\(appState.progress.quizzesTaken)",
                            icon: "checkmark.circle",
                            color: .blue
                        )

                        StatCard(
                            title: "Avg Score",
                            value: averageScore,
                            icon: "star",
                            color: .yellow
                        )

                        StatCard(
                            title: "Cards Reviewed",
                            value: "\(appState.progress.flashcardsReviewed)",
                            icon: "rectangle.on.rectangle",
                            color: .purple
                        )

                        StatCard(
                            title: "Last Studied",
                            value: lastStudiedText,
                            icon: "clock",
                            color: .green
                        )
                    }
                    .padding()

                    // Library Stats
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Library Overview", systemImage: "books.vertical")
                                .font(.headline)

                            Divider()

                            StatRow(label: "Quiz Sets", value: "\(appState.quizSets.count)")
                            StatRow(label: "Flashcard Sets", value: "\(appState.flashcardSets.count)")
                            StatRow(label: "Total Questions", value: "\(totalQuestions)")
                            StatRow(label: "Total Flashcards", value: "\(totalFlashcards)")
                        }
                    }
                    .padding(.horizontal)

                    // Sync Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Sync Status", systemImage: "icloud")
                                .font(.headline)

                            Divider()

                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Data synced from Mac")
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                Task {
                                    await appState.loadData()
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Progress")
            .refreshable {
                await appState.loadData()
            }
        }
    }

    var averageScore: String {
        guard appState.progress.totalQuestions > 0 else { return "—" }
        let avg = Double(appState.progress.totalScore) / Double(appState.progress.totalQuestions) * 100
        return String(format: "%.0f%%", avg)
    }

    var lastStudiedText: String {
        guard let date = appState.progress.lastStudied else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var totalQuestions: Int {
        appState.quizSets.reduce(0) { $0 + $1.questions.count }
    }

    var totalFlashcards: Int {
        appState.flashcardSets.reduce(0) { $0 + $1.cards.count }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    StudyProgressView()
        .environmentObject(AppState())
}
