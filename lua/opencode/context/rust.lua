local M = {}

---Discover local sources without compiling, downloading, or updating Cargo.lock.
---@param buf integer
---@return Promise<table>
function M.collect(buf)
  local Promise = require("opencode.promise")
  if not require("opencode.config").opts.rust.enabled then
    return Promise.resolve({ text = "", permissions = {} })
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return Promise.resolve({ text = "", permissions = {} })
  end
  local manifest = vim.fs.find("Cargo.toml", { path = vim.fs.dirname(file), upward = true })[1]
  if not manifest then
    return Promise.resolve({ text = "", permissions = {} })
  end
  return Promise.new(function(resolve)
    local command = {
      "cargo",
      "metadata",
      "--format-version",
      "1",
      "--offline",
      "--locked",
      "--manifest-path",
      manifest,
    }
    if vim.fn.executable("cargo") ~= 1 then
      resolve({ text = "\nRust manifest: " .. manifest .. " (cargo is unavailable).", permissions = {} })
      return
    end
    local function run(fallback)
      vim.system(command, { text = true, timeout = 10000 }, function(result)
        vim.schedule(function()
          local ok, metadata = pcall(vim.json.decode, result.stdout or "")
          if result.code ~= 0 or not ok or type(metadata) ~= "table" then
            if not fallback then
              table.insert(command, "--no-deps")
              run(true)
              return
            end
            vim.notify("Cargo metadata unavailable; passing the manifest path only", vim.log.levels.WARN)
            resolve({ text = "\nRust manifest: " .. manifest, permissions = {} })
            return
          end
          local roots, lines, permissions =
            {}, {
              "\nRust workspace: " .. metadata.workspace_root,
              "Read the relevant local crate sources and callers before proposing changes:",
            }, {}
          local function add(name, root)
            root = vim.uv.fs_realpath(root) or vim.fs.normalize(root)
            if roots[root] then
              return
            end
            roots[root] = true
            table.insert(lines, "- " .. name .. ": " .. root)
            -- A wildcard in a literal directory would accidentally broaden a rule.
            if not root:find("[%*%?]") then
              for _, action in ipairs({ "external_directory", "read" }) do
                table.insert(permissions, { action = action, resource = root .. "/*", effect = "allow" })
              end
            end
          end
          for _, package in ipairs(metadata.packages or {}) do
            -- Registry and git dependencies are not automatically trusted as personal crates.
            if package.source == nil or package.source == vim.NIL then
              add(package.name, vim.fs.dirname(package.manifest_path))
              -- --no-deps still reports direct path dependencies on workspace members.
              for _, dependency in ipairs(package.dependencies or {}) do
                if type(dependency.path) == "string" then
                  add(dependency.name, dependency.path)
                end
              end
            end
          end
          if fallback then
            table.insert(
              lines,
              "Dependency resolution was unavailable offline. Follow path dependencies in Cargo.toml as needed."
            )
          end
          resolve({ text = table.concat(lines, "\n"), permissions = permissions })
        end)
      end)
    end
    run(false)
  end)
end

return M
