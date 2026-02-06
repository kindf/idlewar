local RetCode = {}

RetCode.SUCCESS = 1 -- 成功
RetCode.FAILED = 2 -- 失败

RetCode.SYSTEM_ERROR = 100 -- 系统错误
RetCode.ACCOUNT_NOT_LOGIN = 101 -- 账号未登录
RetCode.CREATE_AGENT_ERROR = 102 -- 创建agent失败
RetCode.RESTART_AGENT_ERROR = 103 -- 重启agent失败

return RetCode
