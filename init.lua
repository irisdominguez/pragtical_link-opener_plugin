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

local url_pattern = "https?://[/A-Za-z0-9%-%._%:%?#%[%]@!%$%&'%*%+,;%%=]+"

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

local function highlight_link(self, line, x, y, color)
    local text = self.doc.lines[line]
    local s, e = 0, 0

    while true do
        s, e = text:lower():find(url_pattern, e + 1)
        if s then
            local str = text:sub(s, e)
            draw_underline(self, str, line, x, y, s, e, color)
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
    local s, e = 0, 0
    local text = doc.lines[l]
    while true do
        s, e = text:find(url_pattern, e + 1)
        if s == nil then
            return nil
        end
        if c >= s and c <= e + 1 then
            return text:sub(s, e):lower(), s, e
        end
    end
end

local function open_url(url)
    core.log("Opening %s...", url)
    os.execute(string.format('%s %s', config.plugins.link_opener.filelauncher, url))
end

local docview_predicate = command.generate_predicate("core.docview")

local function url_at_caret()
    if docview_predicate() then
        if get_url_at_caret() then
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
        end
    }
)

keymap.add {["ctrl+return"] = "link-opener:open-link"}

contextmenu:register(
    url_at_caret,
    {
        contextmenu.DIVIDER,
        {text = "Open link", command = "link-opener:open-link"}
    }
)

