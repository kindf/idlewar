local skynet = require "skynet"
local Logger = require "public.logger"
local DEFINE = require "public.define"
local AGENT_STATE = DEFINE.AGENT_STATE

-- AgentInfo类
local AgentInfo = {}
AgentInfo.__index = AgentInfo

function AgentInfo.New(account, uid, agentAddr)
    local self = setmetatable({}, AgentInfo)
    self.account = account
    self.uid = uid
    self.agentAddr = agentAddr
    self.state = AGENT_STATE.LOADING
    self.createTime = os.time()
    self.loginTime = nil
    self.lastActiveTime = os.time()
    self.logoutTime = nil
    self.logoutReason = nil
    self.ip = nil
    self.fd = nil
    self.clientInfo = {}
    -- 重连相关
    self.reconnectCount = 0
    self.reconnectStartTime = nil
    self.lastReconnectTime = nil
    -- 业务锁
    self.locks = {}
    return self
end

function AgentInfo:UpdateActiveTime()
    self.lastActiveTime = os.time()
end

function AgentInfo:GetIdleTime()
    return os.time() - self.lastActiveTime
end

function AgentInfo:IsOnline()
    return self.state == AGENT_STATE.ONLINE or
        self.state == AGENT_STATE.GAMING
end

function AgentInfo:CanReconnect()
    return self.state == AGENT_STATE.ONLINE or
        self.state == AGENT_STATE.GAMING or
        self.state == AGENT_STATE.RECONNECTING
end

function AgentInfo:StartReconnect()
    self.reconnectCount = self.reconnectCount + 1
    self.reconnectStartTime = os.time()
    self.lastReconnectTime = os.time()
    self.state = AGENT_STATE.RECONNECTING
    self:UpdateActiveTime()
end

function AgentInfo:ReconnectTimeout()
    if self.state ~= AGENT_STATE.RECONNECTING then
        return false
    end
    local elapsed = (os.time() - (self.reconnectStartTime or 0)) * 1000
    return elapsed > DEFINE.AGENT_CONNECT_TIMEOUT
end

function AgentInfo:BindConnection(fd, ip)
    self.fd = fd
    self.ip = ip
    self.loginTime = os.time()
    self.state = AGENT_STATE.GAMING
    self.reconnectCount = 0
    self.reconnectStartTime = nil
    self:UpdateActiveTime()

    -- 通知agent
    if self.agentAddr then
        skynet.send(self.agentAddr, "lua", "SetConnectionInfo", {
            fd = fd,
            ip = ip,
            account = self.account,
            uid = self.uid
        })
    end

    Logger.Info("AgentInfo:BindConnection account=%s uid=%d fd=%d",
        self.account, self.uid, fd)
end

function AgentInfo:SetOffline(reason)
    self.state = AGENT_STATE.OFFLINE
    self.logoutTime = os.time()
    self.logoutReason = reason
    self.fd = nil
    self.ip = nil
    self:UpdateActiveTime()
end

function AgentInfo:AcquireLock(key, timeout)
    if self.locks[key] then
        local lockTime = self.locks[key]
        if os.time() - lockTime > (timeout or 30) then
            Logger.Warn("AgentInfo:AcquireLock timeout account=%s key=%s",
                self.account, key)
            self.locks[key] = nil
        else
            return false
        end
    end
    self.locks[key] = os.time()
    return true
end

function AgentInfo:ReleaseLock(key)
    self.locks[key] = nil
end

function AgentInfo:ToLogString()
    return string.format("acc=%s uid=%d state=%s idle=%d fd=%s reconnect=%d",
        self.account, self.uid, self.state, self:GetIdleTime(),
        self.fd or "nil", self.reconnectCount)
end

return AgentInfo
