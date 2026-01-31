local skynet = require "skynet"
require "skynet.manager"
local common_util = require "util.common_util"

local function server_gameworld_init()
    skynet.error("server_gameworld_init")
    local watchdog = common_util.abort_new_service("watchdog")
    local mongodb = common_util.abort_new_service("mongodb")
    local guid = common_util.abort_new_service("guid")
    common_util.assert_skynet_call(skynet.call, watchdog, "lua", "start", {agent_cnt = skynet.getenv("agent_cnt"), port = skynet.getenv("gate_port"), nodelay = true, maxclient  = 1000})
    skynet.fork(function()
        local host = skynet.getenv("db_host")
        local port = skynet.getenv("db_port")
        local username = skynet.getenv("db_uname")
        local pwd = skynet.getenv("db_pwd")
        common_util.assert_skynet_call(skynet.call, mongodb, "lua", "connect", host, port, username, pwd)
        common_util.assert_skynet_call(skynet.call, guid, "lua", "start")
    end)
end

skynet.start(function()
    skynet.register(".gameworld")
    skynet.newservice("debug_console", skynet.getenv("debug_console_port"))
    server_gameworld_init()
end)
