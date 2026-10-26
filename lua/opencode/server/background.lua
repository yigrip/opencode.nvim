local M = {}
local running = false

function M.executable()
  if vim.fn.executable("opencode") == 1 then
    return "opencode"
  end
  local installed = vim.fn.expand("~/.opencode/bin/opencode")
  return vim.fn.executable(installed) == 1 and installed or nil
end

function M.start()
  if running then
    return
  end
  local executable = M.executable()
  if not executable then
    error("Install OpenCode v2 and connect your OpenCode Go account first")
  end
  running = true
  vim.system({ executable, "service", "start" }, { text = true }, function(result)
    running = false
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("OpenCode service failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      end)
    end
  end)
end

return M
