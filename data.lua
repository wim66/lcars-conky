--[[
    data.lua
    Gathers system data for the LCARS widget.

    Everything here relies on conky_parse() (Conky already computed the
    value internally - cheap) or a plain read of a small /proc file
    (also cheap, not equivalent to shelling out). Nothing here calls
    io.popen/os.execute, so it is safe to call every conky_main() tick
    without a caching guard.
--]]

local M = {}

local function parse_num(str)
    if not str then return 0 end
    str = str:gsub(",", ".") -- tolerate a locale decimal comma (e.g. "32654,2")
    return tonumber(str:match("[%d%.]+")) or 0
end

-- one-time (called from conky_startup): find the default-route network
-- interface by reading /proc/net/route, so the widget doesn't need a
-- hardcoded interface name.
function M.detect_default_iface()
    local f = io.open("/proc/net/route", "r")
    if not f then return "eth0" end
    local _ = f:read("*l") -- header
    for line in f:lines() do
        local iface, dest = line:match("^(%S+)%s+(%S+)")
        if iface and dest == "00000000" then
            f:close()
            return iface
        end
    end
    f:close()
    return "eth0"
end

-- one-time (called from conky_startup): logical CPU core count.
function M.detect_cpu_count()
    local f = io.open("/proc/cpuinfo", "r")
    if not f then return 4 end
    local n = 0
    for line in f:lines() do
        if line:match("^processor%s*:") then n = n + 1 end
    end
    f:close()
    return (n > 0) and n or 4
end

function M.cpu_overall()
    return parse_num(conky_parse("${cpu}"))
end

-- returns an array of per-core percentages, 1..count
function M.cpu_cores(count)
    local cores = {}
    for i = 1, count do
        cores[i] = parse_num(conky_parse("${cpu cpu" .. i .. "}"))
    end
    return cores
end

function M.mem()
    return {
        pct  = parse_num(conky_parse("${memperc}")),
        used = conky_parse("${mem}"),
        max  = conky_parse("${memmax}"),
    }
end

function M.fs(mount)
    mount = mount or "/"
    return {
        pct  = parse_num(conky_parse("${fs_used_perc " .. mount .. "}")),
        used = conky_parse("${fs_used " .. mount .. "}"),
        size = conky_parse("${fs_size " .. mount .. "}"),
    }
end

function M.net(iface)
    local down_str = conky_parse("${downspeedf " .. iface .. "}")
    local up_str = conky_parse("${upspeedf " .. iface .. "}")
    return {
        down = down_str,
        up = up_str,
        down_kib = parse_num(down_str), -- KiB/s, for the history graph
        up_kib = parse_num(up_str),
    }
end

-- top N processes by CPU, using Conky's own ${top ...} - no io.popen needed
function M.top_processes(n)
    local procs = {}
    for i = 1, n do
        local name = conky_parse("${top name " .. i .. "}")
        local cpu  = conky_parse("${top cpu " .. i .. "}")
        local mem  = conky_parse("${top mem " .. i .. "}")
        procs[i] = { name = name, cpu = cpu, mem = mem }
    end
    return procs
end

function M.uptime()
    return conky_parse("${uptime}")
end

-- "TNG-style" stardate: same "1000 units per year" mechanic used by the
-- commonly-cited fan formula (e.g. Ex Astris Scientia), but anchored at
-- 1966 - the year Star Trek (TOS) first aired - instead of the future
-- fictional year 2323. That keeps the result positive and in a
-- TNG-plausible range (this formula's real anchor gives ~41000+ for
-- 2364; anchoring 60 years earlier lands today in that same neighborhood)
-- while tying the epoch to something real rather than an arbitrary offset.
--
-- Still purely cosmetic flavor text - there is no official stardate
-- authority, and no anchor makes this a "real" Star Trek stardate.
local STARDATE_ANCHOR_YEAR = 1966

function M.stardate()
    local t = os.date("*t")
    local y = t.year
    local leap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
    local days_in_year = leap and 366 or 365
    local sd = (y - STARDATE_ANCHOR_YEAR) * 1000 + (t.yday - 1) / days_in_year * 1000
    return string.format("%.1f", sd)
end

return M