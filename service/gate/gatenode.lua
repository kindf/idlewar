local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local CommonUtil = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local function ServerInit()
    local watchdog = CommonUtil.abort_new_service("gatewatchdog")
    CommonUtil.assert_skynet_call(skynet.call, watchdog, "lua", "start", {port = skynet.getenv("gate_port")})
end

skynet.start(function()
    skynet.newservice("debug_console", skynet.getenv("debug_console_port"))
    ServerInit()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
end)
