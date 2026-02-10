local Logger = require "public.logger"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local skynet = require "skynet"
local ClusterHelper = require "public.cluster_helper"
local DEFINE = require "define"
local GateMgr = {}
local gate

local fd2Connection = {}
local account2Connection = {}
local uid2Connection = {}
local tokenMap = {}

local function NewConnection(fd, ip)
    return {
        fd = fd,
        ip = string.match(ip, "([%d.]+):(%d+)"),
        agentNode = nil,
        agentAddr = nil,
        uid = nil,
        account = nil,
        closeReason = nil,
        loginToken = nil,
        status = "connected",
    }
end

function GateMgr.Init(ip, port)
    gate = skynet.newservice("gate")
    skynet.send(gate, "lua", "open", {
        host = ip,
        port = port,
    })
end

function GateMgr.GetConnection(fd)
    return fd2Connection[fd]
end

function GateMgr.AddConnection(fd, ip)
    if fd2Connection[fd] then
        return Logger.Error("GateMgr.AddConnection 连接已存在 fd=%s", fd)
    end
    fd2Connection[fd] = NewConnection(fd, ip)
    return function()
        skynet.call(gate, "lua", "accept", fd)
    end
end

function GateMgr.CloseConnection(fd, reason)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.CloseConnection 连接不存在 fd=%s", fd)
    end
    fd2Connection[fd] = nil
end

function GateMgr.CloseFd(fd, reason)
    local connection = fd2Connection[fd]
    if connection then
        connection.closeReason = reason
    end
    skynet.call(gate, "lua", "kick", fd)
end

function GateMgr.SendClientMessage(fd, msg)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.SendClientMessage 连接不存在 fd=%s", fd)
    end
    socket.write(fd, netpack.pack(msg))
end

function GateMgr.LoginResult(fd, retCode, account, loginToken)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.LoginResult 连接不存在 fd=%s", fd)
    end
    if not retCode then
        connection.status = "connected"
        return
    end
    connection.account = account
    connection.loginToken = loginToken
    tokenMap[loginToken] = {
        account = account,
        expireTime = os.time() + 300, -- 5min过期时间
    }
    account2Connection[account] = connection
    local succ, uid = ClusterHelper.CallGameAgentMgr("PlayerConnect", account, loginToken, fd)
    if not succ then
        return Logger.Error("GateMgr.LoginResult PlayerConnect失败 account:%s", account)
    end
    uid2Connection[uid] = connection
end

function GateMgr.VerifyToken(account, loginToken)
    local tokenInfo = tokenMap[loginToken]
    local conn = account2Connection[account]
    if tokenInfo and tokenInfo.account == account and os.time() < tokenInfo.expireTime 
        and conn then
        return true
    end
    return false
end

local function ConnectGameWorld(fd, account)
    local conn = fd2Connection[fd]
    if not conn then
        return Logger.Error("GateMgr.ConnectGameWorld 连接不存在 fd=%s", fd)
    end

    local succ, uid = ClusterHelper.CallGameAgentMgr("PlayerConnect", fd, account)
    if not succ then
        return Logger.Error("GateMgr.ConnectGameWorld PlayerConnect失败 account:%s", account)
    end
    conn = uid2Connection[uid]
    if conn then
        uid2Connection[uid] = conn
        conn.uid = uid
    end
end

function GateMgr.HandleLoginCheckAuth(conn, protoId, msg)
    conn.status = DEFINE.CONNECTION_STATUS.LOGINING
    local result = ClusterHelper.CallLoginNode(".login", "CheckAuth", msg)
    -- 认证成功
    if result.succ then
        conn.status = DEFINE.CONNECTION_STATUS.AUTHED
        conn.loginToken = result.loginToken
        tokenMap[result.loginToken] = {
            account = result.account,
            expireTime = os.time() + 300,
        }
        account2Connection[result.account] = conn
        ConnectGameWorld(conn.fd, result.account)
    else
        conn.status = DEFINE.CONNECTION_STATUS.CONNECTED
    end
end


return GateMgr
