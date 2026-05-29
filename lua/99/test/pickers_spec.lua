-- luacheck: globals describe it assert before_each after_each
local pickers = require("99.extensions.pickers")
local _99 = require("99")
local eq = assert.are.same

describe("pickers", function()
  local original_ui_select
  local last_ui_select_args

  before_each(function()
    _99.setup({})
    original_ui_select = vim.ui.select
    last_ui_select_args = nil
    vim.ui.select = function(items, opts, on_choice)
      last_ui_select_args = {
        items = items,
        opts = opts,
        on_choice = on_choice,
      }
    end
  end)

  after_each(function()
    vim.ui.select = original_ui_select
  end)

  it("can select a model via vim.ui.select", function()
    -- Set to a provider that supports models
    _99.set_provider(_99.Providers.GeminiCLIProvider)

    pickers.select_model()

    assert.is_not_nil(last_ui_select_args)
    eq({ "auto", "pro", "flash", "flash-lite" }, last_ui_select_args.items)
    eq("99: Select Model (current: auto)", last_ui_select_args.opts.prompt)

    -- Trigger choice callback
    last_ui_select_args.on_choice("flash")
    eq("flash", _99.get_model())
  end)

  it("can select a provider via vim.ui.select", function()
    pickers.select_provider()

    assert.is_not_nil(last_ui_select_args)
    assert.is_true(#last_ui_select_args.items > 0)
    eq(
      "99: Select Provider (current: OpenCodeProvider)",
      last_ui_select_args.opts.prompt
    )

    -- Trigger choice callback to select GeminiCLIProvider
    last_ui_select_args.on_choice("GeminiCLIProvider")
    eq(_99.Providers.GeminiCLIProvider, _99.get_provider())
  end)
end)
