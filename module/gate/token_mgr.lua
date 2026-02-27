local Logger = require "public.logger"
local DEFINE = require "public.define"

-- TokenInfo类
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

local TokenManager = {
    token2Info = {},
}

function TokenManager:Add(token, account)
    local info = TokenInfo.New(account, token)
    self.token2Info[token] = info
    return info
end

function TokenManager:Verify(token, account)
    local info = self.token2Info[token]
    if not info then
        return false
    end

    if info.account ~= account then
        return false
    end

    if info:IsExpired() then
        self.token2Info[token] = nil
        return false
    end

    info:Refresh()
    return true
end

function TokenManager:Remove(token)
    self.token2Info[token] = nil
end

function TokenManager:Cleanup()
    local now = os.time()
    local expired = {}

    for token, info in pairs(self.token2Info) do
        if info:IsExpired() then
            table.insert(expired, token)
        end
    end

    for _, token in ipairs(expired) do
        self.token2Info[token] = nil
    end

    if #expired > 0 then
        Logger.Debug("TokenManager:Cleanup removed %d expired tokens", #expired)
    end
end

return TokenManager
