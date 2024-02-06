local skynet = require "skynet.manager"

skynet.start(function()
    skynet.newservice("test_login")
end)
