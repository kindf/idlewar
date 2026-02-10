local GateMgr = require "gate.gate_mgr"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local ClusterHelper = require "public.cluster_helper"
local ProtocolHelper = require "public.protocol_helper"
local DEFINE = require "define"
local SOCKET = {}

local function HandleReconnect(fd)
    local c = GateMgr.GetConnection(fd)
    if c then
        c.lastActiveTime = os.time()
    end
end

local function HandleHeartbeat(fd)
    local c = GateMgr.GetConnection(fd)
    if c then
        c.lastActiveTime = os.time()
    end
end

local function Dispatch(c, protoId, msg)
    if not protoId then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    if not Pids[protoId] then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    local fd = c.fd
    assert(fd, "不存在的fd")
    if protoId == Pids["login.c2s_check_version"] then
        GateMgr.HandleLoginCheckVersion(fd, protoId, msg)
    elseif protoId == Pids["login.c2s_login_auth"] then
        GateMgr.HandleLoginCheckAuth(fd, protoId, msg)
    elseif protoId == Pids["login.c2s_reconnect"] then
        HandleReconnect(fd)
    elseif protoId == Pids["gate.c2s_heartbeat"] then
        HandleHeartbeat(fd)
    elseif c.status == DEFINE.CONNECTION_STATUS.GAMING then
        local succ, err = ClusterHelper.TransmitMessage(c, protoId, msg)
        if not succ then
            return Logger.Error("协议转发失败 pid:%s err:%s", protoId, err)
        end
        Logger.Debug("协议转发成功 pid:%s", protoId)
    else
        Logger.Error("协议非法 pid:%s", protoId)

    end
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
    local c = GateMgr.GetConnection(fd)
    if not c then
        return
    end
    local ok, err, buffMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, msg)
    if not ok then
        GateMgr.CloseConnection(c.fd)
        return Logger.Error("协议解析失败 err:%s", err)
    end
    Dispatch(c, err, buffMsg)
end

return SOCKET
