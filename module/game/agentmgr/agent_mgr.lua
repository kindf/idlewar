local skynet = require "skynet"
local cluster = require "skynet.cluster"
local RetCode = require "proto.retcode"
local Logger = require "public.logger"
local ServiceHelper = require "public.service_helper"
local ProtocolHelper = require "public.protocol_helper"
local CMD = ServiceHelper.CMD

local AgentMgr = {}
-- 玩家数据管理
local acc2Agent = {}          -- account->agent地址
local uid2Agent = {}          -- uid->agent地址
local agent2Info = {}         -- agent地址->玩家信息

local ONLINE_AGENT_STATE = 1  -- 在线
local OFFLINE_AGENT_STATE = 2 -- 离线

function AgentMgr.Init()
    Logger.Info("AgentMgr 初始化")
end

-- 创建玩家信息结构
local function CreateagentInfo(account, uid, agentAddr, state)
    return {
        account = account,
        uid = uid,
        agentAddr = agentAddr,
        state = state or ONLINE_AGENT_STATE,
        loginTime = os.time(),
        lastActiveTime = os.time(),
        ip = nil,
        fd = nil
    }
end

-- 登录游戏
function AgentMgr.LoginGame(account, loginToken)
    Logger.Debug("AgentMgr.LoginGame account:%s, token:%s", account, loginToken)

    -- 验证登录token
    local loginSucc, err = pcall(cluster.call, "loginnode", ".login", "CheckAccountLoginSucc", account, loginToken)
    if not loginSucc then
        Logger.Warning("登录验证失败 account:%s, err:%s", account, err)
        return RetCode.ACCOUNT_NOT_LOGIN
    end

    -- 检查是否已有agent
    local agentInfo = acc2Agent[account]
    local uid
    local agentAddr

    if not agentInfo then
        -- 创建新的agent
        Logger.Debug("创建新的agent account:%s", account)
        agentAddr = skynet.newservice("agent")

        -- 启动agent
        local ok, result = pcall(skynet.call, agentAddr, "lua", "Start", account)
        if not ok or not result then
            Logger.Error("启动agent失败 account:%s, err:%s", account, result)
            skynet.kill(agentAddr)
            return RetCode.CREATE_AGENT_ERROR
        end

        uid = result
        if not uid then
            Logger.Error("获取UID失败 account:%s", account)
            skynet.kill(agentAddr)
            return RetCode.CREATE_AGENT_ERROR
        end

        -- 记录玩家信息
        agentInfo = CreateagentInfo(account, uid, agentAddr, ONLINE_AGENT_STATE)
        acc2Agent[account] = agentInfo
        uid2Agent[uid] = agentInfo
        agent2Info[agentAddr] = agentInfo

        return Logger.Info("新玩家登录成功 account:%s, uid:%d, agent:%s", account, uid, tostring(agentAddr))
    end
    -- 已有agent，重新启动（重连）
    Logger.Debug("玩家重连 account:%s", account)

    if agentInfo.state == ONLINE_AGENT_STATE then
        -- 如果玩家已经在线，可能是多设备登录，踢掉旧连接
        Logger.Warning("玩家已在其他地方登录，踢掉旧连接 account:%s", account)
        if agentInfo.fd then
            -- 通知gate关闭连接
            pcall(cluster.send, "gatenode", ".gatewatchdog", "kick_fd", agentInfo.fd, "顶号")
        end
    end

    -- 重新启动agent
    local ok, result = pcall(skynet.call, agentInfo.agentAddr, "lua", "Restart", account)
    if not ok then
        Logger.Error("重启agent失败 account:%s, err:%s", account, result)
        return RetCode.RESTART_AGENT_ERROR
    end

    uid = agentInfo.uid
    agentInfo.state = ONLINE_AGENT_STATE
    agentInfo.loginTime = os.time()
    agentInfo.lastActiveTime = os.time()

    Logger.Info("玩家重连成功 account:%s, uid:%d", account, uid)

    return RetCode.SUCCESS
end

-- 绑定连接信息
function AgentMgr.BindConnection(account, uid, fd, ip)
    local agentInfo = acc2Agent[account]
    if not agentInfo then
        Logger.Error("绑定连接失败，玩家不存在 account:%s", account)
        return false
    end

    if agentInfo.uid ~= uid then
        Logger.Error("绑定连接失败，UID不匹配 account:%s, uid:%d, playerUid:%d",
            account, uid, agentInfo.uid)
        return false
    end

    agentInfo.fd = fd
    agentInfo.ip = ip
    agentInfo.lastActiveTime = os.time()

    -- 通知agent绑定连接
    if agentInfo.agentAddr then
        skynet.send(agentInfo.agentAddr, "lua", "SetConnectionInfo", {
            fd = fd,
            ip = ip,
            account = account,
            uid = uid
        })
    end

    Logger.Debug("绑定连接成功 account:%s, uid:%d, fd:%d", account, uid, fd)
    return true
end

-- 玩家登出
function AgentMgr.Logout(account, uid, reason)
    Logger.Debug("玩家登出 account:%s, uid:%d, reason:%s", account, uid, reason or "未知")

    local agentInfo
    if account then
        agentInfo = acc2Agent[account]
    elseif uid then
        agentInfo = uid2Agent[uid]
    end

    if not agentInfo then
        Logger.Warning("登出失败，玩家不存在 account:%s, uid:%d", account, uid)
        return RetCode.FAILED
    end

    -- 设置状态为离线
    agentInfo.state = OFFLINE_AGENT_STATE
    agentInfo.logoutTime = os.time()
    agentInfo.logoutReason = reason
    agentInfo.fd = nil
    agentInfo.ip = nil

    -- 清理数据结构（延迟清理，避免频繁登录登出）
    skynet.timeout(500, function()
        if agentInfo.state == OFFLINE_AGENT_STATE then
            acc2Agent[agentInfo.account] = nil
            uid2Agent[agentInfo.uid] = nil
            agent2Info[agentInfo.agentAddr] = nil

            -- 销毁agent服务
            skynet.kill(agentInfo.agentAddr)

            Logger.Info("清理离线玩家 account:%s, uid:%d", agentInfo.account, agentInfo.uid)
        end
    end)

    return RetCode.SUCCESS
