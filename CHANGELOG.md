# Changelog

All notable changes to PromptCraft are documented in this file.

## 1.1.0 2026/02/15

### Added

1. IntentDecomposer service for verb object intent extraction, emotional marker detection, urgency scoring, and cleaned input generation.
2. EntityExtractor service for persons, projects, environments, technical terms, temporal markers, and organizations.
3. PostProcessor service for word budget enforcement, simple tier structure cleanup, and meta leakage suppression.
4. Structured entity metadata fields in context entries for persons, projects, environments, and technical terms.
5. New test coverage for the full Recursive Meta Prompt Architecture pipeline.

### Changed

1. Complexity classification now uses intent count and ambiguity scoring instead of simple word count heuristics.
2. Prompt assembly now follows staged Recursive Meta Prompt Architecture flow with tier calibration injection and tier matched examples.
3. Context engine now stores structured entity metadata, applies stop phrase filtering, and prioritizes entity based cluster naming.
4. Default style system instructions were rewritten around density first behavior, strict forbidden constraints, urgency reflection, and verification checks.
5. Optimization flows in main, inline, and menu services now run through the new pipeline and post processing enforcement.

### Documentation

1. README was updated to describe the new architecture and runtime behavior.
2. A new public technical white paper was added at `docs/RMPA_WHITEPAPER.md`.

### Validation

1. Full project tests pass with 123 passing tests and zero failures.

## 1.0.0 2026/02/14

### Added

1. macOS menu bar app with global keyboard shortcut for fast access.
2. Multi provider model support for cloud and local execution.
3. Streaming optimized output view.
4. Custom style editing and style management tools.
5. Prompt history, clipboard integration, and quick optimize workflow.
6. Secure credential storage, provider validation, and configurable model settings.
7. Full onboarding, accessibility, and test coverage for core services.

### Technical

1. SwiftUI and AppKit hybrid architecture.
2. MVVM separation across views, view models, services, and models.
3. Combine based state flow.
4. Hardened runtime and app sandbox support.
