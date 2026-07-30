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

-- one-time (called from conky_startup): distro display name from
-- /etc/os-release, so the footer doesn't hardcode "Arch Linux".
function M.detect_distro_name()
    local f = io.open("/etc/os-release", "r")
    if not f then return "Linux" end
    local name, pretty
    for line in f:lines() do
        local k, v = line:match("^(%u+)=(.*)$")
        if k and v then
            v = v:gsub('^"(.*)"$', "%1") -- strip surrounding quotes if present
            if k == "PRETTY_NAME" then pretty = v
            elseif k == "NAME" then name = v
            end
        end
    end
    f:close()
    return pretty or name or "Linux"
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

-- purely decorative "stardate" readout in the LCARS house style.
-- Cosmetic only - not a real Star Trek stardate authority, just flavor.
function M.stardate()
    local t = os.date("*t")
    -- Cosmetic only: not a real Star Trek stardate authority (those only
    -- make sense for the 23rd/24th century), just a fun always-positive
    -- five-digit-ish readout in the house style, e.g. "26214.8".
    local base = (t.year % 100) * 1000
    local frac = (t.yday - 1) * (1000 / 365)
    return string.format("%05.1f", base + frac)
end

return M