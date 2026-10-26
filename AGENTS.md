# opencode.nvim — agent guide

Fork author and maintainer: yigrip. Preserve upstream
copyright and historical attribution. Maintain the `opencode` Lua namespace.
Use `yigrip` in current fork author and maintainer credits. Preserve original
license notices and historical source references. Keep actual repository
identifiers and contact details accurate.

## Product behavior

- No terminal/TUI/browser opens during normal plugin use.
- Start OpenCode v2 using `opencode service start`; also detect its installer path.
- Create a fresh plugin-owned session for every action; never reuse conversations.
- Ask about the visual selection, or the full file when there is no selection.
- Stream answers into a Markdown scratch buffer without taking editor focus.
- Discover Rust workspace/path crates with offline, locked Cargo metadata.
- Add local source paths to prompts and session read permissions. Ask/edit deny agent
  file writes and shell/subagent execution. Edit results use a local replacement preview.

## Architecture

- `lua/opencode.lua`: public API; config uses `vim.g.opencode_opts`, no setup().
- `server/background.lua`: CLI discovery and headless service startup.
- `server/discovery/init.lua`: registered service discovery, missing-directory handling,
  configured URL override, 30-second startup polling.
- `server/init.lua`: v2 REST/SSE transport, HTTP basic auth, directory-scoped
  requests, session creation. API session-create responses wrap the session in `data`.
- `context/init.lua` / `builtins.lua`: editor context capture and rendering.
- `context/rust.lua`: asynchronous Cargo metadata, local crate context and permissions.
- `ui/replacement.lua`: exact target snapshots, JSON result decoding, side-by-side
  preview, accept/reject, and changedtick checks. Acceptance updates only the buffer.
- `api/prompt.lua`: prompt context, Rust discovery, session permissions, submission.
- `ui/output.lua`: per-session text segments keyed by assistant message and ordinal;
  final text replaces deltas to avoid duplicates. `output()` reopens the latest buffer.
- `events/init.lua`: dispatch events only for plugin-owned sessions.
- `plugin/events/`: existing permission/edit review, reload, and status handlers.

OpenCode v2 uses `/api/*`, shared service registration in its state directory,
`{ id, type, data }` events, and permission rules `{ action, resource, effect }`.
Do not substitute v1 endpoints or permission schemas. Credentials stay in OpenCode.
The background service persists after Neovim exits. No mandatory Lua dependencies;
Snacks and Blink integrations are optional.

## Checks

```sh
nvim --headless -u NONE -i NONE -l tests/run.lua
stylua --check .
lua-language-server --configpath .luarc.ci.json --check=.
```

LuaLS CI paths point to `/opt`; use a temporary local config for other installations.
StyLua uses two spaces, double quotes, and a 120-column limit.
Tests use mocked transport/Cargo responses. Live API verification requires OpenCode
v2; do not print credentials or submit paid model prompts merely to test transport.
