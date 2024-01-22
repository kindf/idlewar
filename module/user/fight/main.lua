local skynet = require "skynet.manager"
local M = {}

function M.main_fight(user, data)
    skynet.error("main_fight user, data", user.uid, data)
end

return M
