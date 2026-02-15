import Foundation

final class PromptAssembler {
    static let shared = PromptAssembler()

    /// Approximate characters per token for English text.
    private let charsPerToken: Double = 4.0

    private init() {}

    // MARK: - Public API

    struct AssembledPrompt {
        let systemMessage: String
        let messages: [LLMMessage]
        let estimatedTokenCount: Int
        let wasTruncated: Bool
        let contextBlock: String?
        let contextEntryCount: Int
    }

    /// Assembles a full prompt from the user's raw input and the selected style.
    ///
    /// - Parameters:
    ///   - rawInput: The user's raw text to optimize.
    ///   - style: The PromptStyle to apply.
    ///   - providerType: The target provider (affects formatting hints).
    ///   - maxContextTokens: Maximum context tokens for the model (used for truncation).
    ///   - complexityTier: The detected complexity tier for output calibration.
    ///   - maxOutputWords: The computed word limit for the output.
    /// - Returns: An assembled prompt with system message, messages array, and metadata.
    func assemble(
        rawInput: String,
        style: PromptStyle,
        providerType: LLMProvider,
        maxContextTokens: Int = 100_000,
        contextBlock: String? = nil,
        contextEntryCount: Int = 0,
        complexityTier: ComplexityTier = .complex,
        maxOutputWords: Int = 800
    ) -> AssembledPrompt {
        let systemMessage = buildSystemMessage(style: style, providerType: providerType, contextBlock: contextBlock, complexityTier: complexityTier, maxOutputWords: maxOutputWords)
        let userMessage = buildUserMessage(rawInput: rawInput)

        let systemTokens = estimateTokens(systemMessage)
        let userTokens = estimateTokens(userMessage)
        let reservedOutputTokens = 4096

        let availableForExamples = maxContextTokens - systemTokens - userTokens - reservedOutputTokens
        let (fewShotMessages, wasTruncated) = buildFewShotMessages(
            examples: style.fewShotExamples,
            availableTokens: max(0, availableForExamples)
        )

        var allMessages: [LLMMessage] = []
        allMessages.append(contentsOf: fewShotMessages)
        allMessages.append(LLMMessage(role: .user, content: userMessage))

        let totalTokens = systemTokens + fewShotMessages.reduce(0) { $0 + estimateTokens($1.content) } + userTokens

        return AssembledPrompt(
            systemMessage: systemMessage,
            messages: allMessages,
            estimatedTokenCount: totalTokens,
            wasTruncated: wasTruncated,
            contextBlock: contextBlock,
            contextEntryCount: contextEntryCount
        )
    }

    /// Estimates the token count for a given text.
    func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    // MARK: - System Message Construction

