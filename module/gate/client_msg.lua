local cluster = require "skynet.cluster"
local skynet = require "skynet"
local socket = require "skynet.socket"
local GateMgr = require "gate.gate_mgr"
local Pids = require "proto.pids"
local ServerPids = require "proto.serverpids"
local Logger = require "public.logger"
local RpcHelper = require "util.rpc_helper"
local ClusterHelper = require "public.cluster_helper"
local SOCKET = {}

function get_context(c)
    local ctx = {}
    ctx.gate = cluster_monitor.get_current_nodename()
    ctx.watchdog = skynet.self()
    ctx.is_websocket = GateMgr.is_websocket()
    ctx.fd = c.fd
    ctx.ip = c.ip
    ctx.session = c.session
    ctx.player_id = c.player_id
    return ctx
end

local function Dispatch(c, protoId, msg)
    if not protoId then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    if not Pids[protoId] then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    local succ, err = ClusterHelper.TransmitMessage(c, protoId, msg)
    if not succ then
        return Logger.Error("协议转发失败 pid:%s err:%s", protoId, err)
    end
    Logger.Debug("协议转发成功 pid:%s", protoId)
end

local function DispatchData(c, msg)
    local protoId, buffMsg
    local ok, err = xpcall(function()
        protoId, buffMsg = RpcHelper.UnpackHeader(msg)
        Dispatch(c, protoId, buffMsg)
    end, debug.traceback)
    if not ok then
        GateMgr.CloseConnection(c.fd)
        return Logger.Error("协议解析失败 err:%s", err)
    end
end


function SOCKET.open(fd, ip)
    GateMgr.AddConnection(fd, ip)
end

--收到socket关闭的通知
function SOCKET.close(fd)
    GateMgr.CloseConnection(fd, "SOCKET_CLOSE")
end

function SOCKET.error(fd, msg)
    GateMgr.CloseConnection(fd, "SOCKET_ERROR")
end

function SOCKET.warning(fd, size)
    Logger.Warning("%d bytes havn't send out in fd[%d]", fd, size)
end

function SOCKET.data(fd, msg)
    local c = GateMgr.GetConnection(fd)
    if not c then
        return
    end
    DispatchData(c, msg)
end

return SOCKET
