local skynet = require "skynet.manager"
require "skynet.manager"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"

local gate
local CMD = {}
local SOCKET = {}

local agent_cnt
local login
local all_agent_list = {}
local subid = 0
local agent_idx = 1

local handshake = {}

local agent_create_cnt = 0

local acc2agent = {}
local uid2agent = {}

local function get_next_agent()
    local agent = all_agent_list[agent_idx]
    agent_idx = agent_idx + 1
    if agent_idx > agent_cnt then
        agent_idx = agent_cnt
    end
    return agent
end

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

function SOCKET.open(fd, addr)
    skynet.send(gate, "lua", "accept", fd)
    handshake[fd] = addr
end

function SOCKET.close(fd)
end

function SOCKET.error(fd, msg)
    SOCKET.close(fd)
end

function SOCKET.warning(fd, size)
end

local function do_auth(fd, msg)
    local acc, _ = string.match(msg, "([^@]+)@(.+)")
    local agent = get_next_agent()
    skynet.send(agent, "lua", "agent_login", acc, fd)
end

local function auth(fd, addr, msg)
    do_auth(fd, msg)
    local result = "200 OK"
    socket.write(fd, netpack.pack(result))
end

function SOCKET.data(fd, msg)
    local addr = handshake[fd]
    if addr then
        auth(fd,addr,msg)
        handshake[fd] = nil
    else
        -- TODO:
    end
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
    skynet.call(gate, "lua", "open" , conf)
end

function CMD.SIGHUP()
end

function CMD.watchdog_login(acc, ts)
    subid = subid + 1
    return subid
end

function CMD.acc_logout(...)
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

function CMD.agent_login_succ(acc, uid, fd, agent)
    acc2agent[acc] = {
        agent = agent,
        fd = fd,
        uid = uid,
    }
    uid2agent[uid] = {
        agent = agent,
        fd = fd,
        acc = acc,
    }
end

function CMD.send_agent_user(acc, uid, func_str, ...)
    local agent
    if acc then
        agent = acc2agent[acc]
    end
    if uid then
        agent = uid2agent[uid]
    end
    skynet.send(agent, "lua", func_str, acc, uid, ...)
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

