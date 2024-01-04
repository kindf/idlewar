local skynet = require "skynet"

local watchdog
local agent_idx

local CMD = {}
function CMD.start(conf)
    watchdog = conf.watchdog
    agent_idx = conf.idx

    skynet.send(watchdog, "lua", "add_agent", conf.idx, skynet.self())
    skynet.error("agent start finish. idx:%s", agent_idx)
end

function CMD.exit()
    skynet.error("agent going to exit succ. idx:", agent_idx)
    skynet.timeout(100, function()
        skynet.exit()
    end)
    return true
end

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

