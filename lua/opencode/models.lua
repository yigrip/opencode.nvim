local M = {}

local function path()
  return vim.fn.stdpath("state") .. "/opencode.nvim/model.json"
end

function M.reference(value)
  if value == nil or value == "" then
    return nil
  end
  local provider, id = value:match("^([^/]+)/(.+)$")
  assert(provider and id, "OpenCode model must use provider/model format")
  return { providerID = provider, id = id }
end

function M.get()
  local configured = require("opencode.config").opts.model
  if configured then
    return M.reference(configured)
  end
  local ok, lines = pcall(vim.fn.readfile, path())
  if not ok then
    return nil
  end
  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if decoded and type(value) == "table" and type(value.model) == "string" then
    local valid, reference = pcall(M.reference, value.model)
    if valid then
      return reference
    end
  end
  return nil
end

function M.save(value)
  M.reference(value)
  local file = path()
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  assert(vim.fn.writefile({ vim.json.encode({ model = value or "" }) }, file) == 0, "Could not save model choice")
  require("opencode.config").opts.model = value
end

function M.options(models)
  local items = {}
  for _, model in ipairs(models) do
    if model.enabled ~= false and type(model.providerID) == "string" and type(model.id) == "string" then
      table.insert(items, { value = model.providerID .. "/" .. model.id, name = model.name or model.id })
    end
  end
  table.sort(items, function(a, b)
    local go_a, go_b = a.value:match("^opencode%-go/") ~= nil, b.value:match("^opencode%-go/") ~= nil
    if go_a ~= go_b then
      return go_a
    end
    return a.value < b.value
  end)
  table.insert(items, 1, { name = "Use OpenCode's default model" })
  return items
end

function M.select(server)
  return server:request("/api/model", "GET"):next(function(response)
    local selected = M.get()
    local selected_name = selected and (selected.providerID .. "/" .. selected.id)
    return require("opencode.promise.ui")
      .select(M.options(response and response.data or {}), {
        prompt = "OpenCode model (saved for future actions): ",
        format_item = function(item)
          local current = item.value == selected_name and " [current]" or ""
          return item.value and (item.name .. " — " .. item.value .. current) or (item.name .. current)
        end,
      })
      :next(function(item)
        M.save(item.value)
        vim.notify("OpenCode model: " .. (item.value or "default"))
      end)
  end)
end

return M
