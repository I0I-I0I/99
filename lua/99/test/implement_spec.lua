-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same
local Levels = require("99.logger.level")
local Range = require("99.geo").Range
local Point = require("99.geo").Point

--- @param content string[]
--- @param cursor_row number
--- @param cursor_col number
--- @return _99.test.Provider, number
local function setup(content, cursor_row, cursor_col)
  local p = test_utils.TestProvider.new()
  _99.setup({
    provider = p,
    logger = {
      error_cache_level = Levels.ERROR,
    },
  })

  local buffer = test_utils.create_file(content, "lua", cursor_row, cursor_col)
  return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("implement", function()
  it("should implement the selected code", function()
    local content = {
      "local function calculate(x)",
      "    -- TODO: implement",
      "end",
    }
    local p, buffer = setup(content, 2, 5) -- Put cursor inside the function

    _99.implement()

    local state = _99.__get_state()
    eq(1, state.tracking:active_count())

    p:resolve("success", "    return x * 2")
    test_utils.next_frame()

    local expected = {
      "local function calculate(x)",
      "    return x * 2",
      "end",
    }
    eq(expected, r(buffer))
  end)

  it(
    "should fallback to visual selection range if no treesitter function enclosing is found",
    function()
      local content = {
        "local x = 42",
        "local y = 100",
      }
      local p, buffer = setup(content, 1, 7) -- Cursor on 'x'

      -- Mock/force the visual selection marks '< and '> manually for the test
      vim.api.nvim_buf_set_mark(buffer, "<", 1, 6, {})
      vim.api.nvim_buf_set_mark(buffer, ">", 1, 7, {})

      _99.implement()

      local state = _99.__get_state()
      eq(1, state.tracking:active_count())

      p:resolve("success", "value")
      test_utils.next_frame()

      -- 'x' is replaced with 'value'
      local expected = {
        "",
        "value",
        "local y = 100",
      }
      eq(expected, r(buffer))
    end
  )

  it("should create a new Lua file when require is called", function()
    local content = {
      'require("some-module").say_hello()',
    }
    local p, buffer = setup(content, 1, 1)

    local current_file_path = vim.api.nvim_buf_get_name(buffer)
    local current_dir = (not current_file_path or current_file_path == "")
        and vim.fn.getcwd()
      or vim.fn.fnamemodify(current_file_path, ":h")
    local target_path = vim.fn.simplify(current_dir .. "/some-module.lua")

    if vim.fn.filereadable(target_path) == 1 then
      vim.fn.delete(target_path)
    end

    _99.implement()

    local state = _99.__get_state()
    eq(1, state.tracking:active_count())

    local response_code =
      "local M = {}\nfunction M.say_hello()\n  print('hello')\nend\nreturn M"
    p:resolve("success", response_code)
    test_utils.next_frame()

    -- The original buffer should remain unchanged
    eq(content, r(buffer))

    -- The new buffer should have been created and populated
    local new_buf = vim.api.nvim_get_current_buf()
    assert(new_buf ~= buffer, "Should have switched to the new buffer")
    local new_path = vim.api.nvim_buf_get_name(new_buf)
    eq(target_path, new_path)

    local new_content = r(new_buf)
    eq(vim.split(response_code, "\n"), new_content)

    -- Clean up
    vim.fn.delete(target_path)
    vim.api.nvim_buf_delete(new_buf, { force = true })
  end)

  it("should create a new Python file when import is called", function()
    local content = {
      "import some_module",
      "some_module.say_hello()",
    }
    local p, buffer = setup(content, 1, 1)
    vim.api.nvim_buf_set_mark(buffer, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buffer, ">", 2, 23, {})

    local current_file_path = vim.api.nvim_buf_get_name(buffer)
    local current_dir = (not current_file_path or current_file_path == "")
        and vim.fn.getcwd()
      or vim.fn.fnamemodify(current_file_path, ":h")
    local target_path = vim.fn.simplify(current_dir .. "/some_module.py")

    if vim.fn.filereadable(target_path) == 1 then
      vim.fn.delete(target_path)
    end

    _99.implement()

    local state = _99.__get_state()
    eq(1, state.tracking:active_count())

    local response_code = "def say_hello():\n    print('hello')"
    p:resolve("success", response_code)
    test_utils.next_frame()

    -- The original buffer should remain unchanged
    eq(content, r(buffer))

    -- The new buffer should have been created and populated
    local new_buf = vim.api.nvim_get_current_buf()
    assert(new_buf ~= buffer, "Should have switched to the new buffer")
    local new_path = vim.api.nvim_buf_get_name(new_buf)
    eq(target_path, new_path)

    local new_content = r(new_buf)
    eq(vim.split(response_code, "\n"), new_content)

    -- Clean up
    vim.fn.delete(target_path)
    vim.api.nvim_buf_delete(new_buf, { force = true })
  end)
end)
