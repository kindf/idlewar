local Logger = require "public.logger"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"
local skynet = require "skynet"
local ClusterHelper = require "public.cluster_helper"
local DEFINE = require "public.define"
local RetCode = require "proto.retcode"
local ProtocolHelper = require "public.protocol_helper"
local Pids = require "proto.pids"
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
        status = DEFINE.CONNECTION_STATUS.CONNECTED,
    }
end

function GateMgr.Init(ip, port)
    gate = skynet.newservice("gate")
    skynet.send(gate, "lua", "open", {
        host = ip,
        port = port,
    })
    ProtocolHelper.RegisterProtocol()
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

-- 发送客户端消息
function GateMgr.SendClientMessage(fd, msg)
    local connection = fd2Connection[fd]
    if not connection then
        return Logger.Error("GateMgr.SendClientMessage 连接不存在 fd=%s", fd)
    end
    socket.write(fd, netpack.pack(msg))
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

function GateMgr.HandleLoginCheckVersion(conn, _, msg)
    local resp = {}
    repeat
        if conn.status ~= DEFINE.CONNECTION_STATUS.CONNECTED then
            resp.retCode = RetCode.CHECK_VERSION_FAILED
            break
        end
        local ret, result = ClusterHelper.CallLoginNode(".login", "CheckVersion", msg)
        assert(ret, string.format("[GateMgr.HandleLoginCheckVersion] 远程调用失败 err:%s", result))
        resp.retCode = result
        if result == RetCode.SUCCESS then
            conn.status = DEFINE.CONNECTION_STATUS.VERSION_CHECKED
            break
        end
    until true
    local pack = ProtocolHelper.Encode("login.s2c_check_version", resp)
    GateMgr.SendClientMessage(conn.fd, pack)
end

function GateMgr.HandleLoginAuth(conn, _, msg)
    local resp = {}
    local function f()
        if conn.status ~= DEFINE.CONNECTION_STATUS.VERSION_CHECKED then
            return RetCode.VERSION_NOT_CHECKED
        end
        conn.status = DEFINE.CONNECTION_STATUS.LOGINING
        local ret, result = ClusterHelper.CallLoginNode(".login", "CheckAuth", msg)
        assert(ret, string.format("[GateMgr.HandleLoginAuth] 远程调用失败 err:%s", result))
        -- 认证成功
        if result.retCode == RetCode.SUCCESS then
            conn.status = DEFINE.CONNECTION_STATUS.AUTHED
            conn.loginToken = result.loginToken
            resp.loginToken = result.loginToken
            tokenMap[result.loginToken] = {
                account = result.account,
                expireTime = os.time() + 300,
            }
            account2Connection[result.account] = conn
        end
        return result.retCode
    end
    resp.retCode = f()
    local pack = ProtocolHelper.Encode("login.s2c_login_auth", resp)
    GateMgr.SendClientMessage(conn.fd, pack)
end

function GateMgr.SetConnectionGaming(account)
    local conn = assert(account2Connection[account], string.format("[GateMgr.SetConnectionGaming] 连接不存在 account:%s", account))
    conn.status = DEFINE.CONNECTION_STATUS.GAMING
    uid2Connection[conn.uid] = conn
    fd2Connection[conn.fd] = conn
end

return GateMgr
