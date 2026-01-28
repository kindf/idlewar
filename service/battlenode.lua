require "skynet.manager"
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local common_util = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local function ServerBattleInit()
    skynet.error("ServerBattleInit")
    for i=1, 10 do
        local battleAgent = common_util.abort_new_service("battle_agent")
        skynet.name("battle_agent_"..i, battleAgent)
    end
end

skynet.start(function()
    skynet.newservice("debug_console", skynet.getenv("debug_console_port"))
    ServerBattleInit()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
end)
