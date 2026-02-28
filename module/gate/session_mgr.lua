local skynet = require "skynet"
local Logger = require "public.logger"
local Session = require "gate.session"
local DEFINE = require "public.define"
local ClusterHelper = require "public.cluster_helper"
local STATE_TRANSITIONS = require "module.gate.session_state_machine"
local CONN_STATE = DEFINE.CONN_STATE

-- SessionManager
local SessionManager = {
    fd2Session = {},       -- fd -> Session
    sid2Session = {},      -- sessionId -> Session
    account2Sid = {},      -- account -> sessionId
    waitingReconnect = {}, -- sessionId -> {session, timeout}
    seqCounter = 0,
    totalCreated = 0,
    totalClosed = 0,
    gateMgr = nil,
}

function SessionManager:SetGateMgr(gateMgr)
    self.gateMgr = gateMgr
end

function SessionManager:GetNextSeq()
    self.seqCounter = self.seqCounter + 1
    return self.seqCounter
end

function SessionManager:Add(fd, ip)
    if self.fd2Session[fd] then
        Logger.Warn("SessionManager:Add duplicate fd=%s, closing", fd)
        self:Close(fd, "duplicate")
    end

    local session = Session.New(fd, ip)
    self.fd2Session[fd] = session
    self.totalCreated = self.totalCreated + 1

    Logger.Debug("SessionManager:Add %s", session:ToLogString())
    return session
end

function SessionManager:GetByFd(fd)
    return self.fd2Session[fd]
end

function SessionManager:GetBySid(sessionId)
    return self.sid2Session[sessionId]
end

function SessionManager:GetByAccount(account)
    local sessionId = self.account2Sid[account]
    if sessionId then
        return self.sid2Session[sessionId]
    end
    return nil
end

function SessionManager:Authenticate(fd, account)
    local session = self.fd2Session[fd]
    if not session then
        Logger.Error("SessionManager:Authenticate no session fd=%s", fd)
        return nil
    end

    -- 处理顶号
    local existingSid = self.account2Sid[account]
    if existingSid then
        local existingSession = self.sid2Session[existingSid]
        if existingSession and existingSession:IsAlive() then
            Logger.Info("SessionManager:Authenticate account=%s 顶号 踢除旧号中", account)
            -- skynet.send(self.gate, "lua", "kick", existingSession.fd)
            -- -- 通知AgentMgr顶号
            -- self:KickAgent(account, "new login")
            -- -- 清理旧session
            -- self:Close(existingSession.fd, "new login")

            self.gateMgr:KickOldConnection(existingSession)
        end
    end

    -- 生成sessionId
    local sessionId = session:GenerateSessionId(self:GetNextSeq())
    session:SetAccount(account)
    session:ChangeState(CONN_STATE.AUTHED)

    -- 建立映射
    self.sid2Session[sessionId] = session
    self.account2Sid[account] = sessionId

    Logger.Info("SessionManager:Authenticate success %s", session:ToLogString())

    return sessionId
end

function SessionManager:BindUid(sessionId, uid)
    local session = self.sid2Session[sessionId]
    if not session then
        Logger.Error("SessionManager:BindUid session not found %s", sessionId)
        return false
    end

    session:SetUid(uid)
    session:ChangeState(CONN_STATE.GAMING)

    Logger.Info("SessionManager:BindUid %s", session:ToLogString())
    return true
end

