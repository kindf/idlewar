require "skynet.manager"
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local CommonUtil = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local function ServerBattleInit()
    skynet.error("ServerBattleInit")
    for i=1, 10 do
        local battleAgent = CommonUtil.abort_new_service("battle_agent")
        skynet.name("battle_agent_"..i, battleAgent)
    end
end

skynet.start(function()
    ServerBattleInit()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
end)
