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
    black  = { 0.02, 0.02, 0.04 },
    ink    = { 0.05, 0.05, 0.08 }, -- near-black text on bright bars
    dim    = { 0.25, 0.20, 0.22 }, -- unfilled part of meter bars
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
-- (the two arms should overlap in the square corner area so the union
-- reads as one seamless bracket)
function M.elbow(cr, corner, vx, vy, vw, vh, hx, hy, hw, hh, c, a)
    local bend = math.min(vw, hh)
    local rtl, rtr, rbr, rbl = 0, 0, 0, 0
    if corner == "tl" then rtl = bend
    elseif corner == "tr" then rtr = bend
    elseif corner == "br" then rbr = bend
    elseif corner == "bl" then rbl = bend
    end

    -- vertical arm carries the rounded bend only where it sits at that
    -- same outer corner
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
-- Conky's tolua++ cairo bindings don't let cairo_text_extents() return a
-- table directly - it needs a real cairo_text_extents_t userdata as its
-- 3rd arg, which cairo doesn't expose a constructor for, so Conky adds
-- cairo_text_extents_t:create()/:free() helpers instead. Create ONE such
-- struct here and reuse it for every M.text() call for the widget's whole
-- lifetime (it's just overwritten each call) rather than create/free one
-- every single tick.
local extents
local function get_extents()
    if not extents then
        extents = cairo_text_extents_t:create()
        tolua.takeownership(extents)
    end
    return extents
end

-- align: "left" (default) | "right" | "center"
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

-- Rendered width of str at the given size/weight, using the same font
-- selection as M.text(). For laying out something next to text (e.g. a
-- graph that must not overlap it) without guessing a fixed column width.
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
-- pct expected 0..100
function M.bar(cr, x, y, w, h, pct, c)
    pct = math.max(0, math.min(100, pct or 0))
    M.pill(cr, x, y, w, h, M.color.dim, 1)

    local fw = w * (pct / 100)
    if fw <= 0 then return end

    -- Clip to the track's own pill outline, then fill a plain rectangle
    -- inside it. This guarantees the visible fill always follows the
    -- track's rounded silhouette exactly, even when fw is small (a
    -- separately-rounded small rect would need a smaller corner radius
    -- than the track's, so its square-ish corners poked out past the
    -- track's curve right at the rounded end).
    cairo_save(cr)
    M.rounded_rect_path(cr, x, y, w, h, h / 2, h / 2, h / 2, h / 2)
    cairo_clip(cr)
    set_rgba(cr, c, 1)
    cairo_rectangle(cr, x, y, fw, h)
    cairo_fill(cr)
    cairo_restore(cr)
end

-- Small filled triangle, centered on (cx, cy), pointing "up" or "down".
-- Drawn as a plain Cairo path rather than a Unicode glyph (e.g. \xE2\x96\xB2)
-- so it always renders identically regardless of which font is installed -
-- some fonts show geometric-shape codepoints as a blank/tofu box.
function M.triangle(cr, cx, cy, size, c, direction)
    local half = size / 2
    cairo_new_path(cr)
    if direction == "down" then
        cairo_move_to(cr, cx - half, cy - half)
        cairo_line_to(cr, cx + half, cy - half)
        cairo_line_to(cr, cx, cy + half)
    else -- "up"
        cairo_move_to(cr, cx - half, cy + half)
        cairo_line_to(cr, cx + half, cy + half)
        cairo_line_to(cr, cx, cy - half)
    end
    cairo_close_path(cr)
    set_rgba(cr, c, 1)
    cairo_fill(cr)
end

-- Blocky/segmented history graph, in the style of an LCARS "okudagram"
-- readout: a row of thin lit segments rather than a smooth curve, which
-- keeps it visually consistent with the pills/elbows used everywhere
-- else in this widget. samples[1] is the oldest value, samples[#samples]
-- the most recent; values are auto-clamped to [0, max_val]. Only the
-- outer left/right ends of the whole strip are rounded (matching the
-- other meter bars) - individual segments inside stay square.
function M.history_bars(cr, x, y, w, h, samples, max_val, c)
    local n = #samples
    if n == 0 or max_val <= 0 then return end
    local gap = 2
    local bw = (w - gap * (n - 1)) / n
    if bw <= 0 then return end

    local r = h / 2 -- rounds the strip's outer ends only

    cairo_save(cr)
    M.rounded_rect_path(cr, x, y, w, h, r, r, r, r)
    cairo_clip(cr)

    for i, v in ipairs(samples) do
        local frac = math.max(0, math.min(1, (v or 0) / max_val))
        local bx = x + (i - 1) * (bw + gap)

        -- dim backdrop segment (always visible, like an unlit LED column)
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

return M