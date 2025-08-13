return {
  {
    'saghen/blink.cmp',
    version = '1.*',
    event = { 'InsertEnter', 'CmdlineEnter' },
    config = function()
      require('configs.blink-cmp')
    end,
  },

  {
    'L3MON4D3/LuaSnip',
    build = 'make install_jsregexp',
    event = 'ModeChanged *:[iRss\x13vV\x16]*',
    config = function()
      require('configs.luasnip')
    end,
  },
}
