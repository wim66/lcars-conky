--[[
    lcars.lua
    Reusable drawing primitives for a Star Trek LCARS-style Conky widget:
    rounded rectangles with per-corner radius, "elbow" brackets, pill
    buttons, LCARS-style meter bars and text helpers.

    Pure drawing helpers only - no Conky data reading and no I/O here,
    so this module is safe to require from any widget.
--]]

require("cairo")

local M = {}

-- ---- palette (classic LCARS hues, 0..1 rgb) ----
M.color = {
    orange = { 1.00, 0.61, 0.00 },
    tan    = { 1.00, 0.80, 0.60 },
    lilac  = { 0.80, 0.60, 0.80 },
    blue   = { 0.60, 0.60, 1.00 },
    red    = { 0.80, 0.40, 0.40 },
    pink   = { 0.80, 0.45, 0.60 },
    gold   = { 0.95, 0.75, 0.35 },
    yellow = { 0.98, 0.76, 0.12 }, -- Classic TOS yellow badge fill
    black  = { 0.02, 0.02, 0.04 },
    ink    = { 0.08, 0.08, 0.10 }, -- Dark outline / star color
    dim    = { 0.25, 0.20, 0.22 }, -- Unfilled part of meter bars
}

-- ---- low-level path helper: rectangle with independent corner radii ----
-- rtl/rtr/rbr/rbl = radius for top-left / top-right / bottom-right /
-- bottom-left corner; 0 = sharp corner. Only builds the PATH; caller
-- fills/strokes it. This is the base every other shape is built from.
function M.rounded_rect_path(cr, x, y, w, h, rtl, rtr, rbr, rbl)
    rtl = math.min(rtl or 0, w / 2, h / 2)
    rtr = math.min(rtr or 0, w / 2, h / 2)
    rbr = math.min(rbr or 0, w / 2, h / 2)
    rbl = math.min(rbl or 0, w / 2, h / 2)

    cairo_new_path(cr)
    cairo_move_to(cr, x + rtl, y)
    cairo_line_to(cr, x + w - rtr, y)
    if rtr > 0 then
        cairo_arc(cr, x + w - rtr, y + rtr, rtr, -math.pi / 2, 0)
    end
    cairo_line_to(cr, x + w, y + h - rbr)
    if rbr > 0 then
        cairo_arc(cr, x + w - rbr, y + h - rbr, rbr, 0, math.pi / 2)
    end
    cairo_line_to(cr, x + rbl, y + h)
    if rbl > 0 then
        cairo_arc(cr, x + rbl, y + h - rbl, rbl, math.pi / 2, math.pi)
    end
    cairo_line_to(cr, x, y + rtl)
    if rtl > 0 then
        cairo_arc(cr, x + rtl, y + rtl, rtl, math.pi, 3 * math.pi / 2)
    end
    cairo_close_path(cr)
end

