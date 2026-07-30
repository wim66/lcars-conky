--[[
    widget.lua - conky-lcars
    Star Trek LCARS-style full-system Conky panel: CPU, memory, storage,
    network, top processes and a stardate/clock readout.

    Design goals:
    - no global leakage (everything local, state in W)
    - no blocking I/O in conky_main (data.lua only uses conky_parse() and
      cheap /proc reads; interface/core detection happens once at startup)
    - portable drawing surface: conky_surface() preferred, cairo_xlib
      fallback for builds without it
    - path-resolved require() for sibling modules (lcars.lua, data.lua)
--]]

require("cairo")

-- Portable drawing-surface helper
local has_cairo_xlib, cairo_xlib = pcall(require, "cairo_xlib")
if not has_cairo_xlib then
    cairo_xlib = setmetatable({}, {
        __index = function(_, k) return _G[k] end,
    })
end

-- Needed for cairo_place_image() (renders a PNG via imlib2). Not every
-- Conky build compiles this in, so we pcall it and fall back to the
-- drawn badge if it's unavailable.
local has_imlib2 = pcall(require, "cairo_imlib2_helper")

local function get_draw_surface()
    if conky_surface then
        local s = conky_surface()
        if s then return s, false end
    end
    if conky_window and cairo_xlib_surface_create then
        local s = cairo_xlib_surface_create(conky_window.display,
            conky_window.drawable, conky_window.visual,
            conky_window.width, conky_window.height)
        return s, true
    end
    return nil, false
end

-- ---- path resolution so sibling modules load regardless of Conky's cwd ----
local function script_dir()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)") or "./"
end
local BASE_DIR = script_dir()
package.path = BASE_DIR .. "?.lua;" .. package.path

local lcars = require("lcars")
local data = require("data")

-- ---- widget state ----
local W = {
    width = 460,
    height = 900,
    outer = 16,
    sidebar_w = 110,
    iface = "enp0s31f6",
    cpu_count = 4,
    fs_mount = "/",           -- change/add mounts here if you want more panels
    sections = { "CPU", "MEM", "DISK", "HOME", "NET", "PROC", "TIME" },
    section_color = {
        lcars.color.orange, lcars.color.blue, lcars.color.tan, lcars.color.gold,
        lcars.color.pink, lcars.color.lilac, lcars.color.red,
    },

    -- header badge image: put Starfleet.png next to widget.lua (same
    -- folder), or change this to an absolute path. badge_w/badge_h are
    -- the size it's drawn at - adjust to match your PNG's aspect ratio.
    -- badge_x/badge_y position it independently of everything else in
    -- the header - move it anywhere you like, the title text won't
    -- follow it.
    badge_png = BASE_DIR .. "Starfleet.png", -- Change to "" to show the drawn badge instead of a PNG
    badge_x = 30,
    badge_y = 20,
    badge_w = 80,
    badge_h = 80,

    distro = "LINUX", -- overwritten at startup by /etc/os-release, if readable
}

-- ---- Conky hooks ----
function conky_startup()
    local ok_i, iface = pcall(data.detect_default_iface)
    if ok_i and iface then W.iface = iface end
    local ok_c, count = pcall(data.detect_cpu_count)
    if ok_c and count then W.cpu_count = math.min(count, 8) end

    local ok_d, distro = pcall(data.detect_distro_name)
    if ok_d and distro then W.distro = distro:upper() end

    -- cairo_place_image() is a void C function: if the file can't be
    -- loaded it just logs internally to Conky's own log and returns -
    -- pcall() around it always reports "ok" either way, so it can't be
    -- used to detect a missing/bad image. Check the file ourselves,
    -- once, instead.
    W.badge_available = false
    if has_imlib2 and W.badge_png then
        local f = io.open(W.badge_png, "rb")
        if f then
            f:close()
            W.badge_available = true
        end
    end
end

-- ---- layout helpers ----
-- returns the top-y and height of each stacked section (count driven by
-- W.sections), aligned between sidebar and content column
local function section_layout()
    local top = W.outer + 90 + 8      -- below the top elbow's vertical arm
    local bottom = W.height - W.outer - 90 - 8 -- above the bottom elbow's arm
    local n = #W.sections
    local gap = 12
    local total_gap = gap * (n - 1)
    local h = (bottom - top - total_gap) / n

    local rows = {}
    local y = top
    for i = 1, n do
        rows[i] = { y = y, h = h }
        y = y + h + gap
    end
    return rows
end

