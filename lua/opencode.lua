---opencode.nvim public API.
local M = {}

---@param err? string
local function on_error(err)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
  end
end

---Input a prompt for OpenCode.
---
--- - Passes the text to `prompt()`.
--- - Press `<Up>` to browse recent asks.
--- - Highlights and completes contexts.
---   - Press `<Tab>` to trigger built-in completion.
---   - Provided by in-process LSP when using [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---
---@param default? string Text to pre-fill the input with.
function M.ask(default)
  local context = require("opencode.context").new(nil)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      context.server = server
      return require("opencode.ui.ask").ask(default or "@this: ", context):next(function(input)
        return require("opencode.api.prompt").prompt(input, context)
      end)
    end)
    :catch(on_error)
end

---Request a focused replacement. With no selection, replace the whole buffer.
---@param instruction? string Omit to open the prompt input.
function M.edit(instruction)
  local context = require("opencode.context").new(nil)
  local ok, snapshot = pcall(require("opencode.ui.replacement").capture, context)
  if not ok then
    context:clear()
    on_error(tostring(snapshot))
    return
  end
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      context.server = server
      local input = instruction and require("opencode.promise").resolve(instruction)
        or require("opencode.ui.ask").ask("", context)
      return input:next(function(text)
        return require("opencode.api.prompt").prompt(text, context, snapshot)
      end)
    end)
    :catch(function(err)
      context:clear()
      on_error(err)
    end)
end

---Select from all opencode.nvim functionality.
---
---Highlights and previews items when using [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  local context = require("opencode.context").new(nil)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      context.server = server
      return require("opencode.ui.select").select(context, opts)
    end)
    :catch(on_error)
end

M.statusline = require("opencode.events.status").statusline

---Prompt OpenCode.
---
---Starts a fresh independent session.
---Injects configured contexts.
---Trailing "..." opens in `ask()`.
---
---@param prompt string
function M.prompt(prompt)
  local context = require("opencode.context").new(nil)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      context.server = server
      return require("opencode.api.prompt").prompt(prompt, context)
    end)
    :catch(on_error)
end

---Run a registered OpenCode [command](https://opencode.ai/v2/docs/commands/).
---Starts a fresh independent session.
---
---@param command string
---@param text? string Arguments for the command.
function M.command(command, text)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return require("opencode.api.command").command(command, text or "", server)
    end)
    :catch(on_error)
end

---Wraps `prompt` as an operator, supporting ranges and dot-repeat.
---
---@param prompt string
function M.operator(prompt)
  _G.opencode_prompt_operator = function(kind) ---@param kind "char" | "line" | "block"
    local start_pos = vim.api.nvim_buf_get_mark(0, "[")
    local end_pos = vim.api.nvim_buf_get_mark(0, "]")
    if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
      start_pos, end_pos = end_pos, start_pos
    end

    require("opencode.server.discovery")
      .get()
      :next(function(server)
        local context = require("opencode.context").new(server, {
          from = { start_pos[1], start_pos[2] },
          to = { end_pos[1], end_pos[2] },
          kind = kind,
        })

        return require("opencode.api.prompt").prompt(prompt, context)
      end)
      :catch(on_error)
  end

  vim.o.operatorfunc = "v:lua.opencode_prompt_operator"
  return "g@"
end

---Choose and persist a model for future independent actions.
function M.select_model()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return require("opencode.models").select(server)
    end)
    :catch(on_error)
end

---Reopen the current session's answer buffer.
function M.output()
  require("opencode.ui.output").show()
end

M.format = require("opencode.context").format

return M
