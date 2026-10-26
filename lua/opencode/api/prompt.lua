local M = {}

---@param prompt string
---@param context opencode.context.Context
---@return Promise<any>
function M.prompt(prompt, context, replacement)
  local Promise = require("opencode.promise")
  local stop
  return (
    prompt:match("%.%.%.$") and require("opencode.ui.ask").ask(prompt:gsub("%.%.%.$", ""), context)
    or Promise.resolve(prompt)
  )
    :next(function(input)
      stop = require("opencode.ui.progress").start(context)
      local has_context = false
      for placeholder in pairs(require("opencode.config").opts.contexts) do
        if input:find(placeholder, 1, true) then
          has_context = true
          break
        end
      end
      local plaintext = context:render(has_context and input or "@this: " .. input).output:plaintext()
      return require("opencode.context.rust").collect(context.buf):next(function(rust)
        return context.server:resolve_session():next(function(session)
          local permissions = vim.deepcopy(rust.permissions)
          for _, action in ipairs({ "edit", "shell", "subagent", "question" }) do
            table.insert(permissions, { action = action, resource = "*", effect = "deny" })
          end
          return context.server
            :request("/api/session/" .. session.id, "PATCH", { permissions = permissions })
            :next(function()
              local instruction = "\nAnswer this question without modifying files."
              local complete
              if replacement then
                instruction = "\nReturn ONLY a JSON object with one string field, replacement. "
                  .. "The string must contain the complete replacement for the target below, without markdown fences. "
                  .. "Do not modify files. Read related sources as needed. Preserve code outside the target.\n"
                  .. "Target buffer: "
                  .. vim.api.nvim_buf_get_name(context.buf)
                  .. "\nTarget text (JSON encoded): "
                  .. vim.json.encode(replacement.text)
                complete = function(text)
                  require("opencode.ui.replacement").preview(replacement, text)
                end
              end
              require("opencode.ui.output").begin(session.id, input, complete, stop)
              return context.server:prompt(session.id, plaintext .. rust.text .. instruction)
            end)
        end)
      end)
    end)
    :next(function()
      context:clear()
    end)
    :catch(function(err)
      if stop then
        stop()
      end
      context:resume()
      return Promise.reject(err)
    end)
end

return M
