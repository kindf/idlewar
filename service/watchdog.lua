local skynet = require "skynet.manager"
require "skynet.manager"

local gate
local CMD = {}
local SOCKET = {}

local agent_cnt
local login
local all_agent_list = {}

local agent_create_cnt = 0

local function abort_new_service(name, ...)
    local ok, ret = pcall(skynet.newservice, name, ...)
    if not ok then
        skynet.error(name, " start error.", ret)
        skynet.sleep(1)
        skynet.abort()
    else
        skynet.error(name, " start...")
    end
    return ret
end

local function auth_loginkey(fd, message)
end

function SOCKET.open(fd, addr)
end

function SOCKET.close(fd)
end

function SOCKET.error(fd, msg)
    SOCKET.close(fd)
end

function SOCKET.warning(fd, size)
end

function SOCKET.data(fd, msg)
end

function CMD.start(conf)
    agent_cnt = tonumber(conf.agent_cnt)
    assert(agent_cnt > 0, "invalid agent count")
    for i = 1, agent_cnt do
        skynet.fork(function()
            local agent = abort_new_service("agent", 'idx-'..i)
            skynet.call(agent, "lua", "start", { gate = gate, watchdog = skynet.self(), idx = i})
        end)
    end
end

function CMD.SIGHUP()
end

function CMD.acc_login(...)
    return 1
end

function CMD.add_agent(idx, agent)
    agent_create_cnt = agent_create_cnt + 1
    assert(all_agent_list[idx] == nil)
    all_agent_list[idx] = agent
    if agent_create_cnt == agent_cnt then
        login = abort_new_service("login", skynet.self())
        skynet.error("new login: ", login)
    end
    skynet.error("add agent. index: ", idx, " agent:", agent)
end

skynet.start(function()
    skynet.register(".watchdog")
    skynet.dispatch("lua", function(_, _, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
        else
            local f = assert(CMD[cmd], "invalid cmd:"..tostring(cmd))
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
    gate = abort_new_service("gate", "game")
end)

