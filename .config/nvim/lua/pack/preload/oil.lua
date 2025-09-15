-- Ensure that img-clip is loaded before oil to prevent its `vim.paste`
-- handler from overriding oil's (see `lua/configs/oil.lua`)
require('utils.load').load('img-clip')
