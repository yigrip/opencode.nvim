# opencode.nvim

Focused AI actions in Neovim, backed by **OpenCode v2**. Ask a question or request
a replacement for selected code. Without a selection, the action targets the
whole current buffer. Every action starts an independent conversation.

**Fork author and maintainer: yigrip.**

Inspired by 99's action-oriented workflow and based on the
[upstream project](https://github.com/nickjvandyke/opencode.nvim).
The Lua namespace remains `opencode`.

## Requirements

- Neovim 0.11+ (tested with 0.12), `curl`, and OpenCode **v2**.
- The installer path `~/.opencode/bin/opencode` is detected if absent from PATH.
- `cargo` for automatic local Rust crate discovery.

Connect your OpenCode Go account once using OpenCode's `/connect` and select a Go
model with `/models`. The plugin uses OpenCode's credentials and model settings;
never put API keys in your Neovim config. No TUI is needed during plugin use.

## Local installation with lazy.nvim

```lua
return {
  dir = vim.fn.expand("~/dev/personal/nvim/opencode.nvim"),
  config = function()
    vim.g.opencode_opts = {}
    vim.keymap.set({ "n", "x" }, "<leader>aa", function()
      require("opencode").ask()
    end, { desc = "Ask about selection or file" })
    vim.keymap.set({ "n", "x" }, "<leader>ae", function()
      require("opencode").edit()
    end, { desc = "Replace selection or file" })
    vim.keymap.set({ "n", "x" }, "<leader>as", function()
      require("opencode").select()
    end, { desc = "AI actions" })
    vim.keymap.set("n", "<leader>ao", function()
      require("opencode").output()
    end, { desc = "Reopen latest result" })
  end,
}
```

After publishing, you can replace `dir = ...` with `"yigrip/opencode.nvim"`.
Do not load both forks at once; their module namespaces overlap.
Run `:checkhealth opencode` after installation.

## Ask

Select code with `v` or `V` and press `<leader>aa`, or use it in normal mode for
the entire file. Ask for an explanation, expected output, or generated code.
The answer streams into a temporary Markdown buffer without moving editor focus.
Press `q` inside that buffer to close it; `<leader>ao` reopens the latest result.

Questions do not automatically edit files. To request an applied change, use
`edit()` instead. `prompt(text)` submits a question directly without opening input.

## Edit

Select code and press `<leader>ae`, then describe the desired behavior. Normal
mode targets the entire buffer. You can also call
`require("opencode").edit("Handle empty input")` with a prompt directly.

The agent reads relevant context and returns replacement text. Once complete,
a new tab shows a side-by-side diff of the original and proposed buffer:

- `da`: accept the replacement into the source buffer.
- `dr` or `q`: reject/close without changing the source.
- `]c` / `[c`: move between diff hunks.

Acceptance is one buffer edit, undoable with `u`. It does not write the file;
use `:write` when ready. Text outside a selection remains unchanged. The plugin
rejects acceptance if the source buffer changed while the request was running.
Malformed agent responses are never applied. Characterwise and linewise selections
are supported; blockwise replacement requests are rejected with an explanation.

The action picker routes edit/document/fix/implement/optimize through replacement
previews. Explain/review/test return answers; test generation is a suggestion.
This is focused buffer editing, not an autonomous multi-file editing workflow.

## Context and independent requests

Each request creates a fresh OpenCode session. No history carries into the next
request, even for the same file. Old sessions remain stored in OpenCode but are
not automatically resumed. Results stay in Neovim memory until exit.

`@this` is the selection, or the whole file when nothing is selected. `@buffer`
always refers to the whole buffer. A prompt without a context placeholder gets
`@this` automatically. Unsaved contents are supplied inline. Edit actions include
an exact snapshot of their target and apply only after review.

For ask/edit actions, built-in file edits, shell execution, subagents, and question
tools are denied in the session. The model can use source-reading tools; respond
to any remaining permission requests in Neovim. Local acceptance applies the
replacement. Registered `command()` calls are an advanced interface and do not
use the ask/edit replacement pipeline.

The plugin starts the shared service using `opencode service start` if needed,
without opening a terminal or browser. The service remains running after Neovim
exits. Explicit `server.url` and `server.password` options are also supported.
Keep `server.connect` and `events.enabled` enabled for results and permissions.

## Local Rust crates

Cargo metadata runs asynchronously with `--offline --locked`, locating workspace
members and local path dependencies, including local transitive crates when full
resolution succeeds. Their source directories are included in the prompt and
given session-scoped read and external-directory access. This lets the agent
inspect related code instead of uploading every source file on each request.

If offline resolution fails, `--no-deps` still discovers workspace members and
their direct path dependencies. The prompt identifies this limitation and points
to the manifest so the agent can follow other dependencies as permissions allow.
Cargo is never used to compile, fetch dependencies, or update Cargo.lock.
Registry and Git sources do not receive automatic local-crate grants.

Disable this feature with `vim.g.opencode_opts = { rust = { enabled = false } }`.
Remote OpenCode servers need the same filesystem paths to use these references.

## Development

```sh
nvim --headless -u NONE -i NONE -l tests/run.lua
stylua --check .
lua-language-server --configpath .luarc.ci.json --check=.
```

Tests cover context, independent sessions, streaming, replacement ranges, review,
stale-buffer rejection, and Cargo discovery. Live API checks need OpenCode v2;
a live model request is separate. Optional Snacks/Blink integration is retained.
See LICENSE for upstream attribution and CHANGELOG.md for history.

## Releases

CI checks `main` and pull requests. Publish a stable version by pushing a tag
like `v1.0.3`; the release workflow creates its GitHub Release using the built-in
workflow token. No personal access token or release-PR approval permission is needed.
The workflow can also be run manually for an existing version tag.

Install from GitHub with `"yigrip/opencode.nvim"`, `branch = "main"`, and
`version = false` in your lazy.nvim spec. `lazy-lock.json` pins the installed
commit. Once version tags exist, use `version = "*"` instead of `branch` to track
stable releases.
