local skynet = require "skynet.manager"
require "skynet.manager"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local common_util = require "util.common_util"

local gate
local CMD = {}
local SOCKET = {}

local agent_cnt
local login
local all_agent_list = {}

local original_subid = 0
local agent_idx = 1


local agent_create_cnt = 0

--已通过login认证，但是还没连接到gate的acc
local login_acc = {}

local handshake = {}
local acc2agent = {}
local uid2agent = {}
local fd2agent = {}

local function get_login_key(acc, subid)
    return string.format("%s@%s", acc, subid)
end

local function get_next_agent()
    local agent = all_agent_list[agent_idx]
    agent_idx = agent_idx + 1
    if agent_idx > agent_cnt then
        agent_idx = agent_cnt
    end
    return agent
end

-- 用户连接上gate时调用
function SOCKET.open(fd, addr)
    skynet.send(gate, "lua", "accept", fd)
    handshake[fd] = addr
end

function SOCKET.close(fd)
    --TODO: 重连
    skynet.error(fd)
    local a = fd2agent[fd]
    if a then
        skynet.send(a.agent, "lua", "agent_logout", a.uid)
    end
end

function SOCKET.error(fd, msg)
    SOCKET.close(fd)
end

function SOCKET.warning(fd, size)
    skynet.error("socket msg too large. fd:", fd)
end

local function do_auth(fd, msg)
    local acc, subid = string.match(msg, "([^@]+)@(.+)")
    local key = get_login_key(acc, subid)
    if not login_acc[key] then
        return "404 User Not Login"
    end
    local agent = get_next_agent()
    local ret = skynet.call(agent, "lua", "agent_login", acc, fd)
    return ret
end

local function auth(fd, addr, msg)
    local _, result = pcall(do_auth, fd, msg)
    if not result then
        result = "200 OK"
    end
    socket.write(fd, netpack.pack(result))
end

function SOCKET.data(fd, msg)
    local addr = handshake[fd]
    if addr then
        auth(fd,addr,msg)
        handshake[fd] = nil
    else
        skynet.error("error data...", msg)
        skynet.send(gate, "lua", "kick", fd)
    end
end

function CMD.start(conf)
    agent_cnt = tonumber(conf.agent_cnt)
    assert(agent_cnt > 0, "invalid agent count")
    for i = 1, agent_cnt do
        skynet.fork(function()
            local agent = common_util.abort_new_service("agent", 'idx-'..i)
            skynet.call(agent, "lua", "start", { gate = gate, watchdog = skynet.self(), idx = i})
        end)
    end
    --启动gate
    skynet.call(gate, "lua", "open" , conf)
end

function CMD.SIGHUP()
end

function CMD.watchdog_login(acc, ts)
    original_subid = original_subid + 1
    local key = get_login_key(acc, original_subid)
    login_acc[key] = acc
    return original_subid
end

function CMD.add_agent(idx, agent)
    agent_create_cnt = agent_create_cnt + 1
    assert(all_agent_list[idx] == nil)
    all_agent_list[idx] = agent
    if agent_create_cnt == agent_cnt then
        login = common_util.abort_new_service("login", skynet.self())
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
    fd2agent[fd] = {
        agent = agent,
        uid = uid,
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

function CMD.agent_logout_succ(uid)
    skynet.send(gate, "lua", "kick", uid2agent[uid].fd)
end

function CMD.watchdog_logout(acc)
    skynet.send(acc2agent[acc].agent, "lua", "agent_logout", acc2agent[acc].uid)
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
    gate = common_util.abort_new_service("gate", "game")
end)
