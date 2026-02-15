# Changelog

All notable changes to PromptCraft will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-14

### Added
- Menu bar app with global keyboard shortcut (Cmd+Shift+P) for instant access.
- Multi-provider LLM support: Anthropic Claude, OpenAI GPT, and local Ollama.
- Streaming response display with real-time token output.
- 6 built-in prompt optimization styles: Professional, Technical, Creative, Concise, Academic, and Friendly.
- Custom style editor with full control over system instructions, few-shot examples, tone, and output sections.
- Style management: create, edit, duplicate, reorder, enable/disable, import/export.
- AI-assisted style generation from natural language descriptions.
- Prompt history with search, filtering by style, favorites, and date grouping.
- Re-optimize from history with one click.
- Clipboard integration: auto-capture on shortcut, auto-copy results.
- Quick Optimize mode: capture clipboard, optimize, copy result, auto-close.
- Selected text capture via simulated Cmd+C (requires accessibility access).
- Secure API key storage in macOS Keychain.
- API key validation with provider-specific error messages.
- Configurable LLM parameters: temperature, max output tokens, model selection.
- Dynamic model listing from each provider's API.
- Network connectivity monitoring with offline state handling.
- Comprehensive error handling with actionable suggestions and provider fallback hints.
- Long input warning (50k+ characters) with user confirmation.
- Partial response recovery on stream interruption.
- Task cancellation during optimization.
- Launch at login via ServiceManagement.
- Theme support: System, Light, and Dark modes.
- Sound on completion (optional).
- Character count display (optional).
- Guided onboarding flow for first-time users.
- Contextual hints for discovering features.
- Configuration export/import as JSON.
- Debug log viewer with copy-to-clipboard.
- Full test suite: models, services, view models, and provider integration.
- Accessibility labels and keyboard navigation throughout.

### Technical
- SwiftUI + AppKit hybrid architecture (NSPopover for menu bar).
- MVVM pattern: Views, ViewModels, Services, Models.
- Combine-based reactive state management.
- macOS 14+ (Sonoma) deployment target.
- Hardened Runtime enabled.
- App Sandbox with network client entitlement.
