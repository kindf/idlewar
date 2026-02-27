local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local Logger = require "public.logger"
local DEFINE = require "public.define"
local RetCode = require "proto.retcode"
local ProtocolHelper = require "public.protocol_helper"
local ClusterHelper = require "public.cluster_helper"
local SessionMgr = require "gate.session_mgr"
local TokenMgr = require "gate.token_mgr"
local Timer = require "public.timer"
local CONN_STATE = DEFINE.CONNECTION_STATUS

local GateMgr = {
    gate = nil,
    timer = Timer.New(),
    cleanupTimerId = nil,
}

function GateMgr:Init(ip, port)
    self.gate = skynet.newservice("gate")
    skynet.send(self.gate, "lua", "open", {
        host = ip,
        port = port,
    })

    ProtocolHelper.RegisterProtocol()
    self.cleanupTimerId = self.timer:Interval(DEFINE.SESSION_CLEANUP_INTERVAL, function() GateMgr:CleanupTimer() end, false)
    SessionMgr:SetGate(self.gate)
    Logger.Info("GateMgr 初始化成功 on %s:%d", ip, port)
end

function GateMgr:CleanupTimer()
    SessionMgr:Cleanup()
    TokenMgr:Cleanup()

    local stats = SessionMgr:GetStats()
    Logger.Info("GateMgr stats - active:%d waiting:%d",
        stats.active, stats.waitingReconnect)
end

-- 连接管理
function GateMgr:AddSession(fd, ip)
    SessionMgr:Add(fd, ip)
    return self.gate
end

function GateMgr:GetSession(fd)
    return SessionMgr:GetByFd(fd)
end

-- fd关闭回调
function GateMgr:CloseSession(fd, reason)
    SessionMgr:Close(fd, reason)
end

-- 主动断开
function GateMgr:CloseFd(fd)
    skynet.call(self.gate, "lua", "kick", fd)
end

function GateMgr:SendMessage(fd, msg)
    local session = SessionMgr:GetByFd(fd)
    if not session then
        Logger.Warn("GateMgr.SendMessage no session fd=%s", fd)
        return false
    end

    local currentFd = session.fd
    if currentFd ~= fd then
        Logger.Debug("GateMgr.SendMessage fd changed: %s -> %s", fd, currentFd)
    end

    local ok, err = pcall(socket.write, currentFd, netpack.pack(msg))
    if not ok then
        Logger.Error("GateMgr.SendMessage failed fd=%s err=%s", currentFd, err)
        SessionMgr:Close(currentFd, "send failed")
        return false
    end

    session:UpdateActiveTime()
    return true
end

-- 检查版本号
function GateMgr:HandleLoginCheckVersion(session, _, msg)
    local resp = { retCode = RetCode.SUCCESS }
    repeat
        if session:GetState() ~= CONN_STATE.INIT then
            resp.retCode = RetCode.SESSION_STATE_ERROR
            break
        end

        local ok, result = ClusterHelper.CallLoginNode(".login", "CheckVersion", msg)
        if not ok then
            Logger.Error("GateMgr.HandleLoginCheckVersion rpc failed")
            resp.retCode = RetCode.SYSTEM_ERROR
            break
        end

        resp.retCode = result
        if result == RetCode.SUCCESS then
            ok = session:ChangeState(CONN_STATE.VERSION_CHECKED)
            if not ok then
                resp.retCode = RetCode.SESSION_STATE_ERROR
                break
            end
        end
    until true
    local pack = ProtocolHelper.Encode("login.s2c_check_version", resp)
    GateMgr:SendMessage(session.fd, pack)
end

-- 登录认证
function GateMgr:HandleLoginAuth(session, _, msg)
    local resp = { retCode = RetCode.SUCCESS }

    repeat
        if not session:ChangeState(CONN_STATE.LOGINING) then
            resp.retCode = RetCode.SESSION_STATE_ERROR
            break
        end
        local ok, result = ClusterHelper.CallLoginNode(".login", "CheckAuth", msg)
        if not ok then
            Logger.Error("GateMgr.HandleLoginAuth rpc failed")
            resp.retCode = RetCode.SYSTEM_ERROR
            session:ChangeState(CONN_STATE.VERSION_CHECKED)
            break
        end

        if result.retCode == RetCode.SUCCESS then
            local sessionId = SessionMgr:Authenticate(session:GetFd(), result.account)
            if sessionId then
                resp.sessionId = sessionId
                TokenMgr:Add(sessionId, result.account)
            else
                resp.retCode = RetCode.FAILED
            end
        else
            session:ChangeState(CONN_STATE.VERSION_CHECKED)
            resp.retCode = result.retCode
        end
    until true
    local pack = ProtocolHelper.Encode("login.s2c_login_auth", resp)
    GateMgr:SendMessage(session.fd, pack)
end

function GateMgr.HandleReconnect(fd, msg)
    local sessionId = msg.sessionId
    local account = msg.account

    local session, err = SessionMgr:HandleReconnect(fd, sessionId, account)

    local resp = { retCode = RetCode.SUCCESS }
    if not session then
        resp.retCode = RetCode.RECONNECT_FAILED
        resp.msg = err or "reconnect failed"
    else
        resp.retCode = RetCode.SUCCESS
        resp.sessionId = sessionId
    end

    local pack = ProtocolHelper.Encode("login.s2c_reconnect", resp)
    GateMgr:SendMessage(fd, pack)
end

function GateMgr.EnterGame(sessionId, uid)
    local succ = SessionMgr:BindUid(sessionId, uid)
    return succ
end

function GateMgr.VerifyToken(account, token)
    return TokenMgr:Verify(token, account)
end

function GateMgr.OnDisconnect(fd, reason)
    SessionMgr:HandleDisconnect(fd, reason)
end

-- 调试接口
function GateMgr.DebugGetSessions()
    local list = {}
    for fd, session in pairs(SessionMgr.fd2Session) do
        table.insert(list, session:ToLogString())
    end
    return list
end

function GateMgr.DebugGetWaiting()
    local list = {}
    for sid, info in pairs(SessionMgr.waitingReconnect) do
        table.insert(list, string.format("%s timeout=%d", sid, info.timeout))
    end
    return list
end

return GateMgr
