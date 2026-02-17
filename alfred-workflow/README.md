# PromptCraft Alfred Workflow

Optimize prompts from Alfred using your local PromptCraft app.

## Prerequisites

- PromptCraft running with **Local API** enabled (Settings > Behavior > Local API Server)
- Alfred with Powerpack

## Setup

1. Open Alfred Preferences > Workflows
2. Create a new **Blank Workflow** named "PromptCraft"
3. Add a **Script Filter** input:
   - Keyword: `pc` (or your choice)
   - Language: `/bin/bash`
   - Paste the contents of `optimize.sh` as the script
4. Add a **Copy to Clipboard** output connected to the Script Filter
   - Set it to copy `{query}`
5. Set environment variables in the workflow configuration:
   - `PROMPTCRAFT_TOKEN` — your bearer token (copy from PromptCraft Settings)
   - `PROMPTCRAFT_PORT` — server port (default: `9847`)

## Usage

1. Open Alfred and type `pc your prompt text here`
2. Press **Enter** to copy the optimized result to your clipboard

## Troubleshooting

- **"PromptCraft not running"** — Make sure PromptCraft is open and Local API is enabled
- **"Missing API token"** — Set `PROMPTCRAFT_TOKEN` in the workflow environment variables
- **401 errors** — Regenerate the token in PromptCraft Settings and update the workflow variable
