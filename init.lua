-- mod-version:3
local core = require "core"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local common = require "core.common"
local DocView = require "core.docview"
local style = require "core.style"
local contextmenu = require "plugins.contextmenu"

local platform_filelauncher
if PLATFORM == "Windows" then
    platform_filelauncher = "start"
elseif PLATFORM == "Mac OS X" then
    platform_filelauncher = "open"
else
    platform_filelauncher = "xdg-open"
end

local url_pattern = "(https?://[/A-Za-z0-9%-%._%:%?#%[%]@!%$%&'%*%+~,;%%=]+)"

-- Sample link: https://iris.eus

config.plugins.link_opener =
    common.merge(
    {
        filelauncher = platform_filelauncher,
        format_urls = true,
        config_spec = {
            --- config specification used by the settings gui
            name = "Link Opener",
            {
                label = "Format URLs",
                description = "Toggles URL underlining in documents.",
                path = "format_urls",
                type = "toggle",
                default = true
            },
            {
                label = "URL opener",
                description = "Command used to open the url under the cursor.",
                path = "filelauncher",
                type = "string",
                default = platform_filelauncher
            }
        }
    },
    config.plugins.link_opener
)

local get_visible_cols_range = DocView.get_visible_cols_range
if not get_visible_cols_range then
  ---Get an estimated range of visible columns. It is an estimate because fonts
  ---and their fallbacks may not be monospaced or may differ in size.
  ---@param self core.docview
  ---@param line integer
  ---@param extra_cols integer Amount of columns to deduce on col1 and include on col2
  ---@return integer col1
  ---@return integer col2
  get_visible_cols_range = function(self, line, extra_cols)
    extra_cols = extra_cols or 100
    local gw = self:get_gutter_width()
    local line_x = self.position.x + gw
    local x = -self.scroll.x + self.position.x + gw

    local non_visible_x = common.clamp(line_x - x, 0, math.huge)
    local char_width = self:get_font():get_width("W")
    local non_visible_chars_left = math.floor(non_visible_x / char_width)
    local visible_chars_right = math.floor((self.size.x - gw) / char_width)
    local line_len = #self.doc.lines[line]

    if non_visible_chars_left > line_len then return 0, 0 end

    return
      math.max(1, non_visible_chars_left - extra_cols),
      math.min(line_len, non_visible_chars_left + visible_chars_right + extra_cols)
  end
end

local function draw_underline(self, str, line, x, y, s, e, color)
    local x1 = x + self:get_col_x_offset(line, s)
    local x2 = x + self:get_col_x_offset(line, e + 1)
    local oy = self:get_line_text_y_offset()
    local h = math.ceil(1 * SCALE)
    local rx1, ry1 = self:get_line_screen_position(line, s)
    local rx2, ry2 = self:get_line_screen_position(line, e + 1)
    local w = self:get_font():get_width(1)

    -- Get token color
    local column = 1
    for _, type, text in self.doc.highlighter:each_token(line) do
      local length = #text
      local half_token = column + (length / 2)
      if (s <= half_token) and (half_token <= e) then
        color = style.syntax[type]
        break
      end
      column = column + length
    end

    if ry1 ~= ry2 then
      -- We are softwrapped in a long link
      local rx2, ry2 = self:get_line_screen_position(line, s)
      for c = s+1, e+1, 1 do
        local rxnew, rynew = self:get_line_screen_position(line, c)
        if ry1 ~= rynew then
          renderer.draw_rect(rx1, ry1 + self:get_line_height() - h, rx2 - rx1 + w, h, color)
          rx1 = rxnew
          ry1 = rynew
        end
        rx2 = rxnew
        ry2 = rynew
      end
      renderer.draw_rect(rx1, ry1 + self:get_line_height() - h, rx2 - rx1, h, color)
    else
      renderer.draw_rect(rx1, ry1 + self:get_line_height() - h, rx2 - rx1, h, color)
    end
end

local function find_url_pattern(text, init)
    local s, e, url = text:find(url_pattern, init)
    -- strip trailing punctuation
    if s then
        local prev_len = #url
        url = url:match("^(.-)[%.,%]]*$") or url
        e = e - (prev_len - #url)
    end
    return s, e, url
end

local function highlight_link(self, line, x, y, color)
    local vs, ve = get_visible_cols_range(self, line, 2000)
    local text = self.doc.lines[line]:sub(vs, ve)
    local s, e, str = 0, 0, ""

    while true do
        s, e, str = find_url_pattern(text, e + 1)
        if s then
            draw_underline(self, str, line, x, y, vs + s - 1, vs + e - 1, color)
        end

        if not s then
            break
        end
    end
end

local draw_line_text = DocView.draw_line_text
function DocView:draw_line_text(line, x, y)
    local lh = draw_line_text(self, line, x, y)

    if config.plugins.link_opener.format_urls then
        highlight_link(self, line, x, y, style.spellcheck_error or style.syntax.keyword2)
    end
    return lh
end

local function get_url_at_caret()
    local doc = core.active_view.doc
    local l, c = doc:get_selection()
    local ss, se = math.max(1, c - 2000), math.min(#doc.lines[l], c + 2000)
    local text = doc.lines[l]:sub(ss, se)
    local s, e, str = 0, 0, ""
    while true do
        s, e, str = find_url_pattern(text, e + 1)
        if s == nil then
            return nil
        end
        local as, ae = ss + s - 1, ss + e
        if c >= as and c <= ae then
            return str, as, ae
        end
    end
end

local function open_url(url)
    core.log("Opening %s...", url)
    system.exec(string.format('%s "%s"', config.plugins.link_opener.filelauncher, url))
end

local docview_predicate = command.generate_predicate("core.docview")

local function get_url_at_pointer()
    local av = core.active_view
    if av.doc then
        local mx, my = core.root_view.mouse.x, core.root_view.mouse.y
        local line, col = av:resolve_screen_position(mx, my)
        if line and col then
            local ss = math.max(1, col - 2000)
            local se = math.min(#av.doc.lines[line], col + 2000)
            local text = av.doc.lines[line]:sub(ss, se)
            local s, e, str = 0, 0, ""
            while true do
                s, e, str = find_url_pattern(text, e + 1)
                if s == nil then
                    return nil
                end
                local as, ae = ss + s - 1, ss + e
                if col >= as and col <= ae then
                    return str, as, ae
                end
            end
        end
    end
    return nil
end

local function url_at_pointer()
    if docview_predicate() then
        if get_url_at_pointer() then
            return true
        end
    end
end

command.add(
    "core.docview",
    {
        ["link-opener:open-link"] = function()
            local url = get_url_at_caret()
            if url then
                open_url(url)
            else
                core.log("No link under cursor")
            end
        end,
        ["link-opener:open-link-at-pointer"] = function()
            local url = get_url_at_pointer()
            if url then
                open_url(url)
            else
                core.log("No link under pointer")
            end
        end
    }
)

keymap.add {["ctrl+return"] = "link-opener:open-link"}
keymap.add {["ctrl+alt+1lclick"] = "link-opener:open-link-at-pointer"}

contextmenu:register(
    url_at_pointer,
    {
        contextmenu.DIVIDER,
        {text = "Open link", command = "link-opener:open-link-at-pointer"}
    }
)
