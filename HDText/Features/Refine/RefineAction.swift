import Foundation

enum RefineAction: String, CaseIterable, Identifiable {
    case elaborate
    case polish
    case shorten
    case formalize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elaborate:  return "Elaborate"
        case .polish:     return "Polish"
        case .shorten:    return "Shorten"
        case .formalize:  return "Formalize"
        }
    }

    var menuTitle: String {
        "HD Text - \(displayName)"
    }

    var systemPrompt: String {
        let base = """
        You are a text editor. You receive a piece of text and transform it according to the instructions below.

        STRICT RULES:
        - NEVER add new facts, claims, or information the original text does not contain.
        - NEVER change the author's intent, position, or core meaning.
        - ALWAYS preserve: names, numbers, technical terms, negations, links, and code.
        - Output ONLY the transformed text. No preamble, no explanation, no quotes.
        """

        switch self {
        case .elaborate:
            return base + """

            TASK: ELABORATE
            - Expand the text with more detail, examples, or clarification.
            - Flesh out ideas that are only hinted at.
            - Keep the original structure and tone.
            - Do NOT pad with generic filler — every added sentence should carry real information.
            """

        case .polish:
            return base + """

            TASK: POLISH
            - Improve grammar, word choice, and sentence flow.
            - Fix awkward phrasing and improve readability.
            - Keep the length roughly the same.
            - Preserve the author's voice and tone.
            """

        case .shorten:
            return base + """

            TASK: SHORTEN
            - Make the text more concise.
            - Remove redundancy, filler, and unnecessary words.
            - Preserve all key information and meaning.
            - Aim for roughly 50-70% of the original length.
            """

        case .formalize:
            return base + """

            TASK: FORMALIZE
            - Rewrite in a more professional, formal tone.
            - Replace casual language, slang, and contractions.
            - Keep the length and content roughly the same.
            - Make it suitable for business or academic contexts.
            """
        }
    }
}
