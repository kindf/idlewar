local skynet = require "skynet"
local GateMgr = require "gate.gate_mgr"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local ClusterHelper = require "public.cluster_helper"
local ProtocolHelper = require "public.protocol_helper"
local DEFINE = require "public.define"
local SOCKET = {}

local DispatchFunc = {}
DispatchFunc[Pids["login.c2s_check_version"]] = function(session, protoId, msg)
    GateMgr:HandleLoginCheckVersion(session, protoId, msg)
end

DispatchFunc[Pids["login.c2s_login_auth"]] = function(session, protoId, msg)
    GateMgr:HandleLoginAuth(session, protoId, msg)
end

-- DispatchFunc[Pids["login.c2s_reconnect"]] = function(session, protoId, msg)
--     GateMgr.HandleReconnect(session.fd, msg)
-- end
--
-- DispatchFunc[Pids["login.c2s_logout"]] = function(session, protoId, msg)
--     GateMgr.HandleLogout(session.fd, msg)
-- end
--
local function DispatchGame(session, protoId, msg)
    local status = session:GetState()
    if status == DEFINE.CONN_STATE.GAMING or status == DEFINE.CONN_STATE.AUTHED then
        local succ, err = ClusterHelper.TransmitMessage(session, protoId, msg)
        if not succ then
            return Logger.Error("协议转发失败 pid:%s err:%s", protoId, err)
        end
    else
        Logger.Error("协议非法 fd:%s, pid:%s, status:%s", session:GetFd(), protoId, status)
    end
end

local function Dispatch(fd, protoId, msg)
    if not protoId then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    if not Pids[protoId] then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end

    local session = GateMgr:GetSession(fd)
    if not session then
        return Logger.Error("不存在的连接 fd:%s", fd)
    end

    local func = DispatchFunc[protoId] or DispatchGame
    if not func then
        return Logger.Error("不存在的协议号 pid:%s", protoId)
    end
    func(session, protoId, msg)
end

function SOCKET.open(fd, ip)
    local gate = GateMgr:AddSession(fd, ip)
    skynet.call(gate, "lua", "accept", fd)
    Logger.Info("连接成功 fd:%d ip:%s", fd, ip)
end

--收到socket关闭的通知
function SOCKET.close(fd)
    -- GateMgr:CloseSession(fd,"SOCKET_CLOSE")
    GateMgr:OnSocketClose(fd)
    Logger.Info("连接关闭 fd:%d", fd)
end

function SOCKET.error(fd, _)
    GateMgr:CloseSession(fd, "SOCKET_ERROR")
    SOCKET.close(fd)
end

function SOCKET.warning(fd, size)
    Logger.Warning("[SOCKET.warning] %d bytes havn't send out in fd[%d]", fd, size)
end

function SOCKET.data(fd, msg)
    local ok, err, buffMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, msg)
    if not ok then
        GateMgr:CloseFd(fd, "协议头解析失败")
        return Logger.Error("协议解析失败 err:%s", err)
    end
    Dispatch(fd, err, buffMsg)
end

return SOCKET
