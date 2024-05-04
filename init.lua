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

local url_pattern = "https?://%w+%.%w+[/%w_%-%.*(%%20)]+"

-- Sample link: https://iris.eus

config.plugins.link_opener =
    common.merge(
    {
        filelauncher = platform_filelauncher,
        format_urls = true,
        config_spec = {
            --- config specification used by the settings gui
            name = "Link opener",
            {
                label = "Enable",
                description = "Format URLs in document.",
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
    renderer.draw_rect(x1, y + self:get_line_height() - h, x2 - x1, h, color)
    renderer.draw_text(self:get_font(), str, x1, y + oy, color)
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
    os.execute(string.format('%s "%s"', config.plugins.link_opener.filelauncher, url))
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

