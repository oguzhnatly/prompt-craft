# PromptCraft

PromptCraft is a macOS menu bar app that turns casual requests into precise AI directives.
The current system uses Recursive Meta Prompt Architecture, a staged pipeline that favors semantic density over unnecessary structure.

## What PromptCraft Delivers

1. Intent aware optimization instead of single pass rewriting.
2. Entity aware context injection that improves specificity without inflating length.
3. Complexity calibrated output that scales from compact prose to full structured specification.
4. Programmatic post processing that enforces strict output constraints for simple requests.

## Recursive Meta Prompt Architecture

PromptCraft now runs through seven runtime steps.

1. Intent Decomposer
Parses raw input into distinct action intents and urgency markers.

2. Entity Extractor
Finds people, projects, environments, technical terms, organizations, and time markers from raw input.

3. Complexity Classifier
Assigns a tier from intent count, ambiguity score, and context signal.

4. Context Engine
Retrieves semantic matches and injects learned context for specificity.

5. Prompt Assembler
Builds system and user messages with tier calibration, context block injection, and tier matched few shot examples.

6. Model Execution
Sends assembled messages to the selected provider.

7. Post Processor
Enforces word budget, removes forbidden structure in simple tiers, and blocks meta leakage.

## Key Product Behaviors

1. Simple requests remain simple.
Single intent tasks produce compact prose with no forced headers or padded sections.

2. Complex requests receive structure only when earned.
High intent count and high ambiguity inputs unlock deeper structure and broader coverage.

3. Emotional noise does not inflate complexity.
Urgency is preserved as signal while profanity and frustration are filtered from core analysis.

4. Context adds precision, not length.
Learned project and environment details are inserted into existing sentences instead of creating extra sections.

## System Requirements

1. macOS 14 or later.
2. A supported model provider configuration.
3. Valid provider credentials when required by the selected provider.

## Quick Start

```bash
git clone https://github.com/promptcraft/promptcraft.git
cd promptcraft
open PromptCraft.xcodeproj
```

Build and run from Xcode using the PromptCraft scheme.

## Testing

Run the test suite from project root.

```bash
xcodebuild test
```

## Documentation

1. Public architecture white paper: `docs/RMPA_WHITEPAPER.md`
2. Distribution guide: `docs/DISTRIBUTION.md`

## License

PromptCraft is proprietary commercial software.
See `LICENSE` for license terms and usage restrictions.