local function set_rgba(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
end
M.set_color = set_rgba

-- filled rounded rect, corners default to 0 (sharp) if omitted
function M.filled_rect(cr, x, y, w, h, c, a, rtl, rtr, rbr, rbl)
    M.rounded_rect_path(cr, x, y, w, h, rtl or 0, rtr or 0, rbr or 0, rbl or 0)
    set_rgba(cr, c, a)
    cairo_fill(cr)
end

-- fully-rounded "stadium" pill (both ends fully round)
function M.pill(cr, x, y, w, h, c, a)
    local r = h / 2
    M.filled_rect(cr, x, y, w, h, c, a, r, r, r, r)
end

-- LCARS elbow bracket: a vertical arm and a horizontal arm sharing one
-- swept outer corner. corner = "tl" | "tr" | "bl" | "br" selects which
-- outer corner of the whole bracket is the rounded bend.
-- vx,vy,vw,vh   = vertical arm rectangle
-- hx,hy,hw,hh   = horizontal arm rectangle
function M.elbow(cr, corner, vx, vy, vw, vh, hx, hy, hw, hh, c, a)
    local bend = math.min(vw, hh)
    local rtl, rtr, rbr, rbl = 0, 0, 0, 0
    if corner == "tl" then rtl = bend
    elseif corner == "tr" then rtr = bend
    elseif corner == "br" then rbr = bend
    elseif corner == "bl" then rbl = bend
    end

    local v_tl, v_tr, v_br, v_bl = 0, 0, 0, 0
    if corner == "tl" or corner == "tr" then
        if corner == "tl" then v_tl = bend else v_tr = bend end
    else
        if corner == "bl" then v_bl = bend else v_br = bend end
    end
    M.filled_rect(cr, vx, vy, vw, vh, c, a, v_tl, v_tr, v_br, v_bl)

    local h_tl, h_tr, h_br, h_bl = 0, 0, 0, 0
    if corner == "tl" then h_tl = bend
    elseif corner == "tr" then h_tr = bend
    elseif corner == "bl" then h_bl = bend
    elseif corner == "br" then h_br = bend
    end
    M.filled_rect(cr, hx, hy, hw, hh, c, a, h_tl, h_tr, h_br, h_bl)
end

-- ---- text ----
local extents
local function get_extents()
    if not extents then
        extents = cairo_text_extents_t:create()
        tolua.takeownership(extents)
    end
    return extents
end

function M.text(cr, x, y, str, size, c, a, align, bold)
    str = tostring(str)
    cairo_select_font_face(cr, "sans-serif",
        CAIRO_FONT_SLANT_NORMAL,
        (bold == false) and CAIRO_FONT_WEIGHT_NORMAL or CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, size)

    local dx = 0
    if align == "right" or align == "center" then
        local ext = get_extents()
        cairo_text_extents(cr, str, ext)
        dx = (align == "right") and -ext.width or -ext.width / 2
    end

    set_rgba(cr, c, a)
    cairo_move_to(cr, x + dx, y)
    cairo_show_text(cr, str)
end

function M.text_width(cr, str, size, bold)
    str = tostring(str)
    cairo_select_font_face(cr, "sans-serif",
        CAIRO_FONT_SLANT_NORMAL,
        (bold == false) and CAIRO_FONT_WEIGHT_NORMAL or CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, size)
    local ext = get_extents()
    cairo_text_extents(cr, str, ext)
    return ext.width
end

-- ---- LCARS meter bar: dim track + filled portion, both pill-shaped ----
function M.bar(cr, x, y, w, h, pct, c)
    pct = math.max(0, math.min(100, pct or 0))
    M.pill(cr, x, y, w, h, M.color.dim, 1)

    local fw = w * (pct / 100)
    if fw <= 0 then return end

    cairo_save(cr)
    M.rounded_rect_path(cr, x, y, w, h, h / 2, h / 2, h / 2, h / 2)
    cairo_clip(cr)
    set_rgba(cr, c, 1)
    cairo_rectangle(cr, x, y, fw, h)
    cairo_fill(cr)
    cairo_restore(cr)
end

-- Small filled triangle
function M.triangle(cr, cx, cy, size, c, direction)
    local half = size / 2
    cairo_new_path(cr)
    if direction == "down" then
        cairo_move_to(cr, cx - half, cy - half)
        cairo_line_to(cr, cx + half, cy - half)
        cairo_line_to(cr, cx, cy + half)
    else
        cairo_move_to(cr, cx - half, cy + half)
        cairo_line_to(cr, cx + half, cy + half)
        cairo_line_to(cr, cx, cy - half)
    end
    cairo_close_path(cr)
    set_rgba(cr, c, 1)
    cairo_fill(cr)
end

-- Blocky/segmented history graph
function M.history_bars(cr, x, y, w, h, samples, max_val, c)
    local n = #samples
    if n == 0 or max_val <= 0 then return end
    local gap = 2
    local bw = (w - gap * (n - 1)) / n
    if bw <= 0 then return end

    local r = h / 2

    cairo_save(cr)
    M.rounded_rect_path(cr, x, y, w, h, r, r, r, r)
    cairo_clip(cr)

    for i, v in ipairs(samples) do
        local frac = math.max(0, math.min(1, (v or 0) / max_val))
        local bx = x + (i - 1) * (bw + gap)

        set_rgba(cr, M.color.dim, 1)
        cairo_rectangle(cr, bx, y, bw, h)
        cairo_fill(cr)

        local bh = h * frac
        if bh > 0 then
            set_rgba(cr, c, 1)
            cairo_rectangle(cr, bx, y + (h - bh), bw, bh)
            cairo_fill(cr)
        end
    end

    cairo_restore(cr)
end

-- ---- Starfleet Insignia Badge (Yellow Delta with Command Star in Circle) ----
-- Draws the classic yellow Starfleet Command badge enclosed in a ring background.
-- Centered on (cx, cy) with outer radius r.
function M.badge(cr, cx, cy, r, c, a)
    a = a or 1
    local yellow = M.color.yellow
    local dark = M.color.ink

    -- 1. Outer Ring (enclosing circle)
    cairo_new_path(cr)
    cairo_set_line_width(cr, math.max(r * 0.08, 1.8))
    set_rgba(cr, dark, a)
    cairo_arc(cr, cx, cy, r * 0.88, 0, 2 * math.pi)
    cairo_stroke(cr)

    -- 2. Delta Insignia Body (Curved Starfleet Arrowhead)
    local half = r * 0.62
    local top_y = cy - r * 0.95
    local base_y = cy + r * 0.82
    local notch_y = cy + r * 0.35

    cairo_new_path(cr)
    cairo_move_to(cr, cx, top_y)
    -- Right curved outer side
    cairo_curve_to(cr,
        cx + half * 0.80, cy - r * 0.25,
        cx + half * 1.15, base_y - r * 0.25,
        cx + half, base_y)
    -- Right inner curve to notch
    cairo_curve_to(cr,
        cx + half * 0.38, cy + r * 0.50,
        cx + r * 0.12, notch_y + r * 0.05,
        cx, notch_y)
    -- Left inner curve from notch
    cairo_curve_to(cr,
        cx - r * 0.12, notch_y + r * 0.05,
        cx - half * 0.38, cy + r * 0.50,
        cx - half, base_y)
    -- Left curved outer side back to top
    cairo_curve_to(cr,
        cx - half * 1.15, base_y - r * 0.25,
        cx - half * 0.80, cy - r * 0.25,
        cx, top_y)
    cairo_close_path(cr)

    -- Fill Yellow Delta
    set_rgba(cr, yellow, a)
    cairo_fill_preserve(cr)

    -- Dark Outline on Delta
    cairo_set_line_width(cr, math.max(r * 0.07, 1.5))
    set_rgba(cr, dark, a)
    cairo_stroke(cr)

    -- 3. Command Star in Center
    local star_cx = cx
    local star_cy = cy - r * 0.05
    local outer_r = r * 0.28
    local inner_r = r * 0.11

    cairo_new_path(cr)
    for i = 0, 4 do
        -- Outer point
        local angle_out = (i * 72 - 90) * math.pi / 180
        local x_out = star_cx + math.cos(angle_out) * outer_r
        local y_out = star_cy + math.sin(angle_out) * outer_r
        if i == 0 then
            cairo_move_to(cr, x_out, y_out)
        else
            cairo_line_to(cr, x_out, y_out)
        end

        -- Inner point
        local angle_in = (i * 72 + 36 - 90) * math.pi / 180
        local x_in = star_cx + math.cos(angle_in) * inner_r
        local y_in = star_cy + math.sin(angle_in) * inner_r
        cairo_line_to(cr, x_in, y_in)
    end
    cairo_close_path(cr)

    -- Fill main star shape
    set_rgba(cr, dark, a)
    cairo_fill(cr)
    
    -- Elongated top spike of the star
    local spike_top = star_cy - r * 0.42
    cairo_new_path(cr)
    cairo_move_to(cr, star_cx, spike_top)
    cairo_line_to(cr, star_cx + inner_r * 0.6, star_cy - inner_r)
    cairo_line_to(cr, star_cx - inner_r * 0.6, star_cy - inner_r)
    cairo_close_path(cr)
    cairo_fill(cr)
end

return M