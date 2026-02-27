local skynet = require "skynet"
local RetCode = require "proto.retcode"
local Logger = require "public.logger"
local DEFINE = require "public.define"
local ClusterHelper = require "public.cluster_helper"
local ProtocolHelper = require "public.protocol_helper"
local AgentInfo = require "module.game.agentmgr.agent_info"
local Timer = require "public.timer"
local AGENT_STATE = DEFINE.AGENT_STATE

local AgentMgr = {
    acc2Agent = {},    -- account -> AgentInfo
    uid2Agent = {},    -- uid -> AgentInfo
    agent2Info = {},   -- agentAddr -> AgentInfo
    cleanupQueue = {}, -- agentAddr -> {info, scheduleTime, reason}
    totalCreated = 0,
    totalDestroyed = 0,
    totalReconnects = 0,
    timer = Timer.New(),
}

function AgentMgr:Add(account, uid, agentAddr)
    -- 检查是否已存在
    local existing = self.acc2Agent[account]
    if existing then
        Logger.Warn("AgentMgr:Add account=%s already exists, removing", account)
        self:ImmediateRemove(existing.agentAddr, "duplicate")
    end

    local info = AgentInfo.New(account, uid, agentAddr)
    self.acc2Agent[account] = info
    self.uid2Agent[uid] = info
    self.agent2Info[agentAddr] = info
    self.totalCreated = self.totalCreated + 1
    Logger.Info("AgentMgr:Add %s", info:ToLogString())
    return info
end

function AgentMgr:GetByAccount(account)
    return self.acc2Agent[account]
end

function AgentMgr:GetByUid(uid)
    return self.uid2Agent[uid]
end

function AgentMgr:GetByAddr(agentAddr)
    return self.agent2Info[agentAddr]
end

function AgentMgr:ImmediateRemove(agentAddr, reason)
    local info = self.agent2Info[agentAddr]
    if not info then
        return false
    end

    Logger.Info("AgentMgr:ImmediateRemove %s reason=%s", info:ToLogString(), reason)

    self.acc2Agent[info.account] = nil
    self.uid2Agent[info.uid] = nil
    self.agent2Info[agentAddr] = nil
    self.cleanupQueue[agentAddr] = nil

    skynet.kill(agentAddr)

    self.totalDestroyed = self.totalDestroyed + 1
    return true
end

function AgentMgr:ScheduleRemove(agentAddr, reason)
    local info = self.agent2Info[agentAddr]
    if not info then
        return false
    end

    info:SetOffline(reason)

    self.cleanupQueue[agentAddr] = {
        info = info,
        scheduleTime = os.time(),
        reason = reason,
    }

    -- 延迟清理
    skynet.timeout(DEFINE.AGENT_CLEANUP_DELAY, function()
        if self.cleanupQueue[agentAddr] then
            self:ImmediateRemove(agentAddr, "cleanup: " .. reason)
        end
    end)

    Logger.Debug("AgentMgr:ScheduleRemove %s", info:ToLogString())
    return true
end

function AgentMgr:CancelCleanup(agentAddr)
    if self.cleanupQueue[agentAddr] then
        self.cleanupQueue[agentAddr] = nil
        Logger.Debug("AgentMgr:CancelCleanup %s", agentAddr)
        return true
    end
    return false
end

function AgentMgr:HandleReconnect(account, uid, fd, ip)
    local info = self.acc2Agent[account]
    if not info then
        return false, "玩家agent不存在"
    end

    -- 检查重连次数
    if info.reconnectCount >= DEFINE.MAX_RECONNECT_ATTEMPTS then
        return false, "超过最大重连次数"
    end
    -- 取消清理
    self:CancelCleanup(info.agentAddr)
    -- 开始重连
    info:StartReconnect()
    -- 重启agent
    local ok, err = skynet.call(info.agentAddr, "lua", "Restart", account)
    if not ok then
        Logger.Error("AgentMgr:HandleReconnect restart failed account=%s err=%s",
            account, err)
        return false, "restart failed"
    end
    -- 绑定连接
    info:BindConnection(fd, ip)
    self.totalReconnects = self.totalReconnects + 1
    Logger.Info("AgentMgr:HandleReconnect success %s", info:ToLogString())
    return true
end

