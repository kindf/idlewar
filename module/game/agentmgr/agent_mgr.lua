local skynet = require "skynet"
local cluster = require "skynet.cluster"
local RetCode = require "proto.retcode"
local Logger = require "public.logger"
local DEFINE = require "public.define"
local ClusterHelper = require "public.cluster_helper"
local ProtocolHelper = require "public.protocol_helper"

local AgentMgr = {}
-- 玩家数据管理
local acc2Agent = {}          -- account->agent地址
local uid2Agent = {}          -- uid->agent地址
local agent2Info = {}         -- agent地址->玩家信息

function AgentMgr.Init()
    Logger.Info("AgentMgr 初始化")
end

-- 创建玩家信息结构
local function CreateAgentInfo(account, uid, agentAddr, state)
    local info =  {
        account = account,
        uid = uid,
        agentAddr = agentAddr,
        state = state or DEFINE.AGENT_STATE.ONLINE_AGENT_STATE,
        loginTime = os.time(),
        lastActiveTime = os.time(),
        ip = nil,
        fd = nil
    }
    agent2Info[agentAddr] = info
    acc2Agent[account] = info
    uid2Agent[uid] = info
    return info
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
    agentInfo.state = DEFINE.AGENT_STATE.OFFLINE_AGENT_STATE
    agentInfo.logoutTime = os.time()
    agentInfo.logoutReason = reason
    agentInfo.fd = nil
    agentInfo.ip = nil

    -- 清理数据结构（延迟清理，避免频繁登录登出）
    skynet.timeout(500, function()
        if agentInfo.state == DEFINE.AGENT_STATE.OFFLINE_AGENT_STATE then
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
    if not agentInfo or agentInfo.state ~= DEFINE.AGENT_STATE.ONLINE_AGENT_STATE then
        return RetCode.PLAYER_NOT_ONLINE
    end

    Logger.Warning("强制踢出玩家 account:%s, reason:%s", account, reason or "未知")

    -- 关闭连接
    if agentInfo.fd then
        pcall(cluster.send, "gatenode", ".gatewatchdog", "KickPlayer", agentInfo.fd, reason or "被管理员踢出")
    end

    -- 执行登出
    AgentMgr.Logout(account, nil, reason or "被管理员踢出")

    return RetCode.SUCCESS
end

-- 获取在线玩家列表
function AgentMgr.GetOnlinePlayers()
    local onlinePlayers = {}
    for account, agentInfo in pairs(acc2Agent) do
        if agentInfo.state == DEFINE.AGENT_STATE.ONLINE_AGENT_STATE then
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
function AgentMgr.GetAgentInfo(account)
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

local function OnEnterGame(account, uid)
    local agentInfo = acc2Agent[account]
    local agentAddr
    if not agentInfo then
        -- 创建新的agent
        Logger.Debug("创建新的agent account:%s", account)
        agentAddr = skynet.newservice("agent")
        local ok, result = skynet.call(agentAddr, "lua", "Start", account, uid)
        if not ok or not result then
            Logger.Error("启动agent失败 account:%s, err:%s", account, result)
            skynet.kill(agentAddr)
            return RetCode.CREATE_AGENT_ERROR
        end
        agentInfo = CreateAgentInfo(account, uid, agentAddr, DEFINE.AGENT_STATE.ONLINE_AGENT_STATE)
        Logger.Info("新玩家登录成功 account:%s, uid:%d, agent:%s", account, uid, tostring(agentAddr))
        return RetCode.SUCCESS
    end

    Logger.Debug("玩家重连 account:%s", account)
    -- 重连
    if agentInfo.state == DEFINE.AGENT_STATE.ONLINE_AGENT_STATE then
        -- 如果玩家已经在线，可能是多设备登录，踢掉旧连接
        Logger.Warning("玩家已在其他地方登录，踢掉旧连接 account:%s", account)
        if agentInfo.fd then
            -- 通知gate关闭连接
            ClusterHelper.CallGateNode(".gatewatchdog", "KickPlayer", agentInfo.fd, "顶号")
        end
    end
    -- 重新启动agent
    local ok, result = pcall(skynet.call, agentInfo.agentAddr, "lua", "Restart", account)
    if not ok or not result then
        Logger.Error("重启agent失败 account:%s, err:%s", account, result)
        skynet.kill(agentAddr)
        return RetCode.RESTART_AGENT_ERROR
    end

    uid = agentInfo.uid
    agentInfo.state = DEFINE.AGENT_STATE.ONLINE_AGENT_STATE
    -- 更新 gate conn 状态
    ClusterHelper.CallGateNode(".gatewatchdog", "SetConnectGaming", account)
    Logger.Info("玩家重连成功 account:%s, uid:%d", account, uid)
    return RetCode.SUCCESS
end

function AgentMgr.EnterGame(account, loginToken)
    local verifyResult = ClusterHelper.CallGateNode(".gatewatchdog", "VerifyToken", account, loginToken)
    if not verifyResult then
        Logger.Error("EnterGame 验证token失败 account:%s", account)
        return RetCode.INVALID_TOKEN
    end

    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account }, {uid = 1})
    if not ret then
        Logger.Error("加载玩家数据失败 account:%s err:%s", account, data)
        return RetCode.MONGODB_OPERATE_ERROR
    end
    if not data then
        return RetCode.ACCOUNT_NOT_EXIST
    end
    return OnEnterGame(account, data.uid)
