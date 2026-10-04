# Browser operation preference

- For ordinary browser work, use Playwright MCP (`playwright`) on the **MacBook** (`shun-tagami-mbp`), in the `shun.tagami@ele-inc.com` Chrome profile. Use `playwright-info` only when the task calls for `info@ele-inc.com`.
- Before browser work, read `~/dotfiles/docs/agent-browser.md` and check `~/dotfiles/bin/agent-browser status` when the connection target is uncertain. `browser_host` must identify the MacBook. A native computer-use tool on the agent's machine may instead control the Mac mini; do not use it as a fallback for MacBook browser work.
- Proceed to the requested screen without asking the user which machine, profile, or existing tab to select. Prefer `browser_tabs` with `action: "new"` and the task URL for a new task. Reuse an existing tab only when it is the task's intended target. Verify navigation before continuing.
- The wrapper authenticates using the selected profile's token in the **MacBook's local Keychain** and opens normal Chrome if needed. Never put the token in Git, config files, tool output, or chat; never ask the user to send it in chat.
- If a connection approval page unexpectedly appears, immediately explain that this is connection setup, name the MacBook/profile and the exact action needed, and check the Keychain configuration. Do not silently wait until timeout or request selection of an unrelated tab.
- If the MacBook cannot be reached or its Keychain/extension is unavailable, report the concrete cause and recovery action. Do not silently switch to the Mac mini, another Chrome profile, or an automation-only browser. Use the Mac mini only when the user explicitly asks for it.
- For an explicitly requested Mac mini connection, use `AGENT_BROWSER_HOST=shun-tagami-mac-mini` with `agent-browser`; its own profiles and Keychain items apply.

# Image generation preference

- The user explicitly selected `gpt-image-2.5-sunburst` for image generation and editing, using the OpenAI API. Treat this as the default unless the user requests another model or route.
- Use the imagegen skill's CLI/API mode and pass `--model gpt-image-2.5-sunburst` explicitly for `generate`, `edit`, and `generate-batch`. Ensure batch job overrides also preserve the selected model.
- This is a standing preference for API mode; do not ask the user to choose the route again for each image request. Do not silently substitute another model or the built-in image tool if the API is unavailable.
- Use `~/.codex/venvs/imagegen/bin/python` with `~/.codex/skills/.system/imagegen/scripts/image_gen.py`. Read the installed imagegen skill for prompt, input-image, and output handling.
- `OPENAI_API_KEY` must be available in the process environment. Zsh loads it from `~/.config/openai/api.env` when unset. For other shells, source that file if the variable is missing. Never print its value or store it in this repository. If both are missing, ask the user to configure it locally; do not request the key in chat.
- The installed CLI currently accepts `--quality low|medium|high|auto` and, for Sunburst, `--size auto|1024x1024|1536x1024|1024x1536`. Use these supported options. Sunburst's additional API options (such as `xhigh`, `max`, and custom dimensions) require a compatible CLI; do not silently downgrade the requested model to enable them.
- For transparent output, use `--background transparent --output-format png` (or `webp`). Omit `--input-fidelity` unless current API documentation explicitly supports it for this model.
- Save final images under the user's requested location or the current project's `output/imagegen/`. Inspect the generated image and report its path and the model used.

Example (requires an API key and incurs API usage):

```sh
"$HOME/.codex/venvs/imagegen/bin/python" \
  "$HOME/.codex/skills/.system/imagegen/scripts/image_gen.py" generate \
  --model gpt-image-2.5-sunburst \
  --prompt "A watercolor illustration of a seaside town" \
  --out output/imagegen/seaside-town.png
```
