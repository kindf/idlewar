local skynet = require "skynet"
require "skynet.manager"
local Pids = require "proto.pids"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local RetCode = require "proto.retcode"
local ServiceHelper = require "public.service_helper"

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
function CMD.CheckAccountLoginSucc(acc, token)
    local accLoginState = accountLoginState[acc]
    if not accLoginState then
        return false
    end
    if accLoginState.state ~= LOGIN_SUCCESS_STATE then
        return false
    end
    if accLoginState.timeout < os.time() then
        accLoginState[acc] = nil
        return false
    end
    if accLoginState.loginToken == token then
        accLoginState[acc] = nil
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
    loginState.loginToken = loginToken
    loginState.timeout = os.time() + 300
    accountLoginState[account] = loginState
    resp.retCode = RetCode.SUCCESS
    resp.loginToken = loginToken
    Logger.Debug("[C2SLoginAuth] 接受到Gate转发的协议 account:%s token:%s", account, token)
end
ProtocolHelper.RegisterRpcHandler(Pids["login.c2s_login_auth"], Pids["login.s2c_login_auth"], C2SLoginAuth)

function CMD.start()
    ProtocolHelper.RegisterProtocol()
end

CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        Logger.Debug("cmd:%s subcmd:%s", cmd, subcmd)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
    skynet.register(".login")
end)