end

-- 强制踢出玩家
function AgentMgr.KickPlayer(account, reason)
    local agentInfo = acc2Agent[account]
    if not agentInfo or agentInfo.state ~= ONLINE_AGENT_STATE then
        return RetCode.PLAYER_NOT_ONLINE
    end

    Logger.Warning("强制踢出玩家 account:%s, reason:%s", account, reason or "未知")

    -- 关闭连接
    if agentInfo.fd then
        pcall(cluster.send, "gatenode", ".gatewatchdog", "kick_fd", agentInfo.fd, reason or "被管理员踢出")
    end

    -- 执行登出
    AgentMgr.Logout(account, nil, reason or "被管理员踢出")

    return RetCode.SUCCESS
end

-- 获取在线玩家列表
function AgentMgr.GetOnlinePlayers()
    local onlinePlayers = {}
    for account, agentInfo in pairs(acc2Agent) do
        if agentInfo.state == ONLINE_AGENT_STATE then
            table.insert(onlinePlayers, {
                account = account,
                uid = agentInfo.uid,
                loginTime = agentInfo.loginTime,
                lastActiveTime = agentInfo.lastActiveTime,
                ip = agentInfo.ip,
                agentAddr = tostring(agentInfo.agentAddr)
            })
        end
    end
    return onlinePlayers
end

-- 根据账号获取agent地址
function AgentMgr.GetAgentByAccount(account)
    local agentInfo = acc2Agent[account]
    return agentInfo and agentInfo.agentAddr
end

-- 根据UID获取agent地址
function AgentMgr.GetAgentByUid(uid)
    local agentInfo = uid2Agent[uid]
    return agentInfo and agentInfo.agentAddr
end

-- 获取玩家信息
function AgentMgr.GetagentInfo(account)
    return acc2Agent[account]
end

-- 发送消息给玩家
function AgentMgr.SendMessageToPlayer(account, protoName, msg)
    local agentAddr = AgentMgr.GetAgentByAccount(account)
    if not agentAddr then
        return RetCode.PLAYER_NOT_ONLINE
    end

    local ok, err = pcall(skynet.send, agentAddr, "lua", "SendClientMessage", protoName, msg)
    if not ok then
        Logger.Error("发送消息失败 account:%s, proto:%s, err:%s", account, protoName, err)
        return RetCode.FAILED
    end

    return RetCode.SUCCESS
end

-- 广播消息给所有在线玩家
function AgentMgr.BroadcastMessage(protoName, msg)
    local onlinePlayers = AgentMgr.GetOnlinePlayers()
    for _, player in ipairs(onlinePlayers) do
        AgentMgr.SendMessageToPlayer(player.account, protoName, msg)
    end
end

-- 清理长时间离线的玩家
function AgentMgr.CleanupOfflinePlayers(maxOfflineTime)
    maxOfflineTime = maxOfflineTime or 3600 -- 默认1小时

    local currentTime = os.time()
    local cleanedCount = 0

    for agentAddr, agentInfo in pairs(agent2Info) do
        if agentInfo.state == OFFLINE_AGENT_STATE and
            agentInfo.logoutTime and
            (currentTime - agentInfo.logoutTime) > maxOfflineTime then
            -- 清理数据结构
            acc2Agent[agentInfo.account] = nil
            uid2Agent[agentInfo.uid] = nil
            agent2Info[agentAddr] = nil

            -- 销毁agent服务
            skynet.kill(agentAddr)

            cleanedCount = cleanedCount + 1
            Logger.Debug("清理离线玩家 account:%s, uid:%d, 离线时间:%d秒",
                agentInfo.account, agentInfo.uid, currentTime - agentInfo.logoutTime)
        end
    end

    if cleanedCount > 0 then
        Logger.Info("清理完成，共清理 %d 个离线玩家", cleanedCount)
    end

    return cleanedCount
end

-- 更新玩家活跃时间
function AgentMgr.UpdateActiveTime(account)
    local agentInfo = acc2Agent[account]
    if agentInfo and agentInfo.state == ONLINE_AGENT_STATE then
        agentInfo.lastActiveTime = os.time()
        return true
    end
    return false
end

-- 心跳检查
function AgentMgr.HeartbeatCheck()
    local currentTime = os.time()
    local timeoutPlayers = {}

    -- 检查长时间无心跳的玩家（5分钟）
    for account, agentInfo in pairs(acc2Agent) do
        if agentInfo.state == ONLINE_AGENT_STATE and
            (currentTime - agentInfo.lastActiveTime) > 300 then
            table.insert(timeoutPlayers, account)
        end
    end

    -- 踢出超时玩家
    for _, account in ipairs(timeoutPlayers) do
        Logger.Warning("玩家心跳超时，强制登出 account:%s", account)
        AgentMgr.KickPlayer(account, "心跳超时")
    end

    -- 清理离线玩家
    AgentMgr.CleanupOfflinePlayers(1800) -- 30分钟

    return #timeoutPlayers
end

return AgentMgr
