local M = {}

---Snapshot before opening any UI or starting asynchronous work.
function M.capture(context)
  local buf, range = context.buf, context.range
  if range and range.kind == "block" then
    error("Use characterwise or linewise visual mode for replacement edits")
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local snapshot = { buf = buf, tick = vim.api.nvim_buf_get_changedtick(buf), lines = lines, range = range }
  if not range then
    snapshot.text = table.concat(lines, "\n")
  elseif range.kind == "line" then
    snapshot.text = table.concat(vim.list_slice(lines, range.from[1], range.to[1]), "\n")
  else
    local last = lines[range.to[1]] or ""
    local col = math.min(range.to[2] + 1, #last)
    -- Include all bytes of the final selected UTF-8 character.
    while col < #last and last:byte(col + 1) >= 128 and last:byte(col + 1) < 192 do
      col = col + 1
    end
    snapshot.end_col = col
    snapshot.text =
      table.concat(vim.api.nvim_buf_get_text(buf, range.from[1] - 1, range.from[2], range.to[1] - 1, col, {}), "\n")
  end
  return snapshot
end

function M.decode(text)
  text = vim.trim(text)
  text = text:match("^```json%s*\n(.-)\n```$") or text
  local ok, value = pcall(vim.json.decode, text)
  if not ok or type(value) ~= "table" or type(value.replacement) ~= "string" then
    error("Expected a JSON object with a replacement string; no changes were applied")
  end
  return value.replacement
end

function M.proposed(snapshot, replacement)
  local temp = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(temp, 0, -1, false, snapshot.lines)
  local lines = vim.split(replacement, "\n", { plain = true })
  local range = snapshot.range
  if not range then
    vim.api.nvim_buf_set_lines(temp, 0, -1, false, lines)
  elseif range.kind == "line" then
    vim.api.nvim_buf_set_lines(temp, range.from[1] - 1, range.to[1], false, replacement == "" and {} or lines)
  else
    vim.api.nvim_buf_set_text(temp, range.from[1] - 1, range.from[2], range.to[1] - 1, snapshot.end_col, lines)
  end
  local result = vim.api.nvim_buf_get_lines(temp, 0, -1, false)
  vim.api.nvim_buf_delete(temp, { force = true })
  return result
end

function M.apply(snapshot, lines)
  if not vim.api.nvim_buf_is_valid(snapshot.buf) or vim.api.nvim_buf_get_changedtick(snapshot.buf) ~= snapshot.tick then
    error("Source buffer changed while the request was running; request a new edit")
  end
  vim.api.nvim_buf_set_lines(snapshot.buf, 0, -1, false, lines)
end

function M.preview(snapshot, text)
  if not vim.api.nvim_buf_is_valid(snapshot.buf) then
    error("Source buffer no longer exists; no replacement was applied")
  end
  local proposed = M.proposed(snapshot, M.decode(text))
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  local original = vim.api.nvim_get_current_buf()
  vim.bo[original].buftype = "nofile"
  vim.bo[original].bufhidden = "wipe"
  vim.bo[original].swapfile = false
  vim.api.nvim_buf_set_lines(original, 0, -1, false, snapshot.lines)
  vim.bo[original].modifiable = false
  vim.cmd("diffthis")
  vim.cmd("vnew")
  local candidate = vim.api.nvim_get_current_buf()
  vim.bo[candidate].buftype = "nofile"
  vim.bo[candidate].bufhidden = "wipe"
  vim.bo[candidate].swapfile = false
  vim.api.nvim_buf_set_lines(candidate, 0, -1, false, proposed)
  vim.bo[candidate].modifiable = false
  vim.cmd("diffthis")
  local function close()
    if vim.api.nvim_tabpage_is_valid(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      vim.cmd("tabclose!")
    end
  end
  for _, buf in ipairs({ original, candidate }) do
    vim.bo[buf].filetype = vim.bo[snapshot.buf].filetype
    vim.keymap.set("n", "da", function()
      local ok, err = pcall(M.apply, snapshot, proposed)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
        return
      end
      close()
      vim.notify("Replacement accepted in buffer; use :write to save")
    end, { buffer = buf, desc = "Accept replacement" })
    vim.keymap.set("n", "dr", close, { buffer = buf, desc = "Reject replacement" })
    vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close replacement preview" })
  end
  vim.notify("Replacement preview: da accept, dr reject. Left: original; right: replacement.")
end

return M
