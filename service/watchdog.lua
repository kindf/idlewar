local skynet = require "skynet.manager"
require "skynet.manager"

local CMD = {}
local SOCKET = {}

local agent_cnt
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
    agent_cnt = skynet.getenv("agent_cnt")
    assert(agent_cnt > 0, "invalid agent count")
    for i = 1, agent_cnt do
        skynet.fork(function()
            abort_new_service("agent", 'idx-'..i..'-'..agent_create_cnt)
        end)
    end
end

function CMD.SIGHUP()
end

function CMD.add_agent(idx, agent)
    agent_create_cnt = agent_create_cnt + 1
    assert(all_agent_list[idx] == nil)
    all_agent_list[idx] = {
        agent = agent,
    }
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
end)

