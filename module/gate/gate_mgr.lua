local Logger = require "public.logger"
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

    local c = {}
    c.fd = fd
    c.ip = string.match(ip, "([%d.]+):(%d+)")
    c.agentnode = nil
    c.agentaddr = nil
    c.uid = nil
    connections[fd] = c
end

return GateMgr
