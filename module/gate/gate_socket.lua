local socket = require "skynet.socket"
local GateMgr = require "gate.gate_mgr"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local RpcHelper = require "util.rpc_helper"
local ClusterHelper = require "public.cluster_helper"
local SOCKET = {}

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
    local ok, err, buffMsg = xpcall(function()
        return RpcHelper.UnpackHeader(msg)
    end, debug.traceback)
    if not ok then
        GateMgr.CloseConnection(c.fd)
        return Logger.Error("协议解析失败 err:%s", err)
    end
    Dispatch(c, err, buffMsg)
end


function SOCKET.open(fd, ip)
    GateMgr.AddConnection(fd, ip)
    Logger.Info("连接成功 fd:%d ip:%s", fd, ip)
end

--收到socket关闭的通知
function SOCKET.close(fd)
    GateMgr.CloseConnection(fd, "SOCKET_CLOSE")
end

function SOCKET.error(fd, msg)
    GateMgr.CloseConnection(fd, "SOCKET_ERROR")
end

function SOCKET.warning(fd, size)
    Logger.Warning("[SOCKET.warning] %d bytes havn't send out in fd[%d]", fd, size)
end

function SOCKET.data(fd, msg)
    Logger.Debug("[SOCKET.data] 收到数据 fd:%d", fd)
    local c = GateMgr.GetConnection(fd)
    if not c then
        return
    end
    DispatchData(c, msg)
end

return SOCKET
