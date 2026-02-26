local GateMgr = require "gate.gate_mgr"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local ClusterHelper = require "public.cluster_helper"
local ProtocolHelper = require "public.protocol_helper"
local DEFINE = require "public.define"
local SOCKET = {}

local DispatchFunc = {}
DispatchFunc[Pids["login.c2s_check_version"]] = function(conn, protoId, msg)
    GateMgr.HandleLoginCheckVersion(conn, protoId, msg)
end

DispatchFunc[Pids["login.c2s_login_auth"]] = function(conn, protoId, msg)
    GateMgr.HandleLoginAuth(conn, protoId, msg)
end

local function DispatchGame(conn, protoId, msg)
    if conn.status == DEFINE.CONNECTION_STATUS.GAMING or conn.status == DEFINE.CONNECTION_STATUS.AUTHED then
        local succ, err = ClusterHelper.TransmitMessage(conn, protoId, msg)
        if not succ then
            return Logger.Error("协议转发失败 pid:%s err:%s", protoId, err)
        end
    else
        Logger.Error("协议非法 fd:%s, pid:%s", conn.fd, protoId)
    end
end

local function Dispatch(conn, protoId, msg)
    if not protoId then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    if not Pids[protoId] then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    local fd = conn.fd
    assert(fd, "不存在的fd")
    local func = DispatchFunc[protoId] or DispatchGame
    if not func then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end
    func(conn, protoId, msg)
end

function SOCKET.open(fd, ip)
    local gateAccept = GateMgr.AddConnection(fd, ip)
    if gateAccept then
        gateAccept()
    end
    Logger.Info("连接成功 fd:%d ip:%s", fd, ip)
end

--收到socket关闭的通知
function SOCKET.close(fd)
    GateMgr.CloseConnection(fd, "SOCKET_CLOSE")
    Logger.Info("连接关闭 fd:%d", fd)
end

function SOCKET.error(fd, msg)
    GateMgr.CloseConnection(fd, "SOCKET_ERROR")
    SOCKET.close(fd)
end

function SOCKET.warning(fd, size)
    Logger.Warning("[SOCKET.warning] %d bytes havn't send out in fd[%d]", fd, size)
end

function SOCKET.data(fd, msg)
    Logger.Debug("[SOCKET.data] 收到数据 fd:%d", fd)
    local conn = GateMgr.GetConnection(fd)
    if not conn then
        return
    end
    local ok, err, buffMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, msg)
    if not ok then
        GateMgr.CloseConnection(conn.fd)
        return Logger.Error("协议解析失败 err:%s", err)
    end
    Dispatch(conn, err, buffMsg)
end

return SOCKET
