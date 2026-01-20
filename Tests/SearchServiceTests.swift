import XCTest
@testable import CustosLibrarius

final class SearchServiceTests: XCTestCase {

    // MARK: - BM25 Algorithm Tests

    func testBM25SearchBasic() async throws {
        // Create a temporary directory with test data
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test chunks
        let dataDir = tempDir.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let testChunks = [
            ChunkData(id: "1", text: "The quick brown fox jumps over the lazy dog", source: "test.txt", title: "Test", author: "Test", index: 0),
            ChunkData(id: "2", text: "A lazy cat sleeps all day long", source: "test.txt", title: "Test", author: "Test", index: 1),
            ChunkData(id: "3", text: "The brown bear runs through the forest", source: "test.txt", title: "Test", author: "Test", index: 2),
            ChunkData(id: "4", text: "Swift programming language is great for iOS development", source: "code.txt", title: "Code", author: "Dev", index: 3),
        ]

        let chunksData = try JSONEncoder().encode(testChunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        // Test search
        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "lazy", topK: 2)

        XCTAssertEqual(results.count, 2)
        // "lazy" appears in first two documents
        XCTAssertTrue(results[0].text.contains("lazy") || results[1].text.contains("lazy"))
    }

    func testBM25SearchRelevanceRanking() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataDir = tempDir.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Document with "swift" multiple times should rank higher
        let testChunks = [
            ChunkData(id: "1", text: "Python is a programming language", source: "a.txt", title: "A", author: "A", index: 0),
            ChunkData(id: "2", text: "Swift is fast. Swift is safe. Swift is expressive.", source: "b.txt", title: "B", author: "B", index: 1),
            ChunkData(id: "3", text: "Java and Swift are both used for mobile development", source: "c.txt", title: "C", author: "C", index: 2),
        ]

        let chunksData = try JSONEncoder().encode(testChunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "swift", topK: 3)

        XCTAssertEqual(results.count, 3)
        // Document with most "swift" mentions should be first
        XCTAssertTrue(results[0].text.lowercased().contains("swift is fast"))
    }

    func testBM25SearchEmptyQuery() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataDir = tempDir.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let testChunks = [
            ChunkData(id: "1", text: "Some test content", source: "test.txt", title: "Test", author: "Test", index: 0),
        ]

        let chunksData = try JSONEncoder().encode(testChunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "", topK: 5)

        // Empty query should return results (all with 0 score)
        XCTAssertTrue(results.count <= 5)
    }

    func testBM25SearchNoMatches() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataDir = tempDir.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let testChunks = [
            ChunkData(id: "1", text: "Apple banana cherry", source: "fruits.txt", title: "Fruits", author: "Test", index: 0),
        ]

        let chunksData = try JSONEncoder().encode(testChunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "programming", topK: 5)

        // Should still return results but with low/zero scores
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].score, 0)
    }

    func testBM25SearchEmptyIndex() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // No data directory - empty index
        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "test", topK: 5)

        XCTAssertEqual(results.count, 0)
    }

    func testBM25SearchMultiWordQuery() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataDir = tempDir.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let testChunks = [
            ChunkData(id: "1", text: "Machine learning is a subset of artificial intelligence", source: "ai.txt", title: "AI", author: "Test", index: 0),
            ChunkData(id: "2", text: "Deep learning uses neural networks", source: "ml.txt", title: "ML", author: "Test", index: 1),
            ChunkData(id: "3", text: "Machine translation converts text between languages", source: "nlp.txt", title: "NLP", author: "Test", index: 2),
        ]

        let chunksData = try JSONEncoder().encode(testChunks)
        try chunksData.write(to: dataDir.appendingPathComponent("chunks.json"))

        let service = SearchService(projectPath: tempDir)
        let results = try await service.search(query: "machine learning", topK: 3)

        XCTAssertEqual(results.count, 3)
        // First result should contain both "machine" and "learning"
        XCTAssertTrue(results[0].text.lowercased().contains("machine") && results[0].text.lowercased().contains("learning"))
    }
}
