local skynet = require "skynet.manager"
local M = {}

local rpc_handler_funcs = {}

local function register_func(id, func)
    rpc_handler_funcs[id] = func
end

local function unpack(msg, sz)
    local m = skynet.tostring(msg, sz)
    local h = tonumber(string.sub(m, 1, 1))
    local l = tonumber(string.sub(m, 2, 2))
    local pid = h << 8 | l
    return pid, string.sub(m, 3)
end

function M.dispatch_c2s_message(user, msg, sz)
    local pid, data = unpack(msg, sz)
    local f = rpc_handler_funcs[pid]
    if not f then
        return skynet.error("not func. pid:", pid)
    end
    f(user, data)
end

local mod = require "user.battle.main"
register_func(1, mod.handle_c2s_battle)
register_func(3, mod.handle_c2s_echo)

return M
