local M = {}
local buffer, window
M.owner = nil
M.locked = false

function M.close()
  if window and vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buffer then
    vim.api.nvim_win_close(window, true)
  end
  window = nil
end

function M.show(owner, lines, opts)
  opts = opts or {}
  if window and vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) ~= buffer then
    window = nil
  end
  if M.locked and M.owner ~= owner then
    return
  end
  if opts.open == false and (not window or not vim.api.nvim_win_is_valid(window)) then
    return
  end
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].swapfile = false
  end
  M.owner = owner
  for _, key in ipairs({ "a", "r", "da", "dr", "q", "<Esc>" }) do
    pcall(vim.keymap.del, "n", key, { buffer = buffer })
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].filetype = opts.filetype or "markdown"
  local reject = opts.reject or M.close
  for _, key in ipairs({ "q", "<Esc>", "r", "dr" }) do
    vim.keymap.set("n", key, reject, { buffer = buffer, desc = "Close / reject AI result" })
  end
  if opts.accept then
    for _, key in ipairs({ "a", "da" }) do
      vim.keymap.set("n", key, opts.accept, { buffer = buffer, desc = "Accept AI replacement" })
    end
  end
  if not window or not vim.api.nvim_win_is_valid(window) then
    local source = vim.api.nvim_get_current_win()
    vim.cmd("botright vsplit")
    window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(window, buffer)
    vim.wo[window].wrap = true
    if not opts.focus then
      vim.api.nvim_set_current_win(source)
    end
  elseif opts.focus then
    vim.api.nvim_set_current_win(window)
  end
  vim.wo[window].winbar = opts.accept and " AI preview — [a] Accept  [r] Reject " or " AI result — [q] Close "
end

return M
