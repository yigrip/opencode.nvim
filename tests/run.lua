---@diagnostic disable: duplicate-set-field
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.shadafile = "NONE"
local count = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n")
    vim.cmd("cquit 1")
  end
  count = count + 1
  print("PASS " .. name)
end
local function await(promise)
  local done, value, failure
  promise
    :next(function(result)
      value, done = result, true
    end)
    :catch(function(err)
      failure, done = err, true
    end)
  assert(
    vim.wait(2000, function()
      return done
    end, 10),
    "Promise timed out"
  )
  assert(not failure, tostring(failure))
  return value
end
local Promise = require("opencode.promise")
local Context = require("opencode.context")
local builtins = require("opencode.context.builtins")
local Server = require("opencode.server")

test("whole unsaved file and exact selected columns", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "second" })
  local context = Context.new(nil)
  assert(builtins.this(context) == "abcdef\nsecond")
  context.range = { from = { 1, 1 }, to = { 1, 3 }, kind = "char" }
  assert(builtins.this(context) == "bcd")
end)

test("each action creates an independent session", function()
  local creates = 0
  local server = setmetatable({
    request = function(_, path, method, body)
      assert(path == "/api/session" and method == "POST")
      assert(body.location.directory == vim.fn.getcwd())
      assert(body.permissions[1].action == "edit" and body.permissions[1].effect == "deny")
      creates = creates + 1
      return Promise.resolve({ data = { id = "own-session" } })
    end,
  }, Server)
  assert(await(server:resolve_session()).id == "own-session")
  assert(await(server:resolve_session()).id == "own-session")
  assert(creates == 2 and server.owned_sessions["own-session"])
end)

test("streaming answers handle deltas and final text without duplicates", function()
  local output = require("opencode.ui.output")
  local source = vim.api.nvim_get_current_win()
  output.begin("session-test", "Explain")
  assert(vim.api.nvim_get_current_win() == source)
  local buf
  for _, id in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[id].filetype == "markdown" then
      buf = id
    end
  end
  assert(buf)
  output.event({
    type = "session.text.delta",
    data = { sessionID = "session-test", assistantMessageID = "m", ordinal = 0, delta = "Hello" },
  })
  output.event({
    type = "session.text.ended",
    data = { sessionID = "session-test", assistantMessageID = "m", ordinal = 0, text = "Hello world" },
  })
  output.event({ type = "session.text.delta", data = { sessionID = "other", delta = "LEAK" } })
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  assert(text:find("Hello world", 1, true) and not text:find("HelloHello", 1, true))
  assert(not text:find("LEAK", 1, true))
  assert(vim.bo[buf].buftype ~= "terminal")
end)

test("Cargo metadata includes local path crates but excludes registry sources", function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "[package]", 'name = "root"' }, root .. "/Cargo.toml")
  vim.api.nvim_buf_set_name(0, root .. "/src/lib.rs")
  local original_system, original_executable = vim.system, vim.fn.executable
  vim.fn.executable = function()
    return 1
  end
  vim.system = function(cmd, opts, callback)
    assert(vim.tbl_contains(cmd, "--offline") and vim.tbl_contains(cmd, "--locked"))
    assert(opts.timeout == 10000)
    callback({
      code = 0,
      stdout = vim.json.encode({
        workspace_root = root,
        packages = {
          { name = "mine", source = vim.NIL, manifest_path = root .. "/Cargo.toml" },
          { name = "sibling", source = vim.NIL, manifest_path = root .. "/../sibling/Cargo.toml" },
          { name = "registry", source = "registry+url", manifest_path = "/registry/Cargo.toml" },
        },
      }),
    })
  end
  local result = await(require("opencode.context.rust").collect(0))
  vim.system, vim.fn.executable = original_system, original_executable
  assert(result.text:find("sibling", 1, true))
  assert(not result.text:find("registry", 1, true))
  assert(#result.permissions == 4)
  for _, rule in ipairs(result.permissions) do
    assert(rule.action ~= "edit")
  end
  vim.fn.delete(root, "rf")
end)

test("prompt supplies default context, crate paths, permissions and output", function()
  local rust = require("opencode.context.rust")
  local original = rust.collect
  rust.collect = function()
    return Promise.resolve({ text = "\nLocal crate: /sibling", permissions = {} })
  end
  local sent, patched
  local server = {
    resolve_session = function()
      return Promise.resolve({ id = "prompt-test" })
    end,
    request = function(_, path, method, body)
      assert(path == "/api/session/prompt-test" and method == "PATCH")
      patched = body.permissions[1].effect == "deny"
      return Promise.resolve(nil)
    end,
    prompt = function(_, id, text)
      sent = text
      return Promise.resolve(nil)
    end,
  }
  await(require("opencode.api.prompt").prompt("Explain", Context.new(server)))
  rust.collect = original
  assert(patched and sent:find("abcdef", 1, true) and sent:find("/sibling", 1, true))
end)

