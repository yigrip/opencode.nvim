local M = {}
local chats = {}
local current

local function render(chat)
  if not chat.buf or not vim.api.nvim_buf_is_valid(chat.buf) then
    chat.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[chat.buf].filetype = "markdown"
    vim.bo[chat.buf].bufhidden = "hide"
    vim.bo[chat.buf].swapfile = false
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = chat.buf, silent = true })
  end
  local text = table.concat(chat.entries, "\n\n")
  for _, key in ipairs(chat.order) do
    text = text .. "\n\n" .. chat.parts[key]
  end
  vim.bo[chat.buf].modifiable = true
  vim.api.nvim_buf_set_lines(chat.buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[chat.buf].modifiable = false
end

function M.show()
  local chat = current and chats[current]
  if not chat then
    vim.notify("No OpenCode answers yet")
    return
  end
  render(chat)
  if vim.fn.bufwinid(chat.buf) == -1 then
    local source = vim.api.nvim_get_current_win()
    vim.cmd("botright vsplit")
    vim.api.nvim_win_set_buf(0, chat.buf)
    vim.wo.wrap = true
    vim.api.nvim_set_current_win(source)
  end
end

function M.begin(session, prompt, complete)
  current = session
  local chat = chats[session] or { entries = {}, parts = {}, order = {} }
  chats[session] = chat
  chat.complete = complete
  for _, key in ipairs(chat.order) do
    table.insert(chat.entries, chat.parts[key])
  end
  chat.parts, chat.order = {}, {}
  table.insert(chat.entries, "## You\n\n" .. prompt .. "\n\n## Assistant")
  if not complete then
    M.show()
  end
end

function M.event(event)
  local data = event.data or {}
  local chat = chats[data.sessionID]
  if not chat then
    return
  end
  if event.type == "session.text.delta" or event.type == "session.text.ended" then
    local key = tostring(data.assistantMessageID) .. ":" .. tostring(data.ordinal)
    if not chat.parts[key] then
      table.insert(chat.order, key)
      chat.parts[key] = ""
    end
    if event.type == "session.text.ended" then
      chat.parts[key] = data.text or chat.parts[key]
    else
      chat.parts[key] = chat.parts[key] .. (data.delta or "")
    end
    if not chat.complete then
      render(chat)
    end
  elseif event.type == "session.execution.succeeded" and not chat.finished then
    chat.finished = true
    if chat.complete then
      -- The final text segment is the result; earlier segments may be progress notes.
      local last = chat.order[#chat.order]
      local ok, err = pcall(chat.complete, last and chat.parts[last] or "")
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
        M.show()
      end
    end
  elseif event.type == "session.execution.failed" then
    table.insert(chat.entries, "**OpenCode failed:** " .. vim.inspect(data.error or data))
    chat.finished = true
    render(chat)
    vim.notify("OpenCode action failed", vim.log.levels.ERROR)
  end
end

return M
