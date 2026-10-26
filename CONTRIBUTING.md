# Contributing to opencode.nvim

Fork author and maintainer: **yigrip**. This fork focuses on an entirely Neovim-based assistant:
background OpenCode service, native answers and edit review, and local Rust crate context.
Keep the public `opencode` Lua namespace compatible. Preserve upstream attribution.

Run `nvim --headless -u NONE -l tests/run.lua`, `stylua --check .`, and the
LuaLS check described in AGENTS.md before submitting changes.
