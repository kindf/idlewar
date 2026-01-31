local skynet = require "skynet"
require "skynet.manager"
local ClusterHelper = require "public.cluster_helper"
local Pids = require "proto.pids"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local pb = require "pb"
local RetCode = require "proto.retcode"

local CMD = {}

--登录状态
local accountLoginState = {
    -- [fd] = {
    --     state = xxx, -- 状态
    --     token = xxx, -- token
    --     timeout = xxx -- 超时
    -- },
}
local LOGIN_SUCCESS_STATE = 1

--检查账号是否已经登录
function CMD.CheckAccountLogin(fd, token)
    local fdLoginState = accountLoginState[fd]
    if not fdLoginState then
        return false
    end
    if fdLoginState.state ~= LOGIN_SUCCESS_STATE then
        return false
    end
    if fdLoginState.timeout < os.time() then
        fdLoginState[fd] = nil
        return false
    end
    if fdLoginState.token == token then
        fdLoginState[fd] = nil
        return true
    end
    return false
end

--检查版本
local function C2SCheckVersion(req, resp)
    resp.retCode = RetCode.SUCCESS
    Logger.Debug("接受到Gate转发的协议 version:%s", req.version)
end
ProtocolHelper.RegisterRpcHandler(Pids["login.c2s_check_version"], Pids["login.s2c_check_version"], C2SCheckVersion)

--登录认证
local function C2SLoginAuth(req, resp)
    local account = req.account
    local token = req.token
    local loginState = accountLoginState[account]
    -- 已在登录
    if loginState then
        resp.retCode = RetCode.FAILED
        return
    end
    -- TODO: sdk token认证 && 生成新的服务器token
    local loginToken = "token"
    loginState = {}
    loginState.state = LOGIN_SUCCESS_STATE
    loginState.token = loginToken
    loginState.timeout = os.time() + 300
    accountLoginState[account] = loginState
    resp.retCode = RetCode.SUCCESS
    resp.loginToken = loginToken
end
ProtocolHelper.RegisterRpcHandler(Pids["login.c2s_login_auth"], Pids["login.s2c_login_auth"], C2SLoginAuth)

-- 分发 Gate 转发过来的消息
function CMD.DispatchClientMessage(fd, protoId, protoBody)
    local protoName = Pids[protoId]
    assert(protoName, "不存在的协议 protoId:" .. protoId)
    local msg = pb.decode(protoName, protoBody)
    local handler = ProtocolHelper.GetProtocolHandler(protoId)
    if not handler then
        return Logger.Error("协议处理函数不存在 protoId:" .. protoId)
    end
    if handler.type == "protocol" then
        local ret, err = pcall(handler.handler, msg)
        if not ret then
            Logger.Error(err)
        end
    else
        local resp = {}
        local ret, err = pcall(handler.handler, msg, resp)
        if not ret then
            Logger.Error(err)
        end
        ClusterHelper.SendClientMessage(fd, handler.respProtoId, resp)
    end
    Logger.Debug("协议转发成功 protoId:%s", protoId)
end

function CMD.start()
    ProtocolHelper.RegisterProtocol()
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        Logger.Debug("cmd:%s subcmd:%s", cmd, subcmd)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
    skynet.register(".login")
end)
