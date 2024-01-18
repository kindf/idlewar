local skynet = require "skynet.manager"
local common_util = require "util.common_util"

local function server_gameworld_init()
    skynet.error("server_gameworld_init")
    local watchdog = common_util.abort_new_service("watchdog")
    common_util.abort_new_service("mongodb")
    common_util.assert_skynet_call(skynet.call, watchdog, "lua", "start", {agent_cnt = skynet.getenv("agent_cnt"), port = 8888, nodelay = true, maxclient  = 1000})
end

local function server_center_init()
    skynet.error("server_center_init")
end

local server_init_func = {
    ["gameworld"] = server_gameworld_init,
    ["center"] = server_center_init,
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
