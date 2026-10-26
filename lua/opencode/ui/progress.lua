local M = {}
local active = {}
local ns = vim.api.nvim_create_namespace("OpencodeProgress")
local frames = { "|", "/", "-", "\\" }

function M.status()
  local count = vim.tbl_count(active)
  return count > 0 and ("AI working" .. (count > 1 and (" (" .. count .. ")") or "…")) or ""
end

function M.start(context)
  local timer = assert(vim.uv.new_timer())
  local state = { timer = timer, buf = context.buf, row = context.cursor and context.cursor[1] or 1, frame = 0 }
  active[state] = true
  local function draw()
    if not active[state] then
      return
    end
    if vim.api.nvim_buf_is_valid(state.buf) then
      state.frame = state.frame + 1
      state.mark = vim.api.nvim_buf_set_extmark(
        state.buf,
        ns,
        math.min(state.row, vim.api.nvim_buf_line_count(state.buf)) - 1,
        0,
        {
          id = state.mark,
          virt_text = { { " " .. frames[(state.frame - 1) % #frames + 1] .. " AI working… ", "DiagnosticInfo" } },
          virt_text_pos = "eol",
        }
      )
    end
    vim.cmd("redrawstatus")
  end
  draw()
  timer:start(150, 150, vim.schedule_wrap(draw))
  local function stop()
    if not active[state] then
      return
    end
    active[state] = nil
    timer:stop()
    timer:close()
    if state.mark and vim.api.nvim_buf_is_valid(state.buf) then
      pcall(vim.api.nvim_buf_del_extmark, state.buf, ns, state.mark)
    end
    vim.cmd("redrawstatus")
  end
  state.stop = stop
  return stop
end

function M.stop_all()
  for state in pairs(active) do
    state.stop()
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("OpencodeProgress", { clear = true }),
  callback = M.stop_all,
})

return M
