local skynet = require "skynet.manager"
local pname2pid = require "proto.pids"
local M = {}

local rpc_handler_funcs = {}

local function register_func(name, func)
    local id = pname2pid[name]
    rpc_handler_funcs[id] = func
end

function M.rpc_unpack(msg, sz)
    local m = skynet.tostring(msg, sz)
    local h = string.byte(string.sub(m, 1, 1))
    local l = string.byte(string.sub(m, 2, 2))
    local pid = h << 8 | l
    return pid, string.sub(m, 3)
end

function M.dispatch_c2s_message(user, pid, data)
    local f = rpc_handler_funcs[pid]
    if not f then
        return skynet.error("not func. pid:", pid)
    end
    f(user, data)
end

local mod = require "user.battle.main"
register_func("battle.c2s_battle", mod.handle_c2s_battle)
register_func("battle.c2s_echo", mod.handle_c2s_echo)

return M
