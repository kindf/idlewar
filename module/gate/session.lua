local Logger = require("public.logger")
local DEFINE = require "public.define"
local STATE_MACHINE = require("module.gate.session_state_machine")
local CONNECTION_STATUS = DEFINE.CONNECTION_STATUS

local Session = {}
Session.__index = Session

function Session.New(Fd, Ip)
    local self = setmetatable({}, Session)
    self.fd = Fd
    self.ip = string.match(Ip, "([%d.]+):(%d+)") or Ip
    self.createTime = os.time()
    self.lastActiveTime = os.time()
    self.status = CONNECTION_STATUS.CONNECTED
    self.account = nil
    self.uid = nil
    self.sessionId = nil
    self.loginToken = nil
    self.agentNode = nil
    self.agentAddr = nil
    self.closeReason = nil
    self.version = nil
    self.clientInfo = {} -- 客户端信息（设备、系统等）
    self.extData = {}    -- 扩展数据
    self.disconnectTime = nil
    self.disconnectReason = nil
    self.reconnectCount = 0

    Logger.Debug("Session created: temp session for fd=%s", Fd)
    return self
end

function Session:GetId()
    return string.format("%d_%s", self.fd, self.ip)
end

function Session:GetFd()
    return self.fd
end

function Session:GetAccount()
    return self.account
end

function Session:GetUid()
    return self.uid
end

function Session:GetStatus()
    return self.status
end

function Session:GetSessionId()
    return self.sessionId
end

function Session:IsAlive()
    return self.status ~= CONNECTION_STATUS.CLOSED
end

function Session:UpdateActiveTime()
    self.lastActiveTime = os.time()
end

function Session:GetIdleTime()
    return os.time() - self.lastActiveTime
end

function Session:GenerateSessionId(seqCounter)
    -- 格式: SID_时间戳_随机数_自增序列
    self.sessionId = string.format("SID_%d_%d_%d",
        os.time(), math.random(10000, 99999), seqCounter)
    Logger.Info("Session[%s] generated sessionId=%s", self.fd, self.sessionId)
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
    -- 验证状态转换是否允许
    local currentStateDef = STATE_MACHINE[self.status]
    if not currentStateDef then
        Logger.Error("Session[%s] invalid current state:%s", self:GetId(), self.status)
        return false
    end

    -- 检查是否允许转换到新状态
    local allowed = STATE_MACHINE[self.status].allowedNext[newState]
    if not allowed then
        Logger.Warn("Session[%s] invalid state transition: %s -> %s",
            self:GetId(), self.status, newState)
        return false
    end

    -- 执行退出当前状态的钩子
    if currentStateDef.OnExit then
        currentStateDef.OnExit(self)
    end

    -- 更新状态
    local oldState = self.status
    self.status = newState

    -- 执行进入新状态的钩子
    local newStateDef = STATE_MACHINE[newState]
    if newStateDef and newStateDef.OnEnter then
        newStateDef.OnEnter(self, reason)
    end

    Logger.Debug("Session[%s] state changed: %s -> %s",
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

function Session:SetAgent(node, addr)
    self.agentNode = node
    self.agentAddr = addr
end

function Session:SetClientInfo(info)
    self.clientInfo = info
end

function Session:SetExtData(key, value)
    self.extData[key] = value
end

function Session:GetExtData(key)
    return self.extData[key]
end

function Session:ToLogString()
    return string.format("fd=%d account=%s uid=%s sessionId=%s status=%s idle=%ds",
        self.fd, self.account or "nil", self.uid or "nil",
        self.sessionId or "nil", self.status, self:GetIdleTime())
end

return Session