function SessionManager:HandleDisconnect(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        return
    end

    local sessionId = session.sessionId

    if sessionId and session.state == CONN_STATE.GAMING then
        -- 游戏中断线，进入重连等待
        session:ChangeState(CONN_STATE.WAITING_RECONNECT, reason)
        session.disconnectTime = os.time()

        self.waitingReconnect[sessionId] = {
            session = session,
            timeout = os.time() + DEFINE.CONNECTION_RECONNECT_WINDOW,
        }

        -- 清理fd映射，保留其他映射
        self.fd2Session[fd] = nil

        Logger.Info("SessionManager:HandleDisconnect %s waiting reconnect",
            session:ToLogString())
    else
        -- 未认证或非游戏状态，直接清理
        self:Close(fd, reason)
    end
end

function SessionManager:HandleReconnect(newFd, sessionId, account)
    local reconnectInfo = self.waitingReconnect[sessionId]
    if not reconnectInfo then
        return nil, "not in reconnect window"
    end

    local session = reconnectInfo.session

    -- 验证
    if os.time() > reconnectInfo.timeout then
        return nil, "reconnect timeout"
    end

    if session.account ~= account then
        return nil, "account mismatch"
    end

    -- 更新fd
    local oldFd = session.fd
    self.fd2Session[oldFd] = nil
    session:UpdateFd(newFd)
    self.fd2Session[newFd] = session

    -- 从等待队列移除
    self.waitingReconnect[sessionId] = nil

    -- 恢复状态
    session:ChangeState(CONN_STATE.GAMING, "reconnect success")

    Logger.Info("SessionManager:HandleReconnect success %s", session:ToLogString())

    return session
end

function SessionManager:Close(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        return
    end

    Logger.Info("SessionManager:Close %s reason=%s", session:ToLogString(), reason)

    session.closeReason = reason
    session:ChangeState(CONN_STATE.CLOSED, reason)

    -- 清理映射
    self.fd2Session[fd] = nil

    if session.sessionId then
        self.sid2Session[session.sessionId] = nil
        self.waitingReconnect[session.sessionId] = nil

        if session.account then
            -- 注意：account2Sid可能已被新session覆盖，需要检查
            if self.account2Sid[session.account] == session.sessionId then
                self.account2Sid[session.account] = nil
            end
        end
    end

    self.totalClosed = self.totalClosed + 1
end

function SessionManager:KickAgent(account, reason)
    -- RPC调用AgentMgr踢人
    local ok, err = ClusterHelper.CallGameAgentMgr("KickPlayer", account, reason)
    if not ok then
        Logger.Error("SessionManager:KickAgent failed account=%s err=%s", account, err)
    end
end

function SessionManager:Cleanup()
    local now = os.time()
    local expired = {}

    -- 清理超时重连
    for _, info in pairs(self.waitingReconnect) do
        if now > info.timeout then
            table.insert(expired, { fd = info.session.fd, reason = "reconnect timeout" })
        end
    end

    -- 清理空闲连接
    for fd, session in pairs(self.fd2Session) do
        if session:GetIdleTime() > DEFINE.HEARTBEAT_TIMEOUT then
            table.insert(expired, { fd = fd, reason = "heartbeat timeout" })
        end

        local rule = STATE_TRANSITIONS[session.state]
        if rule and rule.timeout then
            if session:GetIdleTime() > rule.timeout then
                table.insert(expired, { fd = fd, reason = "state timeout" })
            end
        end
    end

    for _, item in ipairs(expired) do
        self:Close(item.fd, item.reason)
    end

    if #expired > 0 then
        Logger.Info("SessionManager:Cleanup closed %d sessions", #expired)
    end
end

function SessionManager:GetStats()
    local stats = {
        totalCreated = self.totalCreated,
        totalClosed = self.totalClosed,
        active = 0,
        byState = {},
        waitingReconnect = 0,
    }

    for _, session in pairs(self.fd2Session) do
        if session:IsAlive() then
            stats.active = stats.active + 1
            stats.byState[session.state] = (stats.byState[session.state] or 0) + 1
        end
    end

    for _ in pairs(self.waitingReconnect) do
        stats.waitingReconnect = stats.waitingReconnect + 1
    end

    return stats
end

-- SessionManager 中的断开处理
function SessionManager:Disconnect(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        Logger.Debug("SessionManager:Disconnect no session fd=%s", fd)
        return
    end
    local account = session.account
    local sessionId = session.sessionId
    local oldState = session.state
    Logger.Info("SessionManager:Disconnect %s reason=%s", session:ToLogString(), reason)
    -- 记录断开信息
    session.disconnectTime = os.time()
    session.disconnectReason = reason
    -- 根据状态处理
    if sessionId and (oldState == CONN_STATE.GAMING or oldState == CONN_STATE.AUTHED) then
        -- 游戏中断线，进入重连等待
        session:ChangeState(CONN_STATE.WAITING_RECONNECT, reason)

        self.waitingReconnect[sessionId] = {
            session = session,
            timeout = os.time() + DEFINE.CONNECTION_RECONNECT_WINDOW,
        }
        -- 通知AgentMgr玩家断线（等待重连，不立即下线）
        if account then
            self:NotifyAgentDisconnect(account, sessionId, reason)
        end
        -- 清理fd映射，但保留其他映射
        self.fd2Session[fd] = nil
    else
        -- 其他状态（未认证或已关闭），直接清理
        if account then
            -- 通知AgentMgr立即下线
            self:NotifyAgentLogout(account, reason)
        end
        -- 清理所有映射
        self:Close(fd, reason)
    end
end

function SessionManager:ProcessLogout(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        return
    end

    -- 清理fd映射
    self.fd2Session[fd] = nil

    local account = session:GetAccount()
    local sessionId = session:GetSessionId()
    -- 通知AgentMgr
    if account then
        self:NotifyAgentLogout(account, sessionId, reason)
    end
    if sessionId then
        self.sid2Session[sessionId] = nil
        if account and self.account2Sid[account] == sessionId then
            self.account2Sid[account] = nil
        end
    end
    self.totalClosed = self.totalClosed + 1
end

function SessionManager:ProcessDisconnect(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        return
    end

    local now = os.time()
    session:SetDisconnectTime(now)
    session:ChangeState(CONN_STATE.WAITING_RECONNECT, reason)

    self.waitingReconnect[session.sessionId] = {
        session = session,
        timeout = os.time() + DEFINE.CONNECTION_RECONNECT_WINDOW,
        dissconnectTime = now,
        reason = reason,
    }
    self.fd2Session[fd] = nil
end

-- 通知AgentMgr断开 玩家下线
function SessionManager:NotifyAgentLogout(account, sessionId, reason)
    Logger.Info("SessionManager:NotifyAgentLogout Gate 通知 agent 断开连接 account=%s sessionId=%s reason=%s", account,
        sessionId, reason)
    local ret, err = ClusterHelper.CallGameAgentMgr("OnPlayerLogout", account, sessionId, reason)
    if not ret then
        Logger.Error("SessionManager:NotifyAgentLogout Gate 通知 agent 断开连接失败 account=%s sessionId=%s reason=%s err=%s",
            account, sessionId, reason, err)
    end
end

-- 清理重连超时
function SessionManager:CleanupWaitingReconnect()
    local now = os.time()
    local timeoutSessions = {}

    for sessionId, info in pairs(self.waitingReconnect) do
        if now > info.timeout then
            table.insert(timeoutSessions, {
                sessionId = sessionId,
                session = info.session,
                disconnectTime = info.disconnectTime,
            })
        end
    end

    for _, item in ipairs(timeoutSessions) do
        local session = item.session
        local offlineDuration = now - item.disconnectTime

        Logger.Info("SessionManager:CleanupWaitingReconnect 清理超时session sessionId=%s account=%s offline=%ds",
            item.sessionId, session.account or "nil", offlineDuration)

        -- 通知AgentMgr重连超时下线
        if session.account then
            self:NotifyAgentLogout(session.account, item.sessionId, DEFINE.LOGOUT_REASON.RECONNECT_TIMEOUT)
        end

        -- 清理session
        if session.account and self.account2Sid[session.account] == item.sessionId then
            self.account2Sid[session.account] = nil
        end
        self.sid2Session[item.sessionId] = nil
        self.waitingReconnect[item.sessionId] = nil
        self.totalClosed = self.totalClosed + 1
    end
end

return SessionManager
