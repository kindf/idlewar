local Logger = require("public.logger")
local STATE_TRANSITIONS = require("module.gate.session_state_machine")
local DEFINE = require("public.define")
local CONN_STATE = DEFINE.CONNECTION_STATUS
-- Session类
local Session = {}
Session.__index = Session

function Session.New(fd, ip)
    local self = setmetatable({}, Session)
    self.fd = fd
    self.ip = ip
    self.createTime = os.time()
    self.lastActiveTime = os.time()
    self.state = CONN_STATE.INIT
    self.sessionId = nil
    self.account = nil
    self.uid = nil
    self.loginToken = nil
    self.closeReason = nil
    self.disconnectTime = nil
    self.reconnectCount = 0
    self.clientInfo = {}
    return self
end

function Session:GetId()
    return string.format("%d_%s", self.fd, self.ip)
end

function Session:GetFd()
    return self.fd
end

function Session:GetSessionId()
    return self.sessionId
end

function Session:GetAccount()
    return self.account
end

function Session:GetUid()
    return self.uid
end

function Session:GetState()
    return self.state
end

function Session:IsAlive()
    return self.state ~= CONN_STATE.CLOSED
end

function Session:UpdateActiveTime()
    self.lastActiveTime = os.time()
end

function Session:GetIdleTime()
    return os.time() - self.lastActiveTime
end

function Session:GenerateSessionId(seq)
    self.sessionId = string.format("SID_%d_%d_%d",
        os.time(), math.random(10000, 99999), seq)
    return self.sessionId
end

function Session:UpdateFd(newFd)
    Logger.Info("Session[%s] updating fd: %s -> %s",
        self.sessionId or "temp", self.fd, newFd)
    local oldFd = self.fd
    self.fd = newFd
    self:UpdateActiveTime()
    self.reconnectCount = self.reconnectCount + 1
    return oldFd
end

function Session:ChangeState(newState, reason)
    local currentRule = STATE_TRANSITIONS[self.state]
    if not currentRule then
        Logger.Error("Session[%s] invalid state:%s", self:GetId(), self.state)
        return false
    end

    local allowed = currentRule.next[newState]
    if not allowed then
        Logger.Warn("Session[%s] invalid transition: %s -> %s",
            self:GetId(), self.state, newState)
        return false
    end

    local oldState = self.state
    self.state = newState

    local newRule = STATE_TRANSITIONS[newState]
    if newRule and newRule.onEnter then
        newRule.onEnter(self, reason)
    end

    Logger.Debug("Session[%s] state: %s -> %s",
        self:GetId(), oldState, newState)

    return true
end

function Session:SetAccount(account)
    self.account = account
end

function Session:SetUid(uid)
    self.uid = uid
end

function Session:SetLoginToken(token)
    self.loginToken = token
end

function Session:ToLogString()
    return string.format("fd=%d sid=%s acc=%s uid=%s state=%s idle=%d",
        self.fd, self.sessionId or "nil", self.account or "nil",
        self.uid or "nil", self.state, self:GetIdleTime())
end

return Session