    private func buildSystemMessage(style: PromptStyle, providerType: LLMProvider, contextBlock: String? = nil, complexityTier: ComplexityTier = .complex, maxOutputWords: Int = 800) -> String {
        var parts: [String] = []

        // Output calibration directive — injected FIRST, before all style rules
        parts.append(buildCalibrationDirective(for: complexityTier, maxOutputWords: maxOutputWords))

        // Core role definition
        parts.append("""
        You are a prompt optimization engine. Your sole job is to take casual, unstructured text \
        and transform it into the most EFFECTIVE AI prompt possible — where effectiveness means \
        MAXIMUM IMPACT PER WORD. You must preserve the user's original intent completely — never \
        add goals, requirements, or assumptions the user did not express. Where the user was vague, \
        add specificity by inferring reasonable constraints. A 15-word prompt that perfectly captures \
        intent is superior to a 200-word prompt that dilutes intent with structure. Structure is a \
        tool, not a goal — use it only when the input's complexity demands it.
        """)

        // Style-specific transformation rules
        if !style.systemInstruction.isEmpty {
            parts.append("## Transformation Rules\n\(style.systemInstruction)")
        }

        // Output structure guidance — only inject for moderate/complex tiers
        if !style.outputStructure.isEmpty && (complexityTier == .moderate || complexityTier == .complex) {
            let sections = style.outputStructure.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            parts.append("## Target Output Structure\nFor complex inputs that warrant structure, the optimized prompt may organize into these sections:\n\(sections)\nDo NOT use these sections for simple inputs — write dense prose instead.")
        }

        // Tone guidance
        if !style.toneDescriptor.isEmpty {
            parts.append("## Tone\nThe optimized prompt should convey a \(style.toneDescriptor) tone.")
        }

        // Prefix / suffix instructions
        if let prefix = style.enforcedPrefix, !prefix.isEmpty {
            parts.append("## Enforced Prefix\nThe optimized prompt MUST begin with:\n\(prefix)")
        }
        if let suffix = style.enforcedSuffix, !suffix.isEmpty {
            parts.append("## Enforced Suffix\nThe optimized prompt MUST end with:\n\(suffix)")
        }

        // Model-specific formatting hints — only for moderate/complex tiers
        if complexityTier == .moderate || complexityTier == .complex {
            let formattingHint: String
            switch providerType {
            case .anthropicClaude:
                formattingHint = "When the input's complexity warrants structure, use XML tags (e.g., <context>, <task>, <constraints>) for organization in the optimized prompt."
            case .openAI:
                formattingHint = "When the input's complexity warrants structure, use markdown headers (##) for organization in the optimized prompt."
            case .ollama:
                formattingHint = "When the input's complexity warrants structure, use markdown headers (##) for organization in the optimized prompt."
            case .custom:
                formattingHint = "When the input's complexity warrants structure, use clear formatting (headers, lists) in the optimized prompt."
            case .promptCraftCloud:
                formattingHint = "When the input's complexity warrants structure, use XML tags (e.g., <context>, <task>, <constraints>) for organization in the optimized prompt."
            }
            parts.append("## Formatting\n\(formattingHint)")
        }

        // Inject context block if available
        if let contextBlock {
            parts.append("## Prior Context\nUse this context from the user's previous optimizations to make the output MORE SPECIFIC, not LONGER. If context tells you the user works on a Go microservice called auth-service, inject \"in the auth-service Go module\" — that's a few words of massive value. Do NOT use context as an excuse to add sections or structure. Never reference the context block directly in your output.\n\n\(contextBlock)")
        }

        // Hard rule: output only the prompt
        parts.append("""
        ## Critical Rule
        Output ONLY the optimized prompt. No preamble, no explanation, no "Here's your optimized \
        prompt:" — just the prompt itself, ready to be pasted directly into an AI chat.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Output Calibration

    private func buildCalibrationDirective(for tier: ComplexityTier, maxOutputWords: Int) -> String {
        let antiPadding = """
        ABSOLUTE PROHIBITIONS: \
        NEVER add an "Output Format" section unless the user explicitly asked for a specific format. \
        NEVER add a "Constraints" section that restates obvious things ("be accurate" — assumed). \
        NEVER add a "Context" section that just paraphrases the user's input. \
        NEVER split a single concern into multiple numbered requirements. \
        NEVER add sections (Immediate Actions, Environment Consistency, Escalation Path) the user didn't mention. \
        NEVER use ## headers for outputs under 150 words. \
        When input contains strong emotions (profanity, urgency), extract the technical intent and \
        discard the emotional wrapper. Do NOT add "maintain professional tone" constraints — that is patronizing.
        """

        let quality = """
        Even short outputs must be precision-engineered — every word chosen to maximize AI \
        comprehension. Replace vague verbs with specific ones ("fix" → "identify and correct", \
        "make" → "implement", "change" → "refactor ... to"). Add implicit constraints the user \
        assumed but didn't state. Specify scope precisely. A short output is NOT a low-effort \
        paraphrase — it is a surgically crafted directive.
        """

        switch tier {
        case .trivial:
            return """
            ## Output Calibration — TIER 1 (TRIVIAL)
            HARD CONSTRAINT — OUTPUT LENGTH LIMIT: Your response MUST be 1-2 sentences, MAXIMUM \(maxOutputWords) words.
            Do NOT use headers (##), bullet points, numbered lists, bold text, or any structural formatting.
            Write a single dense paragraph or 1-2 sentences. If you find yourself writing a third sentence, STOP and compress.
            The user's input is simple — respect that simplicity. An over-engineered response for a simple request is WORSE than no optimization at all.
            Repeat: MAXIMUM \(maxOutputWords) words, NO formatting, 1-2 sentences.
            \(quality)
            \(antiPadding)
            """

        case .simple:
            return """
            ## Output Calibration — TIER 2 (SIMPLE)
            HARD CONSTRAINT — OUTPUT LENGTH LIMIT: Your response MUST be under \(maxOutputWords) words.
            You may use up to 3 numbered items if the input has distinct sub-tasks, but NO headers (##), NO bold emphasis, \
            NO 'Output Format' or 'Constraints' sections. Write as concise prose or a very short numbered list.
            If your response exceeds \(maxOutputWords) words, you are over-engineering. Compress.
            \(quality)
            \(antiPadding)
            """

        case .moderate:
            return """
            ## Output Calibration — TIER 3 (MODERATE)
            OUTPUT GUIDANCE: Target \(maxOutputWords) words. You may use light headers if the input has 3+ genuinely distinct concerns.
            Each section should be 2-4 sentences max. Do not add sections the user did not request.
            \(antiPadding)
            """

        case .complex:
            return """
            ## Output Calibration — TIER 4 (COMPLEX)
            OUTPUT GUIDANCE: This is a complex request. Use full structured formatting with clear sections.
            Target \(maxOutputWords) words. Cover all dimensions the user raised.
            Even in complex mode, every section must earn its place — do not add empty or obvious sections.
            """
        }
    }

    // MARK: - User Message

    private func buildUserMessage(rawInput: String) -> String {
        return "<raw_prompt>\n\(rawInput)\n</raw_prompt>"
    }

    // MARK: - Few-Shot Examples

    /// Builds few-shot messages from the style's examples, truncating from the end if needed.
    private func buildFewShotMessages(
        examples: [FewShotExample],
        availableTokens: Int
    ) -> (messages: [LLMMessage], wasTruncated: Bool) {
        guard !examples.isEmpty else { return ([], false) }

        var messages: [LLMMessage] = []
        var usedTokens = 0
        var includedCount = 0

        for example in examples {
            let userContent = "<raw_prompt>\n\(example.input)\n</raw_prompt>"
            let assistantContent = example.output
            let exampleTokens = estimateTokens(userContent) + estimateTokens(assistantContent)

            if usedTokens + exampleTokens > availableTokens {
                break
            }

            messages.append(LLMMessage(role: .user, content: userContent))
            messages.append(LLMMessage(role: .assistant, content: assistantContent))
            usedTokens += exampleTokens
            includedCount += 1
        }

        let wasTruncated = includedCount < examples.count
        return (messages, wasTruncated)
    }
}
