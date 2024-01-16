local skynet = require "skynet"
local agent_name = ...

local watchdog
local gate
local agent_idx
local uid = 0

local CMD = {}
function CMD.start(conf)
    watchdog = conf.watchdog
    agent_idx = conf.idx
    gate = conf.gate

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
    uid = uid + 1
    skynet.send(gate, "lua", "forward", fd)
    skynet.send(watchdog, "lua", "agent_login_succ", acc, uid, fd, skynet.self())
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function (msg, sz) return msg, sz end,
    dispatch = function (fd,_,msg, sz)
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
