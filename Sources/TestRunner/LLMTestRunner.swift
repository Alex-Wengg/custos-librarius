// LLM Integration Test Runner
// This file is excluded from the main build and kept for reference.
// To test LLM functionality, use the app directly or run tests from Xcode.
//
// MLX requires Metal GPU access which isn't available in the swift test
// command-line environment. Integration tests must be run from:
// 1. Xcode (with GPU access)
// 2. The running app (manual testing)
//
// The unit tests in Tests/ cover:
// - BM25 search algorithm (SearchServiceTests)
// - Data model serialization (ModelTests)
// - JSON parsing from LLM output (JSONParsingTests)
//
// For LLM generation testing, use the app's Quiz and Flashcard features
// and verify the output quality manually.

import Foundation

// Placeholder to prevent build errors when this directory is excluded
struct LLMTestRunnerPlaceholder {
    static let info = """
    LLM Integration Testing
    =======================

    Due to MLX requiring Metal GPU access, LLM tests cannot run from `swift test`.

    To test LLM functionality:

    1. Run the app: swift run CustosLibrarius
    2. Open a project with indexed documents
    3. Test Quiz generation (Multiple Choice and Open-Ended)
    4. Test Flashcard generation
    5. Test Discussion/Socratic dialogue

    Or run tests from Xcode which has proper GPU context.
    """
}
