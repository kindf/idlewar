local Logger = require "public.logger"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local skynet = require "skynet"
local ClusterHelper = require "public.cluster_helper"
local DEFINE = require "public.define"
local RetCode = require "proto.retcode"
local ProtocolHelper = require "public.protocol_helper"
local SessionMgr = require "module.gate.session_mgr"
local Timer = require "public.timer"
-- 常量定义
local CONNECTION_STATUS = DEFINE.CONNECTION_STATUS

local GateMgr = {
    gate = nil,
    cleanupTimer = Timer.New(),
    cleanupTimerId = nil,
}

-- 初始化网关
function GateMgr:Init(ip, port)
    assert(ip and port, "GateMgr.Init: ip and port required")
    self.gate = skynet.newservice("gate")
    skynet.send(self.gate, "lua", "open", {
        host = ip,
        port = port,
    })
    ProtocolHelper.RegisterProtocol()
    Logger.Info("GateMgr 初始化 on %s:%d", ip, port)
    -- 启动定时清理任务（每30秒执行一次）
    self.cleanupTimerId = self.cleanupTimer:Interval(30, function() GateMgr:CleanupTimer() end, false)
end

-- 定时清理任务
function GateMgr:CleanupTimer()
    SessionMgr:CleanupExpiredSessions()
    SessionMgr:CleanupExpiredTokens()

    -- 定期输出统计信息
    local stats = SessionMgr:GetStats()
    Logger.Info("GateMgr stats - active:%d tokens:%d created:%d closed:%d", stats.active, stats.tokens, stats.totalCreated, stats.totalClosed)
end

-- 获取连接
function GateMgr:GetSession(fd)
    return SessionMgr:GetByFd(fd)
end

-- 添加新连接
function GateMgr:AddSession(fd, ip)
    local session = SessionMgr:Add(fd, ip)
    return function()
        skynet.call(self.gate, "lua", "accept", fd)
    end
end

-- 关闭连接(接受到socket关闭的通知)
function GateMgr:CloseSession(fd, reason)
    SessionMgr:Close(fd, reason)
end

-- 踢掉客户端(主动踢掉)
function GateMgr:CloseFd(fd, reason)
    SessionMgr:Close(fd, reason)
    skynet.call(self.gate, "lua", "kick", fd)
end

-- 发送消息给客户端
function GateMgr:SendClientMessage(fd, msg)
    local session = SessionMgr:GetByFd(fd)
    if not session then
        Logger.Warn("GateMgr.SendClientMessage session not found fd=%s", fd)
        return false
    end

    session:UpdateActiveTime()

    local success, err = pcall(socket.write, fd, netpack.pack(msg))
    if not success then
        Logger.Error("GateMgr.SendClientMessage failed fd=%s err=%s", fd, err)
        SessionMgr:Close(fd, "发送消息失败")
        return false
    end

    return true
end

-- 验证Token
function GateMgr:VerifyToken(account, loginToken)
    return SessionMgr:VerifyToken(loginToken, account)
end

-- 处理版本检查
function GateMgr:HandleLoginCheckVersion(session, _, msg)
    local resp = { retCode = RetCode.SUCCESS }
    repeat
        if not session or not msg then
            Logger.Error("GateMgr.HandleLoginCheckVersion invalid params")
            return
        end

        -- 状态验证
        if session:GetStatus() ~= CONNECTION_STATUS.CONNECTED then
            Logger.Warn("GateMgr.HandleLoginCheckVersion invalid state %s", session:ToLogString())
            resp.retCode = RetCode.CHECK_VERSION_FAILED
            break
        end

        -- 远程调用
        local success, result = ClusterHelper.CallLoginNode(".login", "CheckVersion", msg)
        if not success then
            Logger.Error("GateMgr.HandleLoginCheckVersion remote call failed %s", result)
            resp.retCode = RetCode.SYSTEM_ERROR
            break
        end

        resp.retCode = result

        -- 状态转换
        if result == RetCode.SUCCESS then
            if not session:ChangeState(CONNECTION_STATUS.VERSION_CHECKED) then
                resp.retCode = RetCode.SYSTEM_ERROR
            end
        end
    until true
    local pack = ProtocolHelper.Encode("login.s2c_check_version", resp)
    GateMgr:SendClientMessage(session:GetFd(), pack)
