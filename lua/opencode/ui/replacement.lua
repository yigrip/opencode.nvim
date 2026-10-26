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

local pending = {}

function M.show()
  local item = pending[1]
  if not item then
    return false
  end
  local panel = require("opencode.ui.panel")
  local function finish()
    table.remove(pending, 1)
    panel.locked = false
    panel.close()
    M.show()
  end
  panel.show("replacement", item.lines, {
    filetype = "diff",
    focus = true,
    reject = finish,
    accept = function()
      local ok, err = pcall(M.apply, item.snapshot, item.proposed)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
        return
      end
      finish()
      vim.notify("Replacement accepted; use :write to save")
    end,
  })
  panel.locked = true
  return true
end

function M.preview(snapshot, text)
  if not vim.api.nvim_buf_is_valid(snapshot.buf) then
    error("Source buffer no longer exists; no replacement was applied")
  end
  local proposed = M.proposed(snapshot, M.decode(text))
  ---@diagnostic disable-next-line: deprecated
  local diff_fn = (vim.text and vim.text.diff) or vim.diff
  local diff = diff_fn(
    table.concat(snapshot.lines, "\n") .. "\n",
    table.concat(proposed, "\n") .. "\n",
    { result_type = "unified", ctxlen = 3 }
  )
  assert(type(diff) == "string", "Could not produce a replacement diff")
  local lines = { "Accept this change?  [a] Accept  [r] Reject", "" }
  vim.list_extend(lines, vim.split(diff == "" and "No changes proposed." or diff, "\n", { plain = true }))
  table.insert(pending, { snapshot = snapshot, proposed = proposed, lines = lines })
  if #pending == 1 then
    M.show()
  end
end

return M
