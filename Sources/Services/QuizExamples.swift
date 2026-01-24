import Foundation

/// Gold-standard few-shot examples for quiz generation
/// Organized by difficulty level with diverse subject matter
enum QuizExamples {

    // MARK: - Easy Examples (Fact Recall)

    static let easyExamples: [GoldStandardExample] = [
        // History
        GoldStandardExample(
            text: "The Silk Road was an ancient network of trade routes connecting East and West, established during the Han Dynasty around 130 BCE.",
            question: "When was the Silk Road established?",
            options: ["130 BCE", "500 CE", "1200 CE", "50 BCE"],
            correctIndex: 0,
            explanation: "The Silk Road was established during the Han Dynasty around 130 BCE."
        ),
        GoldStandardExample(
            text: "Marco Polo was a Venetian merchant who traveled to China in the 13th century and wrote about his experiences in 'The Travels of Marco Polo'.",
            question: "What was Marco Polo's profession?",
            options: ["Merchant", "Soldier", "Priest", "Scholar"],
            correctIndex: 0,
            explanation: "Marco Polo was a Venetian merchant who traveled to China."
        ),
        GoldStandardExample(
            text: "The Great Wall of China was primarily built during the Ming Dynasty (1368-1644) to protect against Mongol invasions from the north.",
            question: "During which dynasty was the Great Wall of China primarily built?",
            options: ["Ming Dynasty", "Tang Dynasty", "Han Dynasty", "Qing Dynasty"],
            correctIndex: 0,
            explanation: "The Great Wall was primarily built during the Ming Dynasty (1368-1644)."
        ),
        // Science
        GoldStandardExample(
            text: "DNA, or deoxyribonucleic acid, was first identified by Friedrich Miescher in 1869, though its structure wasn't discovered until 1953 by Watson and Crick.",
            question: "Who first identified DNA in 1869?",
            options: ["Friedrich Miescher", "James Watson", "Francis Crick", "Rosalind Franklin"],
            correctIndex: 0,
            explanation: "Friedrich Miescher first identified DNA in 1869."
        ),
        GoldStandardExample(
            text: "The speed of light in a vacuum is approximately 299,792 kilometers per second, often rounded to 300,000 km/s for calculations.",
            question: "What is the approximate speed of light in a vacuum?",
            options: ["300,000 km/s", "150,000 km/s", "500,000 km/s", "1,000,000 km/s"],
            correctIndex: 0,
            explanation: "The speed of light in a vacuum is approximately 299,792 km/s, often rounded to 300,000 km/s."
        ),
        GoldStandardExample(
            text: "The human heart has four chambers: two atria (upper chambers) and two ventricles (lower chambers).",
            question: "How many chambers does the human heart have?",
            options: ["Four", "Two", "Three", "Six"],
            correctIndex: 0,
            explanation: "The human heart has four chambers: two atria and two ventricles."
        ),
        // Geography
        GoldStandardExample(
            text: "Mount Everest, located in the Himalayas on the border between Nepal and Tibet, stands at 8,849 meters (29,032 feet) above sea level.",
            question: "What is the height of Mount Everest above sea level?",
            options: ["8,849 meters", "7,200 meters", "9,500 meters", "6,800 meters"],
            correctIndex: 0,
            explanation: "Mount Everest stands at 8,849 meters (29,032 feet) above sea level."
        ),
        GoldStandardExample(
            text: "The Amazon River, flowing through South America, is the largest river by discharge volume of water in the world.",
            question: "Which river is the largest by discharge volume of water in the world?",
            options: ["Amazon River", "Nile River", "Mississippi River", "Yangtze River"],
            correctIndex: 0,
            explanation: "The Amazon River is the largest river by discharge volume of water in the world."
        ),
        // Literature
        GoldStandardExample(
            text: "William Shakespeare wrote 37 plays during his lifetime, including tragedies like Hamlet and Macbeth, and comedies like A Midsummer Night's Dream.",
            question: "How many plays did William Shakespeare write during his lifetime?",
            options: ["37", "25", "42", "50"],
            correctIndex: 0,
            explanation: "William Shakespeare wrote 37 plays during his lifetime."
        ),
        GoldStandardExample(
            text: "The novel '1984' was written by George Orwell and published in 1949, depicting a dystopian future under totalitarian rule.",
            question: "Who wrote the novel '1984'?",
            options: ["George Orwell", "Aldous Huxley", "Ray Bradbury", "H.G. Wells"],
            correctIndex: 0,
            explanation: "George Orwell wrote '1984', published in 1949."
        )
    ]

    // MARK: - Medium Examples (Concept Understanding)