test("SSE accepts JSON split across job callbacks and ignores SSE metadata", function()
  local original = vim.fn.jobstart
  local got, failure, callbacks
  vim.fn.jobstart = function(_, opts)
    callbacks = opts
    return 1
  end
  local server = setmetatable({ url = "http://localhost" }, Server)
  server:curl("/api/event", "GET", nil, function(event)
    got = event
  end, function(err)
    failure = err
  end, { persistent = true })
  vim.fn.jobstart = original
  callbacks.on_stdout(1, { "event: message", 'data: {"type":"session.text.' })
  callbacks.on_stdout(1, { 'delta","data":{"delta":"hi"}}', "", "" })
  assert(vim.wait(1000, function()
    return got ~= nil or failure ~= nil
  end, 10))
  assert(not failure and got.data.delta == "hi")
end)

test("offline Cargo fallback keeps direct local dependencies", function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "[package]" }, root .. "/Cargo.toml")
  vim.api.nvim_buf_set_name(0, root .. "/src/lib.rs")
  local original, calls = vim.system, 0
  vim.system = function(cmd, _, callback)
    calls = calls + 1
    if calls == 1 then
      callback({ code = 1, stdout = "", stderr = "dependency unavailable offline" })
    else
      assert(vim.tbl_contains(cmd, "--no-deps"))
      callback({
        code = 0,
        stdout = vim.json.encode({
          workspace_root = root,
          packages = {
            {
              name = "root",
              manifest_path = root .. "/Cargo.toml",
              dependencies = {
                { name = "local-lib", path = root .. "/../local-lib" },
              },
            },
          },
        }),
      })
    end
  end
  local result = await(require("opencode.context.rust").collect(0))
  vim.system = original
  assert(calls == 2 and result.text:find("local-lib", 1, true))
  assert(#result.permissions == 4)
  vim.fn.delete(root, "rf")
end)

test("replacement preserves surrounding text and UTF-8 selections", function()
  local edit = require("opencode.ui.replacement")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before héllo after", "untouched" })
  local snapshot = edit.capture({ buf = buf, range = { from = { 1, 8 }, to = { 1, 8 }, kind = "char" } })
  assert(snapshot.text == "é")
  local proposed = edit.proposed(snapshot, "X")
  assert(proposed[1] == "before hXllo after" and proposed[2] == "untouched")
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "before héllo after")
  edit.apply(snapshot, proposed)
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "before hXllo after")
end)

test("line and full-buffer replacements and stale-source rejection", function()
  local edit = require("opencode.ui.replacement")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c" })
  local snapshot = edit.capture({ buf = buf, range = { from = { 2, 0 }, to = { 2, 99 }, kind = "line" } })
  assert(vim.deep_equal(edit.proposed(snapshot, ""), { "a", "c" }))
  local whole = edit.capture({ buf = buf })
  assert(whole.text == "a\nb\nc")
  assert(vim.deep_equal(edit.proposed(whole, "new\nfile"), { "new", "file" }))
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "user edit" })
  assert(not pcall(edit.apply, snapshot, { "stale" }))
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "user edit")
  assert(not pcall(edit.decode, "Here is some code"))
  assert(edit.decode('{"replacement":""}') == "")
end)

test("preview reject leaves source intact and accept applies only on da", function()
  local edit = require("opencode.ui.replacement")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "original" })
  local function press(key)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if mapping.lhs == key then
        mapping.callback()
        return
      end
    end
    error("Missing preview mapping " .. key)
  end
  edit.preview(edit.capture({ buf = buf }), '{"replacement":"candidate"}')
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "original")
  press("dr")
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "original")
  edit.preview(edit.capture({ buf = buf }), '{"replacement":"accepted"}')
  press("da")
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "accepted")
end)

test("edit waits for success and uses final result rather than progress notes", function()
  local output = require("opencode.ui.output")
  local result, calls = nil, 0
  local windows = #vim.api.nvim_list_wins()
  output.begin("edit-result", "replace", function(text)
    result = text
    calls = calls + 1
  end)
  assert(#vim.api.nvim_list_wins() == windows)
  output.event({
    type = "session.text.ended",
    data = { sessionID = "edit-result", assistantMessageID = "m1", ordinal = 0, text = "Reading sources" },
  })
  output.event({
    type = "session.text.ended",
    data = { sessionID = "edit-result", assistantMessageID = "m2", ordinal = 0, text = '{"replacement":"new"}' },
  })
  assert(not result)
  output.event({ type = "session.execution.succeeded", data = { sessionID = "edit-result" } })
  output.event({ type = "session.execution.succeeded", data = { sessionID = "edit-result" } })
  assert(result == '{"replacement":"new"}' and calls == 1)
end)

print(string.format("%d tests passed", count))
vim.cmd("qa!")
