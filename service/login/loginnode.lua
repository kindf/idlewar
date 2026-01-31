local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local CommonUtil = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local CMD = {}

local function Init()
    local login = CommonUtil.abort_new_service("login")
    CommonUtil.assert_skynet_call(skynet.call, login, "lua", "start")
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.retpack(f(source, ...))
    end)
    Init()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
    skynet.error("Login service start")
    skynet.register(".loginnode")
end)