    static let mediumExamples: [GoldStandardExample] = [
        // History/Politics
        GoldStandardExample(
            text: "The Tang Dynasty is considered a golden age of Chinese civilization, known for its advances in art, poetry, and technology, as well as its cosmopolitan culture that welcomed foreign traders and ideas.",
            question: "Why is the Tang Dynasty considered a golden age of Chinese civilization?",
            options: [
                "Advances in art, poetry, technology, and cosmopolitan culture",
                "Military conquests that expanded the empire to Europe",
                "Establishment of the first democratic government",
                "Discovery of new continents through naval exploration"
            ],
            correctIndex: 0,
            explanation: "The Tang Dynasty is known for its advances in art, poetry, technology, and its welcoming cosmopolitan culture."
        ),
        GoldStandardExample(
            text: "Confucianism emphasizes filial piety, respect for elders, and social harmony, which influenced Chinese governance and social structures for over two thousand years.",
            question: "Which philosophical tradition emphasized filial piety and social harmony, influencing Chinese governance for centuries?",
            options: ["Confucianism", "Daoism", "Legalism", "Buddhism"],
            correctIndex: 0,
            explanation: "Confucianism emphasizes filial piety, respect for elders, and social harmony."
        ),
        GoldStandardExample(
            text: "The Treaty of Westphalia in 1648 established the principle of state sovereignty, ending the Thirty Years' War and fundamentally reshaping international relations in Europe.",
            question: "What principle did the Treaty of Westphalia establish that reshaped European international relations?",
            options: [
                "State sovereignty",
                "Divine right of kings",
                "Balance of power",
                "Colonial expansion rights"
            ],
            correctIndex: 0,
            explanation: "The Treaty of Westphalia established the principle of state sovereignty."
        ),
        // Science
        GoldStandardExample(
            text: "Photosynthesis converts carbon dioxide and water into glucose and oxygen using sunlight energy, making it essential for producing oxygen in Earth's atmosphere.",
            question: "What role does photosynthesis play in Earth's atmosphere?",
            options: [
                "It produces oxygen essential for the atmosphere",
                "It removes excess nitrogen from the air",
                "It generates heat to warm the planet",
                "It creates ozone to block UV radiation"
            ],
            correctIndex: 0,
            explanation: "Photosynthesis converts CO2 and water into glucose and oxygen, producing oxygen essential for Earth's atmosphere."
        ),
        GoldStandardExample(
            text: "Natural selection operates on genetic variation within populations, favoring traits that increase survival and reproduction, leading to adaptation over generations.",
            question: "How does natural selection lead to adaptation in populations?",
            options: [
                "By favoring traits that increase survival and reproduction over generations",
                "By randomly mutating all genes equally",
                "By eliminating all genetic variation",
                "By allowing organisms to consciously choose beneficial traits"
            ],
            correctIndex: 0,
            explanation: "Natural selection favors traits that increase survival and reproduction, leading to adaptation over generations."
        ),
        GoldStandardExample(
            text: "Plate tectonics explains how Earth's lithosphere is divided into plates that move, collide, and separate, causing earthquakes, volcanic activity, and mountain formation.",
            question: "What geological phenomena does plate tectonics explain?",
            options: [
                "Earthquakes, volcanic activity, and mountain formation",
                "Seasonal weather patterns and ocean currents",
                "Formation of clouds and precipitation",
                "Erosion and sediment deposition"
            ],
            correctIndex: 0,
            explanation: "Plate tectonics explains earthquakes, volcanic activity, and mountain formation through plate movement."
        ),
        // Economics
        GoldStandardExample(
            text: "Inflation occurs when the general price level rises over time, reducing the purchasing power of money. Central banks often raise interest rates to combat high inflation.",
            question: "How do central banks typically respond to high inflation?",
            options: [
                "By raising interest rates",
                "By printing more money",
                "By lowering taxes",
                "By increasing government spending"
            ],
            correctIndex: 0,
            explanation: "Central banks often raise interest rates to combat high inflation by reducing spending and borrowing."
        ),
        GoldStandardExample(
            text: "The law of supply and demand states that when demand exceeds supply, prices tend to rise, and when supply exceeds demand, prices tend to fall.",
            question: "According to the law of supply and demand, what happens to prices when demand exceeds supply?",
            options: [
                "Prices tend to rise",
                "Prices tend to fall",
                "Prices remain stable",
                "Prices become unpredictable"
            ],
            correctIndex: 0,
            explanation: "When demand exceeds supply, prices tend to rise according to the law of supply and demand."
        ),
        // Technology
        GoldStandardExample(
            text: "Machine learning algorithms improve their performance through experience by identifying patterns in data, rather than being explicitly programmed with rules for every scenario.",
            question: "How do machine learning algorithms differ from traditional programming?",
            options: [
                "They learn from patterns in data rather than explicit rules",
                "They require no computational resources",
                "They can only process text data",
                "They must be reprogrammed for each new task"
            ],
            correctIndex: 0,
            explanation: "Machine learning algorithms improve by identifying patterns in data rather than being explicitly programmed."
        ),
        GoldStandardExample(
            text: "Blockchain technology creates a decentralized, immutable ledger by linking blocks of transactions cryptographically, making it resistant to tampering and central control.",
            question: "What makes blockchain technology resistant to tampering?",
            options: [
                "Cryptographically linked blocks in a decentralized ledger",
                "Centralized server storage with passwords",
                "Regular deletion of old transaction records",
                "Government regulation and oversight"
            ],
            correctIndex: 0,
            explanation: "Blockchain creates an immutable ledger by cryptographically linking blocks in a decentralized system."
        )
    ]