-- draws the header badge: Starfleet.png if it exists and imlib2 support is
-- compiled into this Conky build (checked once at startup, see
-- conky_startup), otherwise falls back to the drawn badge so the header
-- never ends up with a blank hole.
local function draw_header_badge(cr, x, y)
    if W.badge_available then
        local ok = pcall(cairo_place_image, W.badge_png, cr, x, y, W.badge_w, W.badge_h, 1)
        if ok then return end
    end
    lcars.badge(cr, x + W.badge_w / 2, y + W.badge_h / 2,
        math.min(W.badge_w, W.badge_h) / 2, lcars.color.ink)
end

-- ---- drawing: frame (elbows, header, footer, sidebar pills) ----
local function draw_frame(cr, rows)
    local header_right = W.width - W.outer
    local sb_x = W.outer

    -- top elbow: tall vertical stub + header bar, rounded top-left bend
    lcars.elbow(cr, "tl",
        sb_x, W.outer, W.sidebar_w, 90,
        sb_x, W.outer, header_right - sb_x, 60,
        lcars.color.orange)

    draw_header_badge(cr, W.badge_x, W.badge_y)

    lcars.text(cr, W.outer + W.sidebar_w + 14, W.outer + 38,
        "LCARS \226\128\162 SYSTEMS MONITOR", 18, lcars.color.ink, 1, "left")
    lcars.text(cr, header_right - 14, W.outer + 56,
        "STARDATE " .. data.stardate(), 11, lcars.color.ink, 0.8, "right")

    -- bottom elbow: tall vertical stub + footer bar, rounded bottom-left bend
    local bot = W.height - W.outer
    lcars.elbow(cr, "bl",
        sb_x, bot - 90, W.sidebar_w, 90,
        sb_x, bot - 40, header_right - sb_x, 40,
        lcars.color.lilac)

    lcars.text(cr, W.outer + W.sidebar_w + 14, bot - 15,
        W.distro .. " \226\128\162 UPTIME " .. data.uptime(), 12,
        lcars.color.ink, 0.85, "left")

    -- sidebar pills, one per section, color-matched to its content panel
    for i, label in ipairs(W.sections) do
        local row = rows[i]
        lcars.pill(cr, sb_x, row.y, W.sidebar_w, row.h, W.section_color[i], 1)
        lcars.text(cr, sb_x + W.sidebar_w / 2, row.y + row.h / 2 + 5,
            label, 15, lcars.color.ink, 1, "center")
    end
end

-- ---- drawing: content panels ----
local function content_bounds()
    local x = W.outer + W.sidebar_w + 12
    local right = W.width - W.outer
    return x, right - x
end

-- ---- history buffers for the CPU/NET okudagram-style graphs ----
-- Plain Lua locals, so they persist for the life of the Conky process
-- (module state, not per-tick) - no extra I/O, just one push per tick.
local HIST_LEN = 40 -- ~40s of samples at update_interval = 1
local cpu_hist, net_down_hist, net_up_hist = {}, {}, {}

