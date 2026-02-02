local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local commonUtil = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local function ServerGameworldInit()
    skynet.error("ServerGameworldInit")
    local watchdog = commonUtil.abort_new_service("watchdog")
    local mongodb = commonUtil.abort_new_service("mongodb")
    local guid = commonUtil.abort_new_service("guid")
    local host = skynet.getenv("db_host")
    local port = skynet.getenv("db_port")
    local username = skynet.getenv("db_uname")
    local pwd = skynet.getenv("db_pwd")
    commonUtil.assert_skynet_call(skynet.call, watchdog, "lua", "start",{ agent_cnt = skynet.getenv("agent_cnt"), port = skynet.getenv("gate_port"), nodelay = true, maxclient = 1000 })
    commonUtil.assert_skynet_call(skynet.call, mongodb, "lua", "connect", host, port, username, pwd)
    commonUtil.assert_skynet_call(skynet.call, guid, "lua", "start")
end

skynet.start(function()
    skynet.register(".gamenode")
    skynet.newservice("debug_console", skynet.getenv("debug_console_port"))
    ServerGameworldInit()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
end)
