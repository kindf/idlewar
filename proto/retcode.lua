local RetCode = {}

RetCode.SUCCESS = 1 -- 成功
RetCode.FAILED = 2 -- 失败

RetCode.PROTO_DECODE_ERROR = 100 -- 协议解析错误

RetCode.SYSTEM_ERROR = 200 -- 系统错误
RetCode.ACCOUNT_NOT_LOGIN = 201 -- 账号未登录
RetCode.CREATE_AGENT_ERROR = 202 -- 创建agent失败
RetCode.RESTART_AGENT_ERROR = 203 -- 重启agent失败

return RetCode