    // MARK: - Hard Examples (Analysis & Synthesis)

    static let hardExamples: [GoldStandardExample] = [
        // History/Politics
        GoldStandardExample(
            text: "The examination system in imperial China was both a tool for social mobility and a mechanism for reinforcing Confucian orthodoxy, as it allowed talented individuals from humble backgrounds to enter government while ensuring they adopted state-sanctioned values.",
            question: "What paradox characterized the imperial Chinese examination system's role in society?",
            options: [
                "It enabled social mobility while reinforcing ideological conformity",
                "It promoted military strength while weakening economic growth",
                "It encouraged foreign trade while isolating Chinese culture",
                "It expanded territory while reducing population"
            ],
            correctIndex: 0,
            explanation: "The examination system enabled social mobility for talented individuals while ensuring they adopted Confucian orthodoxy."
        ),
        GoldStandardExample(
            text: "The One-Child Policy, implemented in 1979, aimed to curb population growth but led to demographic imbalances including a skewed gender ratio and an aging population that now strains social services.",
            question: "What unintended demographic consequences emerged from China's One-Child Policy implemented in 1979?",
            options: [
                "Gender imbalance and an aging population straining social services",
                "Rapid urbanization and environmental degradation",
                "Increased birth rates and population explosion",
                "Economic stagnation and widespread unemployment"
            ],
            correctIndex: 0,
            explanation: "The One-Child Policy led to gender imbalance and an aging population that strains social services."
        ),
        GoldStandardExample(
            text: "The Industrial Revolution transformed not just manufacturing but also social structures, as urbanization created new class divisions between factory owners and workers, while also enabling the rise of a middle class.",
            question: "How did the Industrial Revolution reshape social hierarchies beyond economic production?",
            options: [
                "It created new class divisions while enabling middle class emergence",
                "It eliminated all social distinctions through equal wages",
                "It returned society to feudal agricultural structures",
                "It concentrated all wealth in rural landowners"
            ],
            correctIndex: 0,
            explanation: "The Industrial Revolution created new class divisions between owners and workers while enabling middle class emergence."
        ),
        // Science
        GoldStandardExample(
            text: "Antibiotic resistance evolves through natural selection when bacteria with mutations that confer resistance survive treatment and reproduce, while susceptible bacteria die off, eventually making the entire population resistant.",
            question: "What evolutionary mechanism explains the emergence of antibiotic-resistant bacteria?",
            options: [
                "Natural selection favoring bacteria with resistance mutations",
                "Bacteria consciously developing immunity",
                "Antibiotics directly modifying bacterial DNA",
                "Random chance unrelated to antibiotic exposure"
            ],
            correctIndex: 0,
            explanation: "Natural selection favors bacteria with resistance mutations, allowing them to survive and reproduce."
        ),
        GoldStandardExample(
            text: "Climate feedback loops can amplify warming: as Arctic ice melts, darker ocean water absorbs more heat, causing more melting, which in turn causes more warming in a self-reinforcing cycle.",
            question: "Why does Arctic ice melt create a self-reinforcing warming cycle?",
            options: [
                "Darker ocean water absorbs more heat than reflective ice",
                "Melting ice releases stored carbon dioxide",
                "Ocean currents reverse direction when ice disappears",
                "Ice melt increases cloud cover blocking sunlight"
            ],
            correctIndex: 0,
            explanation: "When ice melts, darker ocean water absorbs more heat than reflective ice, causing more melting and warming."
        ),
        GoldStandardExample(
            text: "Quantum entanglement allows particles to be correlated regardless of distance, leading Einstein to call it 'spooky action at a distance,' though it cannot transmit information faster than light.",
            question: "Why did Einstein describe quantum entanglement as 'spooky action at a distance'?",
            options: [
                "Particles remain correlated regardless of physical separation",
                "Particles can travel faster than light speed",
                "Observers can predict particle behavior perfectly",
                "Particles communicate through hidden channels"
            ],
            correctIndex: 0,
            explanation: "Entangled particles remain correlated regardless of distance, which seemed to imply instantaneous connection."
        ),
        // Philosophy/Ethics
        GoldStandardExample(
            text: "Utilitarianism judges actions by their consequences, specifically by how much happiness or suffering they produce, which can conflict with rights-based ethics that hold certain actions as wrong regardless of outcomes.",
            question: "What fundamental tension exists between utilitarianism and rights-based ethics?",
            options: [
                "Utilitarianism allows harmful acts if they maximize overall happiness",
                "Rights-based ethics ignores all consequences of actions",
                "Utilitarianism requires perfect knowledge of the future",
                "Rights-based ethics prohibits all forms of happiness"
            ],
            correctIndex: 0,
            explanation: "Utilitarianism judges by consequences, potentially allowing harmful acts if they maximize happiness, conflicting with rights-based ethics."
        ),
        // Technology/Society
        GoldStandardExample(
            text: "Social media algorithms optimize for engagement by promoting content that triggers strong emotional reactions, which researchers have linked to increased polarization as users are shown increasingly extreme content.",
            question: "What mechanism links social media algorithms to political polarization?",
            options: [
                "Algorithms promote emotionally triggering content, leading to exposure to extreme views",
                "Social media bans all moderate political content",
                "Users consciously seek out only extreme viewpoints",
                "Algorithms randomly distribute political content"
            ],
            correctIndex: 0,
            explanation: "Algorithms optimize for engagement by promoting emotionally triggering content, exposing users to increasingly extreme views."
        ),
        GoldStandardExample(
            text: "The 'tragedy of the commons' occurs when individuals acting in self-interest deplete shared resources, even when cooperation would benefit everyone, highlighting the tension between individual and collective rationality.",
            question: "What does the 'tragedy of the commons' reveal about the relationship between individual and collective interests?",
            options: [
                "Individual self-interest can harm collective well-being even when cooperation benefits all",
                "Collective action always produces optimal outcomes for individuals",
                "Private ownership eliminates all resource management problems",
                "Shared resources are always managed sustainably"
            ],
            correctIndex: 0,
            explanation: "The tragedy shows that individual self-interest can deplete shared resources even when cooperation would benefit everyone."
        ),
        GoldStandardExample(
            text: "The Turing Test proposes that if a machine can converse indistinguishably from a human, it demonstrates intelligence, though critics argue this measures imitation rather than genuine understanding.",
            question: "What criticism challenges the Turing Test as a measure of machine intelligence?",
            options: [
                "It measures imitation ability rather than genuine understanding",
                "It requires machines to have human-like physical bodies",
                "It can only be administered in English language",
                "It has never been successfully passed by any machine"
            ],
            correctIndex: 0,
            explanation: "Critics argue the Turing Test measures imitation of human conversation rather than genuine understanding."
        )
    ]