end

function AgentMgr.CreateRole(account, loginToken, name)
    local verifyResult = ClusterHelper.CallGateNode(".gatewatchdog", "VerifyToken", account, loginToken)
    if not verifyResult then
        Logger.Error("CreateRole 验证token失败 account:%s", account)
        return RetCode.INVALID_TOKEN
    end
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account }, {uid = 1})
    if not ret then
        Logger.Error("加载玩家数据失败 account:%s err:%s", account, data)
        return RetCode.MONGODB_OPERATE_ERROR
    end
    -- 账号已存在
    if data then
        return RetCode.ACCOUNT_CREATE_REPEATED
    end
    local ret1, uid = skynet.call(".guid", "lua", "GenUid")
    if not ret1 then
        return RetCode.GEN_UID_ERROR
    end

    local accountData = {
        account = account,
        name = name,
        uid = uid,
    }
    local succ, err = skynet.call(".mongodb", "lua", "InsertOne", "userdata", accountData)
    if not succ then
        Logger.Error("创建账号失败 account:%s err:%s", account, err)
        return RetCode.MONGODB_OPERATE_ERROR
    end
    return RetCode.SUCCESS
end

------------------------------------ 客户端 req ----------------------------------------------------

-- 请求进入游戏
local function C2SEnterGame(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    resp.retCode = AgentMgr.EnterGame(account, loginToken)
    Logger.Debug("C2SEnterGame account:%s retCode:%s", account, resp.retCode)
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_enter_game", "player_base.s2c_enter_game", C2SEnterGame)

-- 请求创建角色
local function C2SCreateRole(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    local name = req.name
    resp.retCode = AgentMgr.CreateRole(account, loginToken, name)
    Logger.Debug("C2SCreateRole account:%s retCode:%s", account, resp.retCode)
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_create_role", "player_base.s2c_create_role", C2SCreateRole)

local function C2SQueryUid(req, resp)
    local account = req.account
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account }, {uid = 1})
    if not ret then
        resp.retCode = RetCode.MONGODB_OPERATE_ERROR
        return
    end
    resp.retCode = RetCode.SUCCESS
    resp.uid = data and data.uid
    Logger.Debug("C2SQueryUid account:%s uid:%s", account, resp.uid)
end
ProtocolHelper.RegisterRpcHandler("player_base.c2s_query_uid", "player_base.s2c_query_uid", C2SQueryUid)

return AgentMgr