local function push_sample(hist, v)
    hist[#hist + 1] = v or 0
    if #hist > HIST_LEN then table.remove(hist, 1) end
end

-- largest value currently in the buffer (with a floor, so a quiet
-- network graph doesn't visually amplify tiny idle noise)
local function hist_max(hist, floor)
    local m = floor or 0
    for _, v in ipairs(hist) do
        if v > m then m = v end
    end
    return m
end

local function draw_cpu(cr, x, y, w, h, color)
    local overall = data.cpu_overall()
    push_sample(cpu_hist, overall)
    lcars.text(cr, x, y + 16, "CPU LOAD", 13, color, 1)
    lcars.text(cr, x + w, y + 16, string.format("%d%%", overall), 13, color, 1, "right")
    lcars.history_bars(cr, x, y + 24, w, 16, cpu_hist, 100, color)

    local cores = data.cpu_cores(W.cpu_count)
    local n = #cores
    if n > 0 then
        local gap = 6
        local cw = (w - gap * (n - 1)) / n
        local by = y + 24 + 16 + 10
        local bh = math.max(h - (24 + 16 + 10) - 14, 8)
        for i, pct in ipairs(cores) do
            local cx = x + (i - 1) * (cw + gap)
            lcars.bar(cr, cx, by, cw, bh, pct, color)
        end
    end
end

local function draw_mem(cr, x, y, w, h, color)
    local m = data.mem()
    lcars.text(cr, x, y + 16, "MEMORY", 13, color, 1)
    lcars.text(cr, x + w, y + 16, string.format("%d%%", m.pct), 13, color, 1, "right")
    lcars.bar(cr, x, y + 24, w, 16, m.pct, color)
    lcars.text(cr, x, y + h - 6, (m.used or "?") .. " / " .. (m.max or "?"), 11,
        lcars.color.tan, 0.9)
end

local function draw_disk_for(mount)
    return function(cr, x, y, w, h, color)
        local fs = data.fs(mount)
        lcars.text(cr, x, y + 16, "STORAGE " .. mount, 13, color, 1)
        lcars.text(cr, x + w, y + 16, string.format("%d%%", fs.pct), 13, color, 1, "right")
        lcars.bar(cr, x, y + 24, w, 16, fs.pct, color)
        lcars.text(cr, x, y + h - 6, (fs.used or "?") .. " / " .. (fs.size or "?"), 11,
            lcars.color.tan, 0.9)
    end
end

local function fmt_rate(kib)
    return string.format("%.2f MiB/s", (kib or 0) / 1024)
end

local function draw_net(cr, x, y, w, h, color)
    local n = data.net(W.iface)
    push_sample(net_down_hist, n.down_kib)
    push_sample(net_up_hist, n.up_kib)

    local down_str = "DOWN  " .. fmt_rate(n.down_kib)
    local up_str = "UP    " .. fmt_rate(n.up_kib)

    -- size the label column to whichever line is actually wider this
    -- tick, plus the triangle offset and a small margin before the graph
    local text_w = math.max(lcars.text_width(cr, down_str, 13),
        lcars.text_width(cr, up_str, 13))
    local label_w = 20 + text_w + 14
    local graph_x = x + label_w
    local graph_w = math.max(w - label_w, 20)

    lcars.text(cr, x, y + 16, "NETWORK " .. W.iface, 13, color, 1)

    lcars.triangle(cr, x + 6, y + 36, 11, color, "down")
    lcars.text(cr, x + 20, y + 41, down_str, 13, color, 1)
    lcars.history_bars(cr, graph_x, y + 28, graph_w, 16,
        net_down_hist, hist_max(net_down_hist, 64), color)

    lcars.triangle(cr, x + 6, y + 60, 11, color, "up")
    lcars.text(cr, x + 20, y + 65, up_str, 13, color, 1)
    lcars.history_bars(cr, graph_x, y + 52, graph_w, 16,
        net_up_hist, hist_max(net_up_hist, 64), color)
end

local function draw_proc(cr, x, y, w, h, color)
    lcars.text(cr, x, y + 16, "TOP PROCESSES", 13, color, 1)
    local procs = data.top_processes(5)
    local row_h = (h - 24) / #procs
    for i, p in ipairs(procs) do
        local ry = y + 24 + (i - 1) * row_h + row_h * 0.7
        lcars.text(cr, x, ry, p.name or "-", 12, lcars.color.tan, 0.95)
        lcars.text(cr, x + w, ry, (p.cpu or "0") .. "%", 12, color, 1, "right")
    end
end

local function draw_time(cr, x, y, w, h, color)
    lcars.text(cr, x, y + 32, os.date("%H:%M:%S"), 26, color, 1, "left", true)
    lcars.text(cr, x, y + 52, os.date("%A %d %B %Y"), 13, lcars.color.tan, 0.95)
    lcars.text(cr, x, y + h - 4, "STARDATE " .. data.stardate(), 12, color, 0.9)
end

local draw_section = {
    CPU = draw_cpu, MEM = draw_mem,
    DISK = draw_disk_for(W.fs_mount), HOME = draw_disk_for("/home"),
    NET = draw_net, PROC = draw_proc, TIME = draw_time,
}

local function draw(cr)
    -- background panel behind everything
    lcars.filled_rect(cr, 0, 0, W.width, W.height, lcars.color.black, 0.66,
        18, 18, 18, 18)

    local rows = section_layout()
    draw_frame(cr, rows)

    local cx, cw = content_bounds()
    for i, label in ipairs(W.sections) do
        local row = rows[i]
        draw_section[label](cr, cx, row.y, cw, row.h, W.section_color[i])
    end
end

function conky_main()
    local surface, owns_surface = get_draw_surface()
    if not surface then return end
    local cr = cairo_create(surface)

    -- Auto-scale: the whole layout is designed at W.width x W.height
    -- (460x900). If conky.conf's window is a different size (e.g. a
    -- smaller 307x600 window for a compact version), scale the drawing
    -- uniformly to fit it - same widget.lua/lcars.lua, just resize the
    -- window in conky.conf.
    if conky_window and conky_window.width and conky_window.height then
        local sx = conky_window.width / W.width
        local sy = conky_window.height / W.height
        local s = math.min(sx, sy)
        if s ~= 1 then cairo_scale(cr, s, s) end
    end

    local ok, err = pcall(draw, cr)
    if not ok then
        -- fail quiet: don't kill the whole Conky process on a bad tick
        io.stderr:write("conky-lcars draw error: " .. tostring(err) .. "\n")
    end

    cairo_destroy(cr)
    if owns_surface then
        cairo_surface_destroy(surface)
    end
end