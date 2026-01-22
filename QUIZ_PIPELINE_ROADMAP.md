# Production-Quality Quiz Generation Pipeline

## Overview

This document outlines a comprehensive approach to generating high-quality quiz questions from PDF documents. The goal is to move beyond basic RAG to a production-grade system.

---

## Architecture

```
PDF Documents
      ↓
┌─────────────────┐
│ 1. DOCUMENT     │
│    PROCESSING   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 2. RETRIEVAL    │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 3. GENERATION   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 4. VALIDATION   │
└────────┬────────┘
         ↓
   Quiz Questions
```

---

## 1. Document Processing

### Current State
- Basic PDF text extraction
- Fixed character-count chunking (500 chars)
- Minimal metadata

### Target State
- **Structure extraction**: Headers, sections, paragraphs, lists
- **Semantic chunking**: Split by meaning, not arbitrary character count
- **Rich metadata**: Source, page number, chapter, section title, topic
- **Table/figure handling**: Extract and describe visual elements

### Implementation
```swift
struct SemanticChunk {
    let id: String
    let text: String
    let source: String
    let page: Int
    let section: String?
    let chapter: String?
    let topic: String?
    let precedingContext: String?  // What came before
    let followingContext: String?  // What comes after
}
```

### Chunking Strategy
1. Parse PDF structure (headers create boundaries)
2. Split at paragraph boundaries
3. Respect semantic units (don't split mid-sentence)
4. Overlap chunks slightly for context continuity
5. Target 300-800 tokens per chunk (not chars)

---

## 2. Retrieval System

### Current State
- BM25 keyword search
- Basic embedding similarity
- Single retrieval pass

### Target State
- **Hybrid search**: Combine BM25 (keyword) + dense embeddings (semantic)
- **Cross-encoder reranking**: Score relevance more accurately
- **Query expansion**: Generate related queries for better recall
- **Multi-hop retrieval**: Retrieve → reason → retrieve more if needed

### Implementation

```swift
struct RetrievalPipeline {
    // Stage 1: Initial retrieval (fast, high recall)
    func initialRetrieval(query: String, topK: Int = 50) -> [Chunk]

    // Stage 2: Reranking (slow, high precision)
    func rerank(query: String, chunks: [Chunk], topK: Int = 10) -> [Chunk]

    // Stage 3: Multi-hop (if needed)
    func expandAndRetrieve(query: String, context: [Chunk]) -> [Chunk]
}
```

### Hybrid Search Formula
```
final_score = α * bm25_score + (1-α) * embedding_score
α = 0.3 to 0.5 typically
```

### Reranking
- Use cross-encoder model (e.g., `bge-reranker-base`)
- Scores query-document pairs directly
- Much more accurate than bi-encoder similarity

---

## 3. Generation Pipeline

### Current State
- Single prompt
- Direct JSON output
- No examples

### Target State
- **Few-shot prompting**: Include 3-5 gold-standard examples
- **Chain-of-thought**: Multi-step reasoning before output
- **Best-of-N sampling**: Generate multiple, select best
- **Structured output**: Enforce JSON schema

### Few-Shot Examples

Include curated examples in every prompt:

```
Example 1:
Source text: "The Treaty of Westphalia was signed in 1648, ending the Thirty Years' War..."
Question: {"question": "In what year was the Treaty of Westphalia signed, ending the Thirty Years' War?", "options": ["1618", "1648", "1678", "1701"], "correctIndex": 1, "explanation": "The Treaty of Westphalia was signed in 1648."}

Example 2:
...

Example 3:
...

Now generate a question from this text:
[actual chunk]
```

### Chain-of-Thought Pipeline

```
Step 1: EXTRACT key facts from the text
→ "Key facts: Treaty signed 1648, ended Thirty Years War, established sovereignty principle"

Step 2: IDENTIFY testable knowledge
→ "Testable: Date (1648), what it ended (Thirty Years War), key principle (sovereignty)"

Step 3: FORMULATE question with full context
→ "Question about the date, including treaty name for context"

Step 4: CREATE plausible distractors
→ "Other dates from the era: 1618 (war start), 1678, 1701"

Step 5: OUTPUT JSON
→ Final formatted question
```

### Best-of-N Selection

```swift
func generateQuestion(chunk: Chunk) async -> QuizQuestion {
    var candidates: [QuizQuestion] = []

    // Generate N candidates
    for _ in 0..<3 {
        let candidate = try await generateSingle(chunk: chunk, temperature: 0.8)
        candidates.append(candidate)
    }

    // Score and select best
    return selectBest(candidates)
}

func selectBest(_ candidates: [QuizQuestion]) -> QuizQuestion {
    // Score based on:
    // - Self-containment (no vague references)
    // - Option quality (distinct, plausible)
    // - Question clarity
    return candidates.max(by: { score($0) < score($1) })!
}
```

---

## 4. Validation Layer

### Checks to Implement

```swift
struct QuizValidator {

    // 1. Structure validation
    func validateJSON(_ output: String) -> Bool

    // 2. Self-containment check
    func isSelfContained(_ question: QuizQuestion) -> Bool {
        let vaguePatterns = [
            "the author", "the organization", "the event",
            "the policy", "this person", "the study"
        ]
        return !vaguePatterns.any { question.question.contains($0) }
    }

    // 3. Option quality
    func hasValidOptions(_ question: QuizQuestion) -> Bool {
        let options = question.options
        return options.count == 4 &&
               Set(options).count == 4 &&  // All unique
               options.allSatisfy { $0.count > 2 } &&  // Not empty
               !hasPlaceholders(options)
    }

    // 4. Answer verification (check against source)
    func verifyAnswer(_ question: QuizQuestion, source: String) -> Bool

    // 5. Difficulty appropriate
    func matchesDifficulty(_ question: QuizQuestion, target: Difficulty) -> Bool
}
```

### Retry Logic

```swift
func generateWithRetry(chunk: Chunk, maxRetries: Int = 3) async -> QuizQuestion? {
    for attempt in 0..<maxRetries {
        let question = try await generate(chunk: chunk)
        let validation = validate(question)

        if validation.passed {
            return question
        }

        // Retry with feedback
        let feedback = "Previous attempt failed: \(validation.reason). Please fix."
        // Include feedback in next prompt
    }
    return nil
}
```

---

## 5. Model & Training

### Base Model
- **Qwen 2.5 7B Instruct 4-bit**
- Good instruction following
- Fits in 16GB RAM

### LoRA Fine-Tuning

#### Training Data Format (JSONL)
```json
{"text": "<|im_start|>system\nYou are an expert quiz creator...<|im_end|>\n<|im_start|>user\n[few-shot examples]\n\nNow create a question from:\n[chunk text]<|im_end|>\n<|im_start|>assistant\n{\"question\": \"...\", \"options\": [...], \"correctIndex\": 0, \"explanation\": \"...\"}<|im_end|>"}
```

#### Training Data Creation
1. Use Claude API to generate 200-300 high-quality examples (one-time cost ~$2)
2. Human review and curation
3. Split 80/20 train/validation

#### Training Parameters
```swift
LoRAConfig:
  rank: 16
  alpha: 32
  dropout: 0.05
  targetModules: ["q_proj", "v_proj", "k_proj", "o_proj"]

TrainingConfig:
  learningRate: 1e-4
  batchSize: 1
  gradientAccumulation: 4
  epochs: 3
  warmupSteps: 50
```

#### Ship Pre-Trained Adapter
- Train once, bundle with app
- ~20-50MB adapter file
- All users get improved quality

---

## 6. Implementation Plan

### Phase 1: Document Processing Foundation
- [ ] PDF parsing with structure extraction (headers, sections, paragraphs)
- [ ] Semantic chunking by meaning boundaries
- [ ] Rich metadata extraction (page, chapter, section, topic)
- [ ] Table and figure handling

### Phase 2: Retrieval System
- [ ] Hybrid search (BM25 + dense embeddings)
- [ ] Cross-encoder reranking
- [ ] Query expansion
- [ ] Multi-hop retrieval for complex questions

### Phase 3: Generation Pipeline
- [ ] Few-shot prompting with curated gold-standard examples
- [ ] Chain-of-thought reasoning pipeline
- [ ] Best-of-N sampling with quality scoring
- [ ] Structured output enforcement

### Phase 4: Validation & Quality Assurance
- [ ] JSON structure validation
- [ ] Self-containment verification
- [ ] Option quality checks
- [ ] Answer verification against source
- [ ] Retry with feedback loop

### Phase 5: Model Fine-Tuning
- [ ] Generate high-quality training data
- [ ] Train LoRA adapter on Qwen 7B
- [ ] Evaluation against gold standard
- [ ] Ship pre-trained adapter with app

---

## 7. Metrics & Evaluation

### Quality Metrics
- **Self-containment rate**: % of questions that don't use vague references
- **JSON validity rate**: % of outputs that parse correctly
- **Option quality rate**: % with 4 unique, plausible options
- **Human preference**: A/B testing with users

### Evaluation Set
- Create 50 gold-standard questions manually
- Compare model output against gold standard
- Track improvement across iterations

---

## 8. Resources

### Models (MLX)
- LLM: `mlx-community/Qwen2.5-7B-Instruct-4bit`
- Embeddings: `mlx-community/bge-small-en-v1.5-quantized-4bit`
- Reranker: `mlx-community/bge-reranker-base` (if available)

### References
- [RAG best practices](https://www.anthropic.com/research/rag)
- [LoRA paper](https://arxiv.org/abs/2106.09685)
- [Chain-of-thought prompting](https://arxiv.org/abs/2201.11903)

---

## Next Steps

1. Review this document
2. Decide on starting phase
3. Begin implementation

*Last updated: January 2025*
