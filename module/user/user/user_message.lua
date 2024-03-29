local skynet = require "skynet.manager"
local table_util = require "util.table_util"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local user_namager = require "user.user.user_manager"
local pb = require "pb"

local M = {}

local message_func = {}

function M.init_message_func()
    local func_list = require "user.user.message_func"
    for k, v in pairs(func_list) do
        for _, vv in pairs(v) do
            local mod = require(k)
            M.reg_message_func(vv, mod[vv])
        end
    end
    pb.loadfile("proto/pb/battle.pb")
end

function M.reg_message_func(name, func)
    --TODO: 重名问题
    message_func[name] = func
end

function M.dispatch(user, msg, sz)
    local m = skynet.tostring(msg, sz)
    local t = table_util.str2table(m)
    if not t then
        skynet.error("error msg. cant not to table")
        return false
    end
    local f = message_func[t.func_name or ""]
    if not f then
        skynet.error(string.format("error msg. func name:%s not exist.", t.func_name))
        return false
    end
    f(user, t)
    return true
end

function M.send_client_msg(user, t)
    local fd = user_namager.get_fd(user)
    if not fd then
        skynet.error("send_msg error. not fd. uid:", user.uid)
    end
    -- local msg = table_util.table2str(t)
    socket.write(fd, netpack.pack(t))
end

return M
