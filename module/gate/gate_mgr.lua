local Logger = require "public.logger"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local skynet = require "skynet"
local GateMgr = {}
local gate

local connections = {}

function GateMgr.Init(ip, port)
    gate = skynet.newservice("gate")
    skynet.send(gate, "lua", "open", {
        host = ip,
        port = port,
    })
end

function GateMgr.GetConnection(fd)
    return connections[fd]
end

function GateMgr.AddConnection(fd, ip)
    if connections[fd] then
        return Logger.Error("GateMgr.AddConnection 连接已存在 fd=%s", fd)
    end

    local connection = {}
    connection.fd = fd
    connection.ip = string.match(ip, "([%d.]+):(%d+)")
    connection.agentnode = nil
    connection.agentaddr = nil
    connection.uid = nil
    connection.reason = nil
    connections[fd] = connection
    skynet.call(gate, "lua", "accept", fd)
end

function GateMgr.CloseConnection(fd, reason)
    local connection = connections[fd]
    if not connection then
        return Logger.Error("GateMgr.CloseConnection 连接不存在 fd=%s", fd)
    end
    connections[fd] = nil
end

function GateMgr.CloseFd(fd, reason)
    local connection = connections[fd]
    if connection then
        connection.closeReason = reason
    end
    skynet.call(gate, "lua", "kick", fd)
end

function GateMgr.SendClientMessage(fd, msg)
    local connection = connections[fd]
    if not connection then
        return Logger.Error("GateMgr.SendClientMessage 连接不存在 fd=%s", fd)
    end
    socket.write(fd, netpack.pack(msg))
end

return GateMgr
