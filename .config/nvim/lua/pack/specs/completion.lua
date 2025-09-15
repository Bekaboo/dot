return {
  {
    src = 'https://github.com/saghen/blink.cmp',
    data = {
      build = 'cargo build --release',
      events = { 'InsertEnter', 'CmdlineEnter' },
    },
  },

  {
    src = 'https://github.com/L3MON4D3/LuaSnip',
    data = {
      build = 'make install_jsregexp',
      events = { event = 'ModeChanged', pattern = '*:[iRss\x13vV\x16]*' },
    },
  },
}