function AgentMgr:KickPlayer(account, reason)
    local info = self.acc2Agent[account]
    if not info or not info:IsOnline() then
        return RetCode.PLAYER_NOT_ONLINE
    end
    Logger.Warning("AgentMgr:Kick %s reason=%s fd:%s", info:ToLogString(), reason, info.fd)
    -- 踢掉gate连接
    if info.fd then
        ClusterHelper.CallGateNode(".gatewatchdog", "KickPlayer", info.fd, reason or "kicked")
    end
    -- 加入清理队列
    self:ScheduleRemove(info.agentAddr, reason or "kicked")
    return RetCode.SUCCESS
end

function AgentMgr:EnterGame(account, sessionId)
    local info = self.acc2Agent[account]
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", {account = account}, {uid = 1})
    if not ret then
        Logger.Error("AgentMgr.EnterGame 加载数据失败 account=%s", account)
        return RetCode.SYSTEM_ERROR
    end
    if not data or not data.uid then
        Logger.Error("AgentMgr.EnterGame 账号尚未创建 account=%s", account)
        return RetCode.ACCOUNT_NOT_EXIST
    end
    local uid = data.uid
    local ret1, succ = ClusterHelper.CallGateNode(".gatewatchdog", "EnterGame", sessionId, uid)
    if not ret1 then
        Logger.Error("AgentMgr.EnterGame EnterGame失败 account=%s", account)
        return RetCode.SYSTEM_ERROR
    end
    if not succ then
        Logger.Error("AgentMgr.EnterGame EnterGame失败 account=%s", account)
        return RetCode.SYSTEM_ERROR
    end
    -- 新玩家
    if not info then
        Logger.Debug("AgentMgr:EnterGame creating new agent account=%s", account)

        local agentAddr = skynet.newservice("agent")
        local ok, err = skynet.call(agentAddr, "lua", "Start", account, uid)
        if not ok then
            Logger.Error("AgentMgr:EnterGame start agent failed err=%s", err)
            skynet.kill(agentAddr)
            return RetCode.CREATE_AGENT_ERROR
        end

        self:Add(account, uid, agentAddr)
        Logger.Info("AgentMgr:EnterGame new player account=%s uid=%d", account, uid)

        return RetCode.SUCCESS
    end

    -- 重连玩家
    Logger.Debug("AgentMgr:EnterGame player reconnect account=%s", account)
    -- 取消清理
    self:CancelCleanup(info.agentAddr)
    -- 重启agent
    local ok, err = skynet.call(info.agentAddr, "lua", "Restart", account)
    if not ok then
        Logger.Error("AgentMgr:EnterGame restart failed err=%s", err)
        return RetCode.RESTART_AGENT_ERROR
    end
    info.state = AGENT_STATE.GAMING
    info:UpdateActiveTime()
    Logger.Info("AgentMgr:EnterGame reconnect success account=%s uid=%d", account, info.uid)
    return RetCode.SUCCESS
end

function AgentMgr:Logout(account, reason)
    local info = self.acc2Agent[account]
    if not info then
        return RetCode.FAILED
    end

    self:ScheduleRemove(info.agentAddr, reason or "logout")
    return RetCode.SUCCESS
end

function AgentMgr:GetOnlineCount()
    local count = 0
    for _, info in pairs(self.acc2Agent) do
        if info:IsOnline() then
            count = count + 1
        end
    end
    return count
end

function AgentMgr:GetOnlineList()
    local list = {}
    for account, info in pairs(self.acc2Agent) do
        if info:IsOnline() then
            table.insert(list, {
                account = account,
                uid = info.uid,
                state = info.state,
                loginTime = info.loginTime,
                lastActive = info.lastActiveTime,
                idleTime = info:GetIdleTime(),
                ip = info.ip,
                fd = info.fd,
                reconnectCount = info.reconnectCount,
            })
        end
    end
    return list
end

function AgentMgr:GetStats()
    local stats = {
        totalCreated = self.totalCreated,
        totalDestroyed = self.totalDestroyed,
        totalReconnects = self.totalReconnects,
        online = 0,
        reconnecting = 0,
        offline = 0,
        cleanup = 0,
    }

    for _, info in pairs(self.agent2Info) do
        if info.state == AGENT_STATE.GAMING then
            stats.online = stats.online + 1
        elseif info.state == AGENT_STATE.RECONNECTING then
            stats.reconnecting = stats.reconnecting + 1
        elseif info.state == AGENT_STATE.OFFLINE then
            stats.offline = stats.offline + 1
        elseif info.state == AGENT_STATE.CLEANUP then
            stats.cleanup = stats.cleanup + 1
        end
    end

    return stats
end