end

-- 处理登录认证
function GateMgr:HandleLoginAuth(session, _, msg)
    local resp = { retCode = RetCode.SUCCESS }
    repeat
        if not session or not msg then
            Logger.Error("GateMgr.HandleLoginAuth invalid params")
            return
        end

        -- 状态验证
        if session:GetStatus() ~= CONNECTION_STATUS.VERSION_CHECKED then
            Logger.Warn("GateMgr.HandleLoginAuth invalid state %s", session:ToLogString())
            resp.retCode = RetCode.VERSION_NOT_CHECKED
            break
        end

        -- 转换到登录中状态
        if not session:ChangeState(CONNECTION_STATUS.LOGINING) then
            resp.retCode = RetCode.SYSTEM_ERROR
            break
        end

        -- 远程调用认证
        local success, result = ClusterHelper.CallLoginNode(".login", "CheckAuth", msg)
        if not success then
            Logger.Error("GateMgr.HandleLoginAuth remote call failed %s", result)
            resp.retCode = RetCode.SYSTEM_ERROR
            session:ChangeState(CONNECTION_STATUS.VERSION_CHECKED) -- 回滚
            break
        end

        -- 认证成功
        if result.retCode == RetCode.SUCCESS then
            -- 生成Token
            local loginToken = string.format("%s_%d_%d", result.account, os.time(), math.random(10000, 99999))

            -- 绑定账号
            SessionMgr:BindAccount(session:GetFd(), result.account)
            session:SetLoginToken(loginToken)

            -- 存储Token
            SessionMgr:AddToken(loginToken, result.account)

            -- 状态转换
            session:ChangeState(CONNECTION_STATUS.AUTHED)

            -- 填充响应
            resp.loginToken = loginToken

            Logger.Info("GateMgr.HandleLoginAuth success account=%s fd=%s",
                result.account, session:GetFd())
        else
            -- 认证失败，回滚状态
            session:ChangeState(CONNECTION_STATUS.VERSION_CHECKED)
        end

        resp.retCode = result.retCode
    until true
    local pack = ProtocolHelper.Encode("login.s2c_login_auth", resp)
    GateMgr:SendClientMessage(session:GetFd(), pack)
end

-- 设置连接为游戏中状态
function GateMgr:SetConnectionGaming(account)
    local session = SessionMgr:GetByAccount(account)
    if not session then
        Logger.Error("GateMgr.SetConnectionGaming session not found account:%s", account)
        return false
    end

    -- 状态转换
    if not session:ChangeState(CONNECTION_STATUS.GAMING) then
        return false
    end

    -- 如果有uid，绑定uid映射
    if session.uid then
        SessionMgr:BindUid(account, session.uid)
    end

    Logger.Info("GateMgr.SetConnectionGaming success %s", session:ToLogString())
    return true
end

-- 踢掉玩家
function GateMgr:KickPlayer(uid, reason)
    local session = SessionMgr:GetByUid(uid)
    if not session then
        Logger.Warn("GateMgr.KickPlayer player not found uid=%s", uid)
        return false
    end

    reason = reason or "kicked by server"
    GateMgr.CloseFd(session:GetFd(), reason)

    Logger.Info("GateMgr.KickPlayer uid=%s reason=%s", uid, reason)
    return true
end

-- 获取在线玩家数量
function GateMgr:GetOnlineCount()
    local count = 0
    for _, session in pairs(SessionMgr.fd2Session) do
        if session:GetStatus() == CONNECTION_STATUS.GAMING then
            count = count + 1
        end
    end
    return count
end

-- 获取所有在线玩家信息
function GateMgr:GetOnlinePlayers()
    local players = {}
    for _, session in pairs(SessionMgr.uid2Session) do
        if session:GetStatus() == CONNECTION_STATUS.GAMING then
            table.insert(players, {
                uid = session:GetUid(),
                account = session:GetAccount(),
                fd = session:GetFd(),
                idleTime = session:GetIdleTime(),
                clientInfo = session.clientInfo,
            })
        end
    end
    return players
end

-- 获取统计信息
function GateMgr:GetStats()
    return SessionMgr:GetStats()
end

-- 清理过期的Token（保持原接口）
function GateMgr:CleanupExpiredTokens()
    SessionMgr:CleanupExpiredTokens()
end

return GateMgr
