local RequestStatus = require("99.ops.request_status")
local Mark = require("99.ops.marks")
local geo = require("99.geo")
local make_prompt = require("99.ops.make-prompt")
local CleanUp = require("99.ops.clean-up")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

local Range = geo.Range
local Point = geo.Point

--- @param context _99.Prompt
--- @param opts? _99.ops.Opts
local function over_range(context, opts)
  opts = opts or {}
  local logger = context.logger:set_area("visual")

  local data = context:visual_data()
  local range = data.range
  local top_mark = Mark.mark_above_range(range)
  local bottom_mark = Mark.mark_point(range.buffer, range.end_)
  context.marks.top_mark = top_mark
  context.marks.bottom_mark = bottom_mark

  logger:debug(
    "visual request start",
    "start",
    Point.from_mark(top_mark),
    "end",
    Point.from_mark(bottom_mark)
  )

  local display_ai_status = context._99.ai_stdout_rows > 1
  local top_status = RequestStatus.new(
    250,
    context._99.ai_stdout_rows or 1,
    "Implementing",
    top_mark
  )
  local bottom_status = RequestStatus.new(250, 1, "Implementing", bottom_mark)
  local clean_up = make_clean_up(function()
    top_status:stop()
    bottom_status:stop()
  end)

  local system_cmd
  if opts.new_file_path then
    local new_file_name = vim.fn.fnamemodify(opts.new_file_path, ":t")
    local function get_surrounding_context(r, n)
      local start_row, _ = r.start:to_vim()
      local end_row, _ = r.end_:to_vim()
      local line_count = vim.api.nvim_buf_line_count(r.buffer)
      local from = math.max(start_row - n, 0)
      local to = math.min(end_row + 1 + n, line_count)
      local lines = vim.api.nvim_buf_get_lines(r.buffer, from, to, false)
      return table.concat(lines, "\n")
    end
    system_cmd = string.format(
      [[
You receive a selection in neovim that references a module/file you need to create: %s
Please provide the complete, robust, canonical implementation for this new file.
We will save your response directly into the file.
Do not output any markdown formatting other than the code itself, do not wrap in code blocks unless they are standard code, and output ONLY the implementation code for this new file.
<SELECTION_LOCATION>
%s
</SELECTION_LOCATION>
<SELECTION_CONTENT>
%s
</SELECTION_CONTENT>
<SURROUNDING_CONTEXT>
%s
</SURROUNDING_CONTEXT>
]],
      new_file_name,
      range:to_string(),
      range:to_text(),
      get_surrounding_context(range, 100)
    )
  else
    system_cmd = context._99.prompts.prompts.visual_selection(range)
  end
  local prompt, refs = make_prompt(context, system_cmd, opts)

  context:add_prompt_content(prompt)
  context:add_references(refs)
  context:add_clean_up(clean_up)

  top_status:start()
  bottom_status:start()
  context:start_request(make_observer(context, {
    on_complete = function(status, response)
      if status == "cancelled" then
        logger:debug("request cancelled for visual selection, removing marks")
      elseif status == "failed" then
        logger:error(
          "request failed for visual_selection",
          "error response",
          response or "no response provided"
        )
      elseif status == "success" then
        local valid = top_mark:is_valid() and bottom_mark:is_valid()
        if not valid then
          logger:fatal(
            -- luacheck: ignore 631
            "the original visual_selection has been destroyed.  You cannot delete the original visual selection during a request"
          )
          return
        end

        if vim.trim(response) == "" then
          print("response was empty, visual replacement aborted")
          logger:debug("response was empty, visual replacement aborted")
          return
        end

        if opts.new_file_path then
          local dir = vim.fn.fnamemodify(opts.new_file_path, ":h")
          if vim.fn.isdirectory(dir) == 0 then
            vim.fn.mkdir(dir, "p")
          end
          local lines = vim.split(response, "\n")
          local bufnr = vim.fn.bufadd(opts.new_file_path)
          vim.fn.bufload(bufnr)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("write")
          end)
          vim.api.nvim_set_current_buf(bufnr)
          vim.notify(
            "Created and implemented new file: " .. opts.new_file_path,
            vim.log.levels.INFO
          )
          context._99:sync()
        else
          local new_range = Range.from_marks(top_mark, bottom_mark)
          local lines = vim.split(response, "\n")

          --- HACK: i am adding a new line here because above range will add a mark to the line above.
          --- that way this appears to be added to "the same line" as the visual selection was
          --- originally take from
          table.insert(lines, 1, "")

          new_range:replace_text(lines)
          context._99:sync()
        end
      end
    end,
    on_stdout = function(line)
      if display_ai_status then
        top_status:push(line)
      end
    end,
  }))
end

return over_range