function AgentMgr:Cleanup()
    local timeoutReconnects = {}
    -- 清理超时重连
    for _, info in pairs(self.acc2Agent) do
        if info.state == AGENT_STATE.RECONNECTING and info:ReconnectTimeout() then
            table.insert(timeoutReconnects, info.agentAddr)
        end
    end
    for _, addr in ipairs(timeoutReconnects) do
        Logger.Warn("AgentMgr:Cleanup reconnect timeout %s",
            self.agent2Info[addr]:ToLogString())
        self:ScheduleRemove(addr, "reconnect timeout")
    end
    -- 输出统计
    local stats = self:GetStats()
    Logger.Info("AgentMgr stats - online:%d reconnecting:%d cleanup:%d", stats.online, stats.reconnecting, stats.cleanup)
end

function AgentMgr:Init()
    Logger.Info("AgentMgr initialized")
    -- 启动清理定时器
    self.timer:Interval(50, function() self:Cleanup() end, false)
end

function AgentMgr:GetAgentByAccount(account)
    local info = self:GetByAccount(account)
    return info and info.agentAddr
end

function AgentMgr:GetAgentByUid(uid)
    local info = self:GetByUid(uid)
    return info and info.agentAddr
end

function AgentMgr:SendMessageToPlayer(account, proto, msg)
    local info = self:GetByAccount(account)
    if not info or not info:IsOnline() then
        return RetCode.PLAYER_NOT_ONLINE
    end
    -- 获取业务锁
    if not info:AcquireLock("send", 5) then
        return RetCode.PLAYER_BUSY
    end
    info:ReleaseLock("send")
    local ok, err = pcall(skynet.send, info.agentAddr, "lua", "SendMessage", proto, msg)
    if not ok then
        Logger.Error("AgentMgr.SendMessage failed account=%s err=%s", account, err)
        return RetCode.FAILED
    end
    info:UpdateActiveTime()
    return RetCode.SUCCESS
end

-- 调试接口
function AgentMgr:DebugGetCleanupQueue()
    local list = {}
    for _, info in pairs(self.cleanupQueue) do
        table.insert(list, string.format("%s reason=%s",
            info.info:ToLogString(), info.reason))
    end
    return list
end

function AgentMgr:CreateRole(sessionId, account, name)
    local ret, succ = ClusterHelper.CallGateNode(".gatewatchdog", "CheckCreateRoleSession", account, sessionId)
    if not ret then
        Logger.Warning("AgentMgr.CreateRole 非法token account=%s", account)
        return RetCode.INVALID_TOKEN
    end

    local ret1, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", {account = account}, {uid = 1})
    if not ret1 then
        Logger.Error("AgentMgr.CreateRole 加载数据失败 account=%s", account)
        return RetCode.SYSTEM_ERROR
    end

    if data then
        Logger.Error("AgentMgr.CreateRole 账号已存在 account=%s", account)
        return RetCode.ACCOUNT_CREATE_REPEATED
    end

    local ret2, uid = skynet.call(".guid", "lua", "GetUid")
    if not ret2 then
        Logger.Error("AgentMgr.CreateRole 获取uid失败")
        return RetCode.SYSTEM_ERROR
    end

    local accountData = {
        account = account,
        uid = uid,
        bornTime = os.time(),
        name = name,
    }

    local ret3 = skynet.call(".mongodb", "lua", "InsertOne", "userdata", accountData)
    if not ret3 then
        Logger.Error("AgentMgr.CreateRole 写入数据失败 account=%s", account)
        return RetCode.SYSTEM_ERROR
    end
    return RetCode.SUCCESS
end

------------------------------------------------- 客户端请求 --------------------------------------------------------------------------

-- 查询玩家uid
local function C2SQueryUid(req, resp)
    local account = req.account
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", {account = account}, {uid = 1})
    if not ret then
        Logger.Error("AgentMgr.C2SQueryUid 加载数据失败 account=%s", account)
        resp.retCode = RetCode.SYSTEM_ERROR
        return
    end

    resp.retCode = RetCode.SUCCESS
    resp.uid = data and data.uid
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_query_uid", "player_base.s2c_query_uid", C2SQueryUid)

-- 创角
local function C2SCreateRole(req, resp)
    local sessionId = req.sessionId
    local account = req.account
    local name = req.name
    resp.retCode = AgentMgr:CreateRole(sessionId, account, name)
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_create_role", "player_base.s2c_create_role", C2SCreateRole)

-- 进入游戏
local function C2SEnterGame(req, resp)
    local account = req.account
    local sessionId = req.sessionId
    resp.retCode = AgentMgr:EnterGame(account, sessionId)
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_enter_game", "player_base.s2c_enter_game", C2SEnterGame)

return AgentMgr
