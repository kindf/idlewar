local skynet = require "skynet.manager"
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

local function server_test_init()
    common_util.abort_new_service("test")
end

local server_init_func = {
    ["gameworld"] = server_gameworld_init,
    ["test"] = server_test_init,
}

skynet.start(function()
    skynet.register(".main")
    local server_type = skynet.getenv("server_type")
    skynet.error("server start. server_type:", server_type)
    local init_func = server_init_func[server_type]
    if not init_func then
        skynet.error("start error. not server_type:", server_type)
        skynet.sleep(1)
        skynet.abort()
    end
    init_func()
end)
