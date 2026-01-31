require "skynet.manager"
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local common_util = require "util.common_util"
local nodeName = skynet.getenv("nodename")

local CMD = {}
local SOCKET = {}
local gate

function SOCKET.open(fd, addr)
    skynet.error("New client from : " .. addr)
    skynet.call(gate, "lua", "accept", fd)
end

local function close_agent(fd)
    skynet.call(gate, "lua", "kick", fd)
    cluster.send("gamenode", "agent_mgr", "disconnect")
end

function SOCKET.close(fd)
    print("socket close", fd)
    close_agent(fd)
end

function SOCKET.error(fd, msg)
    print("socket error", fd, msg)
    close_agent(fd)
end

function SOCKET.warning(fd, size)
    -- size K bytes havn't send out in fd
    print("socket warning", fd, size)
end

function SOCKET.data(fd, msg)
    -- 分发
    local msgId = string.unpack(">I2", msg, 1)
    local msgBody = msg:sub(3)
    if msgId < 10000 then
        cluster.call("loginnode", "login", "socket", fd, msgId, msgBody)
        return
    end
    cluster.call("gamenode", "agent_mgr", "socket", fd, msgId, msgBody)
end

function CMD.start(conf)
    return skynet.call(gate, "lua", "open", conf)
end

function CMD.close(fd)
    close_agent(fd)
end

skynet.start(function()
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)

    gate = skynet.newservice("gate")
end)
