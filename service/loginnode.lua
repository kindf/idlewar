local skynet = require "skynet"
local crypt = require "skynet.crypt"
local cluster = require "skynet.cluster"
local clusterConfig = require "etc.cluster"
local RpcHelper = require "util.rpc_helper"
local nodeName = skynet.getenv("nodename")

local CMD = {}
local loginCache = {}

local LOGIN_AUTH_STATE = 1    -- 用户登录中
local LOGIN_SUCCESS_STATE = 2 -- 用户登录成功
local gateProxy

local function SendGateProxy(...)
    if not gateProxy then
        gateProxy = cluster.proxy("gatenode", ".gatenode")
    end
    return skynet.call(gateProxy, "lua", ...)
end

local function CheckAuth(account, version, data)
    if loginCache[account] then
        return false, "用户登录中"
    end

    if not version then
        return false, "版本号错误"
    end
    loginCache[account] = {
        account = account,
        token = nil,
        expire = os.time() + 300,
        state = LOGIN_AUTH_STATE
    }
    return true
end
RpcHelper.RegisterClientHandler("check_auth", CheckAuth)

local function CheckToken(account, token)
    return true
end

local function CheckAuth(account, token)
    if not loginCache[account] then
        return false, "用户未登录"
    end

    if not CheckToken(account, token) then
        return false, "token无效"
    end

    if loginCache[account].expire < os.time() then
        loginCache[account] = nil
        return false, "登录已过期"
    end

    -- 生成token
    local loginToken = crypt.base64encode(crypt.randomkey())
    loginCache[account].token = loginToken
    loginCache[account].state = LOGIN_SUCCESS_STATE

    return true, loginToken
end
RpcHelper.RegisterClientHandler("check_auth", CheckAuth)

function CMD.check_auth(account, token)
    local ret, loginToken = CheckAuth(account, token)
    if not ret then
        SendGateProxy("login", account, loginToken)
    end
    SendGateProxy("login", account, loginToken)
end

local function CheckVersion(account, token)
    local data = loginCache[account]
    if not data then
        return false, "token无效"
    end

    if data.state ~= LOGIN_SUCCESS_STATE then
        return false, "未完成登录认证"
    end

    if data.expire < os.time() then
        loginCache[account] = nil
        return false, "token已过期"
    end

    if data.token ~= token then
        return false, "token无效"
    end

    return true
end
RpcHelper.RegisterClientHandler("check_version", CheckVersion)

function CMD.logout(source, userid, token)
end

function CMD.kick_user(source, account)
    -- 查找对应的token并清理
    loginCache[account] = nil
    return true
end

skynet.register_protocol {
    name = "gatenode",
    id = skynet.PTYPE_GATE,
    unpack = function ( msg, sz )
        return netpack.filter( queue, msg, sz)
    end,
    dispatch = function (_, _, q, type, ...)
        RpcHelper.DispatchClientMessage(q, type, ...)
    end
}

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.retpack(f(source, ...))
    end)
    skynet.register(".loginnode")
    cluster.reload(clusterConfig)
    cluster.open(nodeName)
    skynet.error("Login service start")
end)
