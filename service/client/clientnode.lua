local skynet = require "skynet.manager"

skynet.start(function()
    local agent = skynet.newservice("client_agent")
    skynet.error("clientnode start")
    skynet.fork(function()
        skynet.call(agent, "lua", "start", {})
    end)
end)
