local skynet = require "skynet.manager"
local M = {}

function M.abort_new_service(name, ...)
    local ok, ret = pcall(skynet.newservice, name, ...)
    if not ok then
        skynet.error(name, " start error.", ret)
        skynet.sleep(1)
        skynet.abort()
    else
        skynet.error(name, " start...")
    end
    return ret
end

function M.assert_skynet_call(...)
    local ok, err = pcall(...)
    if not ok then
        skynet.error("assert_skynet_call error:", err)
        skynet.sleep(1)
        skynet.abort()
    end
end

return M
