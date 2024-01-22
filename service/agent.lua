local skynet = require "skynet"
local user_namager = require "user.user_manager"
local user = require "user.user"
local user_message = require("user.user_message")
local agent_name = ...

local watchdog
local gate
local agent_idx

local online_users = {}
local fd2uid = {}

local CMD = {}
function CMD.start(conf)
    watchdog = conf.watchdog
    agent_idx = conf.idx
    gate = conf.gate

    user_message.init()

    skynet.send(watchdog, "lua", "add_agent", conf.idx, skynet.self())
    skynet.error("agent start finish. idx:%s name%s", agent_idx, agent_name)
end

function CMD.exit()
    skynet.error("agent going to exit succ. idx:", agent_idx)
    skynet.timeout(100, function()
        skynet.exit()
    end)
    return true
end

function CMD.agent_login(acc, fd)
    --用户已存在
    local user_data = user_namager.load_create_user_data(acc)

    if not user_data then
        return "405 User Load Data Error"
    end

    local uid = user_data.uid
    if online_users[uid] then
        return "404 User Have Logined"
    end

    local u = user.new()
    u:init(user_data)

    user_namager.add_user(u)
    --将gate的信息重定向到该agent
    online_users[uid] = {}
    fd2uid[fd] = uid
    skynet.send(gate, "lua", "forward", fd)
    --通知watchdog登录成功
    skynet.send(watchdog, "lua", "agent_login_succ", acc, uid, fd, skynet.self())
end

function CMD.agent_logout(uid)
    online_users[uid] = nil
    skynet.send(watchdog, "lua", "agent_logout_succ", uid)
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function (msg, sz) return msg, sz end,
    dispatch = function (fd,_,msg, sz)
        skynet.ignoreret()
        local uid = fd2uid[fd]
        local u = user_namager.get_user(uid)
        if u then
            user_message.dispatch(u, msg, sz)
        else
            skynet.error("User Not Found. uid:", uid)
        end
        skynet.error(string.format("fd:%s, msg:%s, sz:%s", fd, msg, sz))
    end
}

skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        local f = CMD[command]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error("invalid cmd. cmd:%s", command)
        end
    end)
end)