    // MARK: - Distractor Generation Guidelines

    static let distractorGuidelines = """
    DISTRACTOR QUALITY RULES:
    1. SAME TYPE: All options must be the same category (all dates, all names, all concepts)
    2. PLAUSIBLE: Distractors should be believable, not obviously wrong
    3. DISTINCT: Each option should be clearly different from others
    4. NO TRICKS: Avoid "all of the above" or "none of the above"
    5. SIMILAR LENGTH: Options should have comparable length

    GOOD DISTRACTORS:
    - For dates: Use nearby time periods (same century or era)
    - For names: Use related figures from the same field/period
    - For concepts: Use common misconceptions or related but different ideas
    - For numbers: Use values in the same order of magnitude

    BAD DISTRACTORS TO AVOID:
    - Obviously wrong answers ("The year 1 million BCE")
    - Unrelated topics ("A type of cheese" when asking about history)
    - Near-duplicates of the correct answer
    - Joke answers or absurd options
    """

    // MARK: - Helper Methods

    static func getExamples(for difficulty: QuizDifficulty) -> [GoldStandardExample] {
        switch difficulty {
        case .easy: return easyExamples
        case .medium: return mediumExamples
        case .hard: return hardExamples
        }
    }

    static func formatExamplesForPrompt(difficulty: QuizDifficulty, count: Int = 3) -> String {
        let examples = getExamples(for: difficulty)
        let selected = examples.shuffled().prefix(count)

        var result = "GOLD-STANDARD EXAMPLES:\n\n"

        for (index, example) in selected.enumerated() {
            result += """
            Example \(index + 1):
            Text: "\(example.text)"
            Output: {"question": "\(example.question)", "options": \(formatOptions(example.options)), "correctIndex": \(example.correctIndex), "explanation": "\(example.explanation)"}

            """
        }

        result += "\n\(distractorGuidelines)\n"

        return result
    }

    private static func formatOptions(_ options: [String]) -> String {
        let escaped = options.map { "\"\($0)\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }
}

// MARK: - Supporting Types

struct GoldStandardExample {
    let text: String
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
}
