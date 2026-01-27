require "skynet.manager"
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local common_util = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local function ServerBattleInit()
    skynet.error("ServerBattleInit")
    local battleAgent = common_util.abort_new_service("battle_agent")
end

skynet.start(function()
    skynet.newservice("debug_console", skynet.getenv("debug_console_port"))
    ServerBattleInit()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
end)
