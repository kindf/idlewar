local Logger = require("public.logger")
local Session = require("module.gate.session")
local DEFINE = require("public.define")
local STATE_MACHINE = require("module.gate.session_state_machine")

local CONNECTION_STATUS = DEFINE.CONNECTION_STATUS
-- Token 信息类
local TokenInfo = {}
TokenInfo.__index = TokenInfo

function TokenInfo.New(account, token)
    local self = setmetatable({}, TokenInfo)
    self.account = account
    self.token = token
    self.createTime = os.time()
    self.expireTime = os.time() + DEFINE.TOKEN_EXPIRE_TIME
    return self
end

function TokenInfo:IsExpired()
    return os.time() > self.expireTime
end

function TokenInfo:Refresh()
    self.expireTime = os.time() + DEFINE.TOKEN_EXPIRE_TIME
end

-- SessionManager 管理所有 Session
local SessionManager = {
    fd2Session = {},      -- fd -> Session
    account2Session = {}, -- account -> Session
    uid2Session = {},     -- uid -> Session
    token2Info = {},      -- token -> TokenInfo
    totalCreated = 0,
    totalClosed = 0,
}

function SessionManager:Add(fd, ip)
    if self.fd2Session[fd] then
        Logger.Warn("SessionManager:Add session already exists for fd=%s, closing old one", fd)
        self:Close(fd, "重复的连接")
    end

    local session = Session.New(fd, ip)
    self.fd2Session[fd] = session
    self.totalCreated = self.totalCreated + 1

    Logger.Debug("SessionManager:Add %s, total:%d", session:ToLogString(), self:GetActiveCount())

    return session
end

function SessionManager:GetByFd(fd)
    return self.fd2Session[fd]
end

function SessionManager:GetByAccount(account)
    return self.account2Session[account]
end

function SessionManager:GetByUid(uid)
    return self.uid2Session[uid]
end

function SessionManager:GetAll()
    return self.fd2Session
end

function SessionManager:BindAccount(fd, account)
    local session = self.fd2Session[fd]
    if not session then
        Logger.Error("SessionManager:BindAccount session not found fd=%s", fd)
        return false
    end

    -- 如果该账号已有其他session，先处理
    local existing = self.account2Session[account]
    if existing and existing.fd ~= fd then
        Logger.Info("SessionManager:BindAccount account %s already has session fd=%s, kicking",
            account, existing.fd)
        self:Close(existing.fd, "顶号")
    end

    session:SetAccount(account)
    self.account2Session[account] = session

    Logger.Info("SessionManager:BindAccount account=%s fd=%s", account, fd)
    return true
end

function SessionManager:BindUid(account, uid)
    local session = self.account2Session[account]
    if not session then
        Logger.Error("SessionManager:BindUid session not found account=%s", account)
        return false
    end

    -- 如果该UID已有其他session，先处理
    local existing = self.uid2Session[uid]
    if existing and existing.fd ~= session.fd then
        Logger.Info("SessionManager:BindUid uid %s already has session fd=%s, kicking",
            uid, existing.fd)
        self:Close(existing.fd, "顶号")
    end

    session:SetUid(uid)
    self.uid2Session[uid] = session

    Logger.Info("SessionManager:BindUid uid=%s account=%s fd=%s", uid, account, session.fd)
    return true
end

function SessionManager:AddToken(token, account)
    local tokenInfo = TokenInfo.New(account, token)
    self.token2Info[token] = tokenInfo
    return tokenInfo
end

function SessionManager:VerifyToken(token, account)
    local tokenInfo = self.token2Info[token]
    if not tokenInfo then
        Logger.Debug("SessionManager:VerifyToken token not found")
        return false
    end

    if tokenInfo.account ~= account then
        Logger.Warn("SessionManager:VerifyToken account mismatch: %s vs %s",
            tokenInfo.account, account)
        return false
    end

    if tokenInfo:IsExpired() then
        Logger.Debug("SessionManager:VerifyToken token expired")
        self.token2Info[token] = nil
        return false
    end

    -- 验证通过，刷新token
    tokenInfo:Refresh()
    return true
end

function SessionManager:RemoveToken(token)
    self.token2Info[token] = nil
end

function SessionManager:Close(fd, reason)
    local session = self.fd2Session[fd]
    if not session then
        return
    end

    -- 状态转换为CLOSED
    session:ChangeState(CONNECTION_STATUS.CLOSED, reason)

    -- 从所有映射中移除
    self.fd2Session[fd] = nil

    if session:GetAccount() then
        local accSession = self.account2Session[session:GetAccount()]
        if accSession and accSession.fd == fd then
            self.account2Session[session:GetAccount()] = nil
        end
    end

    if session:GetUid() then
        local uidSession = self.uid2Session[session:GetUid()]
        if uidSession and uidSession.fd == fd then
            self.uid2Session[session:GetUid()] = nil
        end
    end

    if session.loginToken then
        self.token2Info[session.loginToken] = nil
    end

    self.totalClosed = self.totalClosed + 1

    Logger.Info("SessionManager:Close %s, active:%d", session:ToLogString(), self:GetActiveCount())
end

function SessionManager:CleanupExpiredSessions()
    local expired = {}

    for fd, session in pairs(self.fd2Session) do
        -- 检查超时
        if session:GetIdleTime() > DEFINE.SESSION_TIMEOUT then
            table.insert(expired, fd)
        end

        -- 检查特定状态超时
        local stateDef = STATE_MACHINE[session:GetStatus()]
        if stateDef and stateDef.timeout then
            if session:GetIdleTime() > stateDef.timeout then
                table.insert(expired, fd)
            end
        end
    end

    for _, fd in ipairs(expired) do
        self:Close(fd, "session timeout")
    end

    if #expired > 0 then
        Logger.Info("SessionManager:CleanupExpiredSessions closed %d expired sessions", #expired)
    end
end

function SessionManager:CleanupExpiredTokens()
    local expired = {}

    for token, tokenInfo in pairs(self.token2Info) do
        if tokenInfo:IsExpired() then
            table.insert(expired, token)
        end
    end

    for _, token in ipairs(expired) do
        self.token2Info[token] = nil
    end

    if #expired > 0 then
        Logger.Debug("SessionManager:CleanupExpiredTokens cleaned %d expired tokens", #expired)
    end
end

function SessionManager:GetActiveCount()
    local count = 0
    for _, session in pairs(self.fd2Session) do
        if session:IsAlive() then
            count = count + 1
        end
    end
    return count
end

function SessionManager:GetStats()
    local stats = {
        totalCreated = self.totalCreated,
        totalClosed = self.totalClosed,
        active = self:GetActiveCount(),
        byStatus = {},
        tokens = 0,
    }

    for _, session in pairs(self.fd2Session) do
        if session:IsAlive() then
            stats.byStatus[session:GetStatus()] = (stats.byStatus[session:GetStatus()] or 0) + 1
        end
    end

    for _ in pairs(self.token2Info) do
        stats.tokens = stats.tokens + 1
    end

    return stats
end

return SessionManager
