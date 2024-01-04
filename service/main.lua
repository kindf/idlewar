local skynet = require "skynet.manager"

local function server_gameworld_init()
    skynet.error("server_gameworld_init")
    local watchdog = skynet.uniqueservice("watchdog")
    local ok, err = pcall(skynet.call, watchdog, "lua", "start", {})
    if not ok then
        skynet.error("watchdog start error:", err)
        skynet.sleep(1)
        skynet.abort()
    else
        skynet.error("watchdog start...")
    end
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
