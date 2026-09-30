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
