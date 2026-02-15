# PromptCraft

A macOS menu bar app that converts casual text into AI-optimized prompts. Type naturally, get perfectly structured prompts for any LLM.

## Features

- **Menu Bar Access** -- Global keyboard shortcut (Cmd+Shift+P) opens instantly from anywhere.
- **Multi-Provider** -- Works with Anthropic Claude, OpenAI GPT, and local Ollama models.
- **Streaming Output** -- Watch optimized prompts generate in real time.
- **Custom Styles** -- Build your own optimization styles with system instructions, few-shot examples, and tone controls.
- **Quick Optimize** -- Capture clipboard, optimize, copy result, and auto-close in one shortcut press.
- **History** -- Search, filter, favorite, and re-optimize past prompts.
- **Secure** -- API keys stored in macOS Keychain. Hardened Runtime. App Sandbox.

## System Requirements

- macOS 14.0 (Sonoma) or later
- An API key for Anthropic Claude or OpenAI, or a local Ollama installation

## Installation

### Download

Download the latest `PromptCraft-x.x.x.dmg` from the [Releases](https://github.com/promptcraft/promptcraft/releases) page. Open the DMG and drag PromptCraft to your Applications folder.

### Build from Source

```bash
git clone https://github.com/promptcraft/promptcraft.git
cd promptcraft
open PromptCraft.xcodeproj
```

Select the **PromptCraft** scheme, then Build & Run (Cmd+R).

## Configuration

### API Keys

1. Open PromptCraft from the menu bar.
2. Click the gear icon to open Settings.
3. Select your LLM provider (Claude, OpenAI, or Ollama).
4. Enter your API key and click the validation checkmark.

API keys are stored securely in the macOS Keychain.

### Ollama (Local)

1. Install Ollama: `brew install ollama`
2. Start the server: `ollama serve`
3. Pull a model: `ollama pull llama3`
4. Select "Ollama" in PromptCraft Settings and test the connection.

### Keyboard Shortcut

The default global shortcut is **Cmd+Shift+P**. You can change it in Settings > Keyboard Shortcut. Accessibility access is required for global shortcuts.

## Architecture

```
PromptCraft/
  App/                  # App entry point, AppDelegate (NSPopover + status item)
  Views/                # SwiftUI views (MainPopoverView, SettingsView, etc.)
  ViewModels/           # MVVM view models (MainViewModel, SettingsViewModel, etc.)
  Services/             # Business logic (LLM providers, history, styles, keychain, etc.)
  Models/               # Data models (PromptStyle, AppConfiguration, PromptHistoryEntry)
  Utilities/            # Constants, shared UI components
PromptCraftTests/       # Unit tests for models, services, and view models
scripts/                # Build and distribution scripts
docs/                   # Distribution and signing documentation
```

**Pattern**: App -> Views -> ViewModels -> Services -> Models

- **Views** are pure SwiftUI. They bind to ViewModels via `@ObservedObject`.
- **ViewModels** hold `@Published` state and call into Services.
- **Services** are singletons managing persistence, network, and system APIs.
- **Models** are `Codable` structs.

## Building for Distribution

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for the complete guide on code signing, notarization, and release.

Quick build:

```bash
# Debug build
./scripts/build.sh --debug

# Release DMG (unsigned)
./scripts/build.sh

# Signed + notarized DMG
export APPLE_ID="your@apple.id"
export APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="XXXXXXXXXX"
./scripts/build.sh --notarize
```

## Contributing

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and add tests.
4. Run the test suite: `xcodebuild test -scheme PromptCraft -destination 'platform=macOS'`
5. Commit with a clear message describing the change.
6. Open a pull request against `main`.

### Code Style

- Follow existing patterns in the codebase.
- Use MVVM: views should not contain business logic.
- Add `@Published` properties for observable state.
- Use Combine for reactive data flow.
- Write tests for new services and view model logic.

## License

PromptCraft is proprietary commercial software. All rights reserved. See [LICENSE](LICENSE) for the full license agreement. Unauthorized copying, distribution, or reverse engineering is strictly prohibited.
