local Logger = require "public.logger"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local skynet = require "skynet"
local GateMgr = {}
local gate

local fd2Connection = {}
local uid2Connection = {}
local session2Connection = {}
local session = 0

local function GetNextSession()
    session = session + 1
    return session
end

function GateMgr.Init(ip, port)
    gate = skynet.newservice("gate")
    skynet.send(gate, "lua", "open", {
        host = ip,
        port = port,
    })
end

function GateMgr.GetConnection(fd)
    return fd2Connection[fd]
end

function GateMgr.AddConnection(fd, ip)
    if fd2Connection[fd] then
        return Logger.Error("GateMgr.AddConnection 连接已存在 fd=%s", fd)
    end

    local connection = {}
    connection.fd = fd
    connection.ip = string.match(ip, "([%d.]+):(%d+)")
    connection.agentNode = nil
    connection.agentAddr = nil
    connection.uid = nil
    connection.closeReason = nil
    connection.session = GetNextSession()
    fd2Connection[fd] = connection
    skynet.call(gate, "lua", "accept", fd)
end

function GateMgr.CloseConnection(fd, reason)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.CloseConnection 连接不存在 fd=%s", fd)
    end
    fd2Connection[fd] = nil
end

function GateMgr.BindAgent(fd, agentNode, agentAddr)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.BindAgent 连接不存在 fd=%s", fd)
    end
    connection.agentNode = agentNode
    connection.agentAddr = agentAddr
end

function GateMgr.CloseFd(fd, reason)
    local connection = fd2Connection[fd]
    if connection then
        connection.closeReason = reason
    end
    skynet.call(gate, "lua", "kick", fd)
end

function GateMgr.SendClientMessage(fd, msg)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.SendClientMessage 连接不存在 fd=%s", fd)
    end
    socket.write(fd, netpack.pack(msg))
end

return GateMgr
