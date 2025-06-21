local utils = require('utils')

---Check if there exists an LS that supports the given method
---for the given buffer
---@param method string the method to check for
---@param bufnr number buffer handler
local function supports_method(method, bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client:supports_method(method) then
      return true
    end
  end
  return false
end

---Setup LSP keymaps
---@return nil
local function setup_keymaps()
  -- stylua: ignore start
  vim.keymap.set({ 'n' }, 'gq;', function() vim.lsp.buf.format() end, { desc = 'Format buffer' })
  vim.keymap.set({ 'i' }, '<M-a>', function() vim.lsp.buf.code_action() end, { desc = 'Show code actions' })
  vim.keymap.set({ 'i' }, '<C-_>', function() vim.lsp.buf.code_action() end, { desc = 'Show code actions' })
  vim.keymap.set({ 'n', 'x' }, 'g/', function() vim.lsp.buf.references() end, { desc = 'Go to references' })
  vim.keymap.set({ 'n', 'x' }, 'g.', function() vim.lsp.buf.implementation() end, { desc = 'Go to implementation' })
  vim.keymap.set({ 'n', 'x' }, 'gb', function() vim.lsp.buf.type_definition() end, { desc = 'Go to type definition' })
  vim.keymap.set({ 'n', 'x' }, 'gd', function() return supports_method('textDocument/definition', 0) and '<Cmd>lua vim.lsp.buf.definition()<CR>' or 'gd' end, { expr = true, desc = 'Go to definition' })
  vim.keymap.set({ 'n', 'x' }, 'gD', function() return supports_method('textDocument/declaration', 0) and '<Cmd>lua vim.lsp.buf.declaration()<CR>' or 'gD' end, { expr = true, desc = 'Go to declaration' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>r', function() vim.lsp.buf.rename() end, { desc = 'Rename symbol' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>a', function() vim.lsp.buf.code_action() end, { desc = 'Show code actions' })
  vim.keymap.set({ 'n', 'x' }, '<Leader><', function() vim.lsp.buf.incoming_calls() end, { desc = 'Show incoming calls' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>>', function() vim.lsp.buf.outgoing_calls() end, { desc = 'Show outgoing calls' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>s', function() vim.lsp.buf.document_symbol() end, { desc = 'Show document symbols' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>S', function() vim.lsp.buf.workspace_symbol() end, { desc = 'Show workspace symbols' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>d', function() vim.diagnostic.setloclist() end, { desc = 'Show document diagnostics' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>D', function() vim.diagnostic.setqflist() end, { desc = 'Show workspace diagnostics' })
  -- stylua: ignore end

  ---Open diagnostic floating window, jump to existing window if possible
  ---@return nil
  local function diagnostic_open_float()
    ---@param win integer
    ---@return boolean
    local function is_diag_win(win)
      if vim.fn.win_gettype(win) ~= 'popup' then
        return false
      end
      local buf = vim.api.nvim_win_get_buf(win)
      return vim.bo[buf].bt == 'nofile'
        and unpack(vim.api.nvim_buf_get_lines(buf, 0, 1, false))
          == 'Diagnostics:'
    end

    -- If a diagnostic float window is already open, switch to it
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if is_diag_win(win) then
        vim.api.nvim_set_current_win(win)
        return
      end
    end

    -- Else open diagnostic float
    vim.diagnostic.open_float()
  end

  -- stylua: ignore start
  -- nvim's default mapping
  vim.keymap.set({ 'n', 'x' }, '<M-d>', diagnostic_open_float, { desc = 'Open diagnostic floating window' })
  vim.keymap.set({ 'n', 'x' }, '<C-w>d', diagnostic_open_float, { desc = 'Open diagnostic floating window' })
  vim.keymap.set({ 'n', 'x' }, '<C-w><C-d>', diagnostic_open_float, { desc = 'Open diagnostic floating window' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>i', diagnostic_open_float, { desc = 'Open diagnostic floating window' })
  -- stylua: ignore end

  vim.keymap.set({ 'n', 'x' }, 'gy', function()
    local diags = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
    local n_diags = #diags
    if n_diags == 0 then
      vim.notify(
        '[LSP] no diagnostics found in current line',
        vim.log.levels.WARN
      )
      return
    end

    ---@param msg string
    local function _yank(msg)
      vim.fn.setreg('"', msg)
      vim.fn.setreg(vim.v.register, msg)
    end

    if n_diags == 1 then
      local msg = diags[1].message
      _yank(msg)
      vim.notify(
        string.format([[[LSP] yanked diagnostic message '%s']], msg),
        vim.log.levels.INFO
      )
      return
    end

    vim.ui.select(
      vim.tbl_map(function(d)
        return d.message
      end, diags),
      { prompt = 'Select diagnostic message to yank: ' },
      _yank
    )
  end, { desc = 'Yank diagnostic message on current line' })

  -- stylua: ignore start
  vim.keymap.set({ 'n', 'x' }, '[d', function() vim.diagnostic.jump({ count = -vim.v.count1 }) end, { desc = 'Go to previous diagnostic' })
  vim.keymap.set({ 'n', 'x' }, ']d', function() vim.diagnostic.jump({ count =  vim.v.count1 }) end, { desc = 'Go to next diagnostic' })
  vim.keymap.set({ 'n', 'x' }, '[e', function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR }) end, { desc = 'Go to previous diagnostic error' })
  vim.keymap.set({ 'n', 'x' }, ']e', function() vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.ERROR }) end, { desc = 'Go to next diagnostic error' })
  vim.keymap.set({ 'n', 'x' }, '[w', function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN }) end, { desc = 'Go to previous diagnostic warning' })
  vim.keymap.set({ 'n', 'x' }, ']w', function() vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.WARN }) end, { desc = 'Go to next diagnostic warning' })
  vim.keymap.set({ 'n', 'x' }, '[i', function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.INFO }) end, { desc = 'Go to previous diagnostic info' })
  vim.keymap.set({ 'n', 'x' }, ']i', function() vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.INFO }) end, { desc = 'Go to next diagnostic info' })
  vim.keymap.set({ 'n', 'x' }, '[h', function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.HINT }) end, { desc = 'Go to previous diagnostic hint' })
  vim.keymap.set({ 'n', 'x' }, ']h', function() vim.diagnostic.jump({ count =  vim.v.count1, severity = vim.diagnostic.severity.HINT }) end, { desc = 'Go to next diagnostic hint' })
  -- stylua: ignore end
end

---Setup LSP handlers overrides
---@return nil
local function setup_lsp_overrides()
  vim.lsp.config('*', utils.lsp.default_config)
  vim.lsp.start = utils.lsp.start -- override for additional checks

  -- Show notification if no references, definition, declaration,
  -- implementation or type definition is found
  local methods = {
    'textDocument/references',
    'textDocument/definition',
    'textDocument/declaration',
    'textDocument/implementation',
    'textDocument/typeDefinition',
  }

  for _, method in ipairs(methods) do
    local obj_name = method:match('/(%w*)$'):gsub('s$', '')
    local handler = vim.lsp.handlers[method]

    vim.lsp.handlers[method] = function(err, result, ctx, ...)
      if not result or vim.tbl_isempty(result) then
        vim.notify('[LSP] no ' .. obj_name .. ' found')
        return
      end

      -- textDocument/definition can return Location or Location[]
      -- https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_definition
      if not vim.islist(result) then
        result = { result }
      end

      if #result == 1 then
        local enc = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
        vim.lsp.util.jump_to_location(result[1], enc)
        return
      end

      handler(err, result, ctx, ...)
    end
  end

  -- Configure hovering window style
  -- Hijack LSP floating window function to use custom options
  local _open_floating_preview = vim.lsp.util.open_floating_preview
  ---@param contents table of lines to show in window
  ---@param syntax string of syntax to set for opened buffer
  ---@param opts table with optional fields (additional keys are passed on to |nvim_open_win()|)
  ---@returns bufnr,winnr buffer and window number of the newly created floating preview window
  ---@diagnostic disable-next-line: duplicate-set-field
  function vim.lsp.util.open_floating_preview(contents, syntax, opts)
    opts = vim.tbl_deep_extend('force', opts, {
      border = 'solid',
      max_width = math.max(80, math.ceil(vim.go.columns * 0.75)),
      max_height = math.max(20, math.ceil(vim.go.lines * 0.4)),
      close_events = {
        'CursorMovedI',
        'CursorMoved',
        'InsertEnter',
        'WinScrolled',
        'WinResized',
        'VimResized',
      },
    })
    local floating_bufnr, floating_winnr =
      _open_floating_preview(contents, syntax, opts)
    vim.wo[floating_winnr].concealcursor = 'nc'
    return floating_bufnr, floating_winnr
  end

  -- Use loclist instead of qflist by default when showing document symbols
  local _lsp_document_symbol = vim.lsp.buf.document_symbol
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.buf.document_symbol = function()
    ---@diagnostic disable-next-line: redundant-parameter
    _lsp_document_symbol({
      loclist = true,
    })
  end
end

---@class lsp_command_parsed_arg_t : parsed_arg_t
---@field apply boolean|nil
---@field async boolean|nil
---@field bufnr integer|nil
---@field context table|nil
---@field pos table|nil
---@field defaults table|nil
---@field diagnostics table|nil
---@field disable boolean|nil
---@field enable boolean|nil
---@field filter function|nil
---@field float boolean|table|nil
---@field format function|nil
---@field formatting_options table|nil
---@field global boolean|nil
---@field groups table|nil
---@field header string|table|nil
---@field id integer|nil
---@field local boolean|nil
---@field name string|nil
---@field namespace integer|nil
---@field new_name string|nil
---@field open boolean|nil
---@field options table|nil
---@field opts table|nil
---@field pat string|nil
---@field prefix function|string|table|nil
---@field query table|nil
---@field range table|nil
---@field severity integer|nil
---@field severity_map table|nil
---@field severity_sort boolean|nil
---@field show-status boolean|nil
---@field source boolean|string|nil
---@field str string|nil
---@field suffix function|string|table|nil
---@field timeout_ms integer|nil
---@field title string|nil
---@field toggle boolean|nil
---@field winid integer|nil
---@field winnr integer|nil
---@field wrap boolean|nil

---Parse arguments passed to LSP commands
---@param fargs string[] list of arguments
---@param fn_name_alt string|nil alternative function name
---@return string|nil fn_name corresponding LSP / diagnostic function name
---@return lsp_command_parsed_arg_t parsed the parsed arguments
local function parse_cmdline_args(fargs, fn_name_alt)
  local fn_name = fn_name_alt or fargs[1] and table.remove(fargs, 1) or nil
  local parsed = utils.cmd.parse_cmdline_args(fargs)
  return fn_name, parsed
end

---@type string<table, subcommand_arg_handler_t>
local subcommand_arg_handler = {
  ---LSP command argument handler for functions that receive a range
  ---@param args lsp_command_parsed_arg_t
  ---@param tbl table information passed to the command
  ---@return table args
  range = function(args, tbl)
    args.range = args.range
      or tbl.range > 0 and {
        ['start'] = { tbl.line1, 0 },
        ['end'] = { tbl.line2, 999 },
      }
      or nil
    return args
  end,
  ---Extract the first item from a table, expand it to absolute path if possible
  ---@param args lsp_command_parsed_arg_t
  ---@return any
  item = function(args)
    for _, item in pairs(args) do -- luacheck: ignore 512
      return type(item) == 'string' and vim.uv.fs_realpath(item) or item
    end
  end,
  ---Convert the args of the form '<id_1> (<name_1>) <id_2> (<name_2) ...' to
  ---list of client ids
  ---@param args lsp_command_parsed_arg_t
  ---@return integer[]
  lsp_client_ids = function(args)
    local ids = {}
    for _, arg in ipairs(args) do
      local id = tonumber(arg:match('^%d+'))
      if id then
        table.insert(ids, id)
      end
    end
    return ids
  end,
}

---@type table<string, subcommand_completion_t>
local subcommand_completions = {
  bufs = function()
    return vim.tbl_map(function(buf)
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname == '' then
        return tostring(buf)
      end
      return string.format('%d (%s)', buf, vim.fn.fnamemodify(bufname, ':~:.'))
    end, vim.list_extend({ 0 }, vim.api.nvim_list_bufs()))
  end,
  ---Get completion for LSP clients
  ---@return string[]
  lsp_clients = function(arglead)
    -- Only return candidate list if the argument is empty or ends with '='
    -- to avoid giving wrong completion when argument is incomplete
    if arglead ~= '' and not vim.endswith(arglead, '=') then
      return {}
    end
    return vim.tbl_map(function(client)
      return string.format('%d (%s)', client.id, client.name)
    end, vim.lsp.get_clients())
  end,
  ---Get completion for LSP client ids
  ---@return integer[]
  lsp_client_ids = function(arglead)
    if arglead ~= '' and not vim.endswith(arglead, '=') then
      return {}
    end
    return vim.tbl_map(function(client)
      return client.id
    end, vim.lsp.get_clients())
  end,
  ---Get completion for LSP client names
  ---@return integer[]
  lsp_client_names = function(arglead)
    if arglead ~= '' and not vim.endswith(arglead, '=') then
      return {}
    end
    local client_names = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
      client_names[client.name] = true
    end
    return vim.tbl_keys(client_names)
  end,
}

---@type table<string, string[]|fun(): any[]>
local subcommand_opt_vals = {
  bool = { 'v:true', 'v:false' },
  severity = { 'WARN', 'INFO', 'ERROR', 'HINT' },
  bufs = subcommand_completions.bufs,
  lsp_clients = subcommand_completions.lsp_clients,
  lsp_client_ids = subcommand_completions.lsp_client_ids,
  lsp_client_names = subcommand_completions.lsp_client_names,
  lsp_methods = {
    'callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls',
    'textDocument/codeAction',
    'textDocument/completion',
    'textDocument/declaration',
    'textDocument/definition',
    'textDocument/diagnostic',
    'textDocument/documentHighlight',
    'textDocument/documentSymbol',
    'textDocument/formatting',
    'textDocument/hover',
    'textDocument/implementation',
    'textDocument/inlayHint',
    'textDocument/publishDiagnostics',
    'textDocument/rangeFormatting',
    'textDocument/references',
    'textDocument/rename',
    'textDocument/semanticTokens/full',
    'textDocument/semanticTokens/full/delta',
    'textDocument/signatureHelp',
    'textDocument/typeDefinition',
    'window/logMessage',
    'window/showMessage',
    'window/showDocument',
    'window/showMessageRequest',
    'workspace/applyEdit',
    'workspace/configuration',
    'workspace/executeCommand',
    'workspace/inlayHint/refresh',
    'workspace/symbol',
    'workspace/workspaceFolders',
  },
}

---@alias subcommand_arg_handler_t fun(args: lsp_command_parsed_arg_t, tbl: table): ...?
---@alias subcommand_params_t string[]
---@alias subcommand_opts_t table
---@alias subcommand_fn_override_t fun(...?): ...?
---@alias subcommand_completion_t fun(arglead: string, cmdline: string, cursorpos: integer): string[]

---@class subcommand_info_t
---@field arg_handler subcommand_arg_handler_t?
---@field params subcommand_params_t?
---@field opts subcommand_opts_t?
---@field fn_override subcommand_fn_override_t?
---@field completion subcommand_completion_t?

local subcommands = {
  ---LSP subcommands
  ---@type table<string, subcommand_info_t>
  lsp = {
    info = {
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
        ['filter.id'] = subcommand_opt_vals.lsp_client_ids,
        ['filter.name'] = subcommand_opt_vals.lsp_client_names,
        ['filter.method'] = subcommand_opt_vals.lsp_methods,
      },
      arg_handler = function(args)
        return args.filter
      end,
      fn_override = function(filter)
        local clients = vim.lsp.get_clients(filter)
        for _, client in ipairs(clients) do
          vim.print({
            id = client.id,
            name = client.name,
            root_dir = client.config.root_dir,
            attached_buffers = vim.tbl_keys(client.attached_buffers),
          })
        end
      end,
    },
    restart = {
      completion = subcommand_completions.lsp_clients,
      arg_handler = subcommand_arg_handler.lsp_client_ids,
      fn_override = function(ids)
        -- Restart all clients attached to current buffer if no ids are given
        local clients = not vim.tbl_isempty(ids)
            and vim.tbl_map(function(id)
              return vim.lsp.get_client_by_id(id)
            end, ids)
          or vim.lsp.get_clients({ bufnr = 0 })
        for _, client in ipairs(clients) do
          utils.lsp.restart(client, {
            on_restart = function(new_client_id)
              vim.notify(
                string.format(
                  '[LSP] restarted client %d (%s) as client %d',
                  client.id,
                  client.name,
                  new_client_id
                )
              )
            end,
          })
        end
      end,
    },
    get_clients_by_id = {
      completion = subcommand_completions.lsp_clients,
      arg_handler = function(args)
        return tonumber(args[1]:match('^%d+'))
      end,
      fn_override = function(id)
        vim.print(vim.lsp.get_client_by_id(id))
      end,
    },
    get_clients = {
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
        ['filter.id'] = subcommand_opt_vals.lsp_client_ids,
        ['filter.name'] = subcommand_opt_vals.lsp_client_names,
        ['filter.method'] = subcommand_opt_vals.lsp_methods,
      },
      arg_handler = function(args)
        return args.filter
      end,
      fn_override = function(filter)
        local clients = vim.lsp.get_clients(filter)
        for _, client in ipairs(clients) do
          vim.print(client)
        end
      end,
    },
    stop = {
      completion = subcommand_completions.lsp_clients,
      arg_handler = subcommand_arg_handler.lsp_client_ids,
      fn_override = function(ids)
        -- Stop all clients attached to current buffer if no ids are given
        local clients = not vim.tbl_isempty(ids)
            and vim.tbl_map(function(id)
              return vim.lsp.get_client_by_id(id)
            end, ids)
          or vim.lsp.get_clients({ bufnr = 0 })
        for _, client in ipairs(clients) do
          utils.lsp.soft_stop(client, {
            on_close = function()
              vim.notify(
                string.format(
                  '[LSP] stopped client %d (%s)',
                  client.id,
                  client.name
                )
              )
            end,
          })
        end
      end,
    },
    references = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.context, args.options
      end,
      opts = { 'context', 'options.on_list' },
    },
    rename = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.new_name or args[1], args.options
      end,
      opts = {
        'new_name',
        'options.filter',
        'options.name',
      },
    },
    workspace_symbol = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.query, args.options
      end,
      opts = { 'query', 'options.on_list' },
    },
    format = {
      arg_handler = subcommand_arg_handler.range,
      opts = {
        'id',
        'name',
        'range',
        'filter',
        'timeout_ms',
        'formatting_options',
        'formatting_options.tabSize',
        ['formatting_options.insertSpaces'] = subcommand_opt_vals.bool,
        ['formatting_options.trimTrailingWhitespace'] = subcommand_opt_vals.bool,
        ['formatting_options.insertFinalNewline'] = subcommand_opt_vals.bool,
        ['formatting_options.trimFinalNewlines'] = subcommand_opt_vals.bool,
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['async'] = subcommand_opt_vals.bool,
      },
    },
    auto_format = {
      ---@param args lsp_command_parsed_arg_t
      ---@param tbl table information passed to the command
      ---@return lsp_command_parsed_arg_t args
      ---@return table tbl
      arg_handler = function(args, tbl)
        args.format = subcommand_arg_handler.range(args, tbl).format
        return args, tbl
      end,
      params = {
        'enable',
        'disable',
        'toggle',
        'reset',
        'status',
      },
      opts = {
        'format.formatting_options',
        'format.formatting_options.tabSize',
        'format.timeout_ms',
        'format.filter',
        'format.async',
        'format.id',
        'format.name',
        'format.range',
        ['format.bufnr'] = subcommand_opt_vals.bufs,
        ['format.formatting_options.insertSpaces'] = subcommand_opt_vals.bool,
        ['format.formatting_options.trimTrailingWhitespace'] = subcommand_opt_vals.bool,
        ['formatting_options.insertFinalNewline'] = subcommand_opt_vals.bool,
        ['format.formatting_options.trimFinalNewlines'] = subcommand_opt_vals.bool,
        ['local'] = subcommand_opt_vals.bool,
        ['global'] = subcommand_opt_vals.bool,
      },
      ---@param args lsp_command_parsed_arg_t
      ---@param tbl table information passed to the command
      fn_override = function(args, tbl)
        local scope = vim[args.global and 'g' or 'b']

        if scope.lsp_autofmt_enabled == nil then
          scope.lsp_autofmt_enabled = vim.g.lsp_autofmt_enabled
        end

        if tbl.bang or vim.tbl_contains(args, 'toggle') then
          scope.lsp_autofmt_enabled = not scope.lsp_autofmt_enabled
        elseif tbl.fargs[1] == '&' or vim.tbl_contains(args, 'reset') then
          scope.lsp_autofmt_enabled = false
          scope.lsp_autofmt_opts = { async = true, timeout = 500 }
        elseif tbl.fargs[1] == '?' or vim.tbl_contains(args, 'status') then
          vim.notify(
            string.format(
              'enabled: %s',
              scope.lsp_autofmt_enabled ~= nil and scope.lsp_autofmt_enabled
                or vim.g.lsp_autofmt_enabled
            )
          )
          vim.notify(
            string.format(
              'opts: %s',
              vim.inspect(
                scope.lsp_autofmt_opts ~= nil and scope.lsp_autofmt_opts
                  or vim.g.lsp_autofmt_opts
              )
            )
          )
        elseif vim.tbl_contains(args, 'enable') then
          scope.lsp_autofmt_enabled = true
        elseif vim.tbl_contains(args, 'disable') then
          scope.lsp_autofmt_enabled = false
        else
          scope.lsp_autofmt_enabled = true
          vim.notify('[LSP] auto format enabled')
        end

        if args.format then
          scope.lsp_autofmt_opts = vim.tbl_deep_extend(
            'force',
            scope.lsp_autofmt_opts or {},
            args.format
          )
        end
      end,
    },
    code_action = {
      opts = {
        'filter',
        'range',
        'context.only',
        'context.triggerKind',
        'context.diagnostics',
        ['apply'] = subcommand_opt_vals.bool,
      },
    },
    add_workspace_folder = {
      arg_handler = subcommand_arg_handler.item,
      completion = function(arglead, _, _)
        local basedir = arglead == '' and vim.fn.getcwd() or arglead
        local incomplete = nil ---@type string|nil
        if not vim.uv.fs_stat(basedir) then
          basedir = vim.fn.fnamemodify(basedir, ':h')
          incomplete = vim.fn.fnamemodify(arglead, ':t')
        end
        local subdirs = {}
        for name, type in vim.fs.dir(basedir) do
          if type == 'directory' and name ~= '.' and name ~= '..' then
            table.insert(
              subdirs,
              vim.fn.fnamemodify(
                vim.fn.resolve(vim.fs.joinpath(basedir, name)),
                ':p:~:.'
              )
            )
          end
        end
        if incomplete then
          return vim.tbl_filter(function(s)
            return s:find(incomplete, 1, true)
          end, subdirs)
        end
        return subdirs
      end,
    },
    remove_workspace_folder = {
      arg_handler = subcommand_arg_handler.item,
      completion = function(_, _, _)
        return vim.tbl_map(function(path)
          local short = vim.fn.fnamemodify(path, ':p:~:.')
          return short ~= '' and short or './'
        end, vim.lsp.buf.list_workspace_folders())
      end,
    },
    execute_command = {
      arg_handler = subcommand_arg_handler.item,
    },
    type_definition = {
      opts = {
        'reuse_win',
        ['on_list'] = subcommand_opt_vals.bool,
      },
    },
    declaration = {
      opts = {
        'reuse_win',
        ['on_list'] = subcommand_opt_vals.bool,
      },
    },
    definition = {
      opts = {
        'reuse_win',
        ['on_list'] = subcommand_opt_vals.bool,
      },
    },
    document_symbol = {
      opts = {
        ['on_list'] = subcommand_opt_vals.bool,
      },
    },
    implementation = {
      opts = {
        ['on_list'] = subcommand_opt_vals.bool,
      },
    },
    hover = {},
    document_highlight = {},
    clear_references = {},
    list_workspace_folders = {
      fn_override = function()
        vim.print(vim.lsp.buf.list_workspace_folders())
      end,
    },
    incoming_calls = {},
    outgoing_calls = {},
    signature_help = {},
    codelens_clear = {
      fn_override = function(args)
        vim.lsp.codelens.clear(args.client_id, args.bufnr)
      end,
      opts = {
        ['client_id'] = subcommand_opt_vals.lsp_clients,
        ['bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    codelens_display = {
      fn_override = function(args)
        vim.lsp.codelens.display(args.lenses, args.bufnr, args.client_id)
      end,
      opts = {
        ['client_id'] = subcommand_opt_vals.lsp_clients,
        ['bufnr'] = subcommand_opt_vals.bufs,
        'lenses',
      },
    },
    codelens_get = {
      fn_override = function(args)
        vim.lsp.codelens.get(args[1])
      end,
      completion = subcommand_completions.bufs,
    },
    codelens_on_codelens = {
      fn_override = function(args)
        vim.lsp.codelens.on_codelens(args.err, args.result, args.ctx)
      end,
      opts = { 'err', 'result', 'ctx' },
    },
    codelens_refresh = {
      fn_override = function(args)
        vim.lsp.codelens.refresh(args.opts)
      end,
      opts = {
        'opts',
        ['opts.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    codelens_run = {
      fn_override = vim.lsp.codelens.run,
    },
    codelens_save = {
      fn_override = function(args)
        vim.lsp.codelens.save(args.lenses, args.bufnr, args.client_id)
      end,
      opts = {
        'lenses',
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['client_id'] = subcommand_opt_vals.lsp_clients,
      },
    },
    inlay_hint_enable = {
      fn_override = function(args)
        vim.lsp.inlay_hint.enable(true, args.filter)
      end,
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    inlay_hint_disable = {
      fn_override = function(args)
        vim.lsp.inlay_hint.enable(false, args.filter)
      end,
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    inlay_hint_toggle = {
      fn_override = function(args)
        vim.lsp.inlay_hint.enable(
          not vim.lsp.inlay_hint.is_enabled(args.filter),
          args.filter
        )
      end,
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    inlay_hint_get = {
      fn_override = function(args)
        vim.print(vim.lsp.inlay_hint.get(args.filter))
      end,
      opts = {
        'filter',
        'filter.range',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    inlay_hint_is_enabled = {
      fn_override = function(args)
        vim.print(vim.lsp.inlay_hint.is_enabled(args.filter))
      end,
      opts = {
        'filter',
        ['filter.bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    semantic_tokens_force_refresh = {
      fn_override = function(args)
        vim.lsp.semantic_tokens.force_refresh(args[1])
      end,
      completion = subcommand_completions.bufs,
    },
    semantic_tokens_get_at_pos = {
      fn_override = function(args)
        vim.print(
          vim.lsp.semantic_tokens.get_at_pos(
            args.bufnr or 0,
            args.row,
            args.col
          )
        )
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        'row',
        'col',
      },
    },
    semantic_tokens_highlight_token = {
      fn_override = function(args)
        vim.lsp.semantic_tokens.highlight_token(
          args.token,
          args.bufnr or 0,
          args.client_id,
          args.hl_group,
          args.opts
        )
      end,
      opts = {
        'token',
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['client_id'] = subcommand_opt_vals.lsp_clients,
        ['hl_group'] = function()
          return vim.fn.getcompletion(':hi ', 'cmdline')
        end,
        'opts',
        'opts.priority',
      },
    },
    semantic_tokens_start = {
      fn_override = function(args)
        vim.lsp.semantic_tokens.start(
          args.bufnr or 0,
          args.client_id,
          args.opts
        )
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['client_id'] = subcommand_opt_vals.lsp_clients,
        'opts',
        'opts.debounce',
      },
    },
    semantic_tokens_stop = {
      fn_override = function(args)
        vim.lsp.semantic_tokens.stop(args.bufnr or 0, args.client_id)
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['client_id'] = subcommand_opt_vals.lsp_clients,
      },
    },
  },

  ---Diagnostic subcommands
  ---@type table<string, subcommand_info_t>
  diagnostic = {
    config = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.opts, args.namespace
      end,
      opts = {
        'namespace',
        'opts.virtual_text.source',
        'opts.virtual_text.spacing',
        'opts.virtual_text.prefix',
        'opts.virtual_text.suffix',
        'opts.virtual_text.format',
        'opts.signs.priority',
        'opts.signs.text',
        'opts.signs.text.ERROR',
        'opts.signs.text.WARN',
        'opts.signs.text.INFO',
        'opts.signs.text.HINT',
        'opts.signs.numhl',
        'opts.signs.numhl.ERROR',
        'opts.signs.numhl.WARN',
        'opts.signs.numhl.INFO',
        'opts.signs.numhl.HINT',
        'opts.signs.linehl',
        'opts.signs.linehl.ERROR',
        'opts.signs.linehl.WARN',
        'opts.signs.linehl.INFO',
        'opts.signs.linehl.HINT',
        'opts.float',
        'opts.float.namespace',
        'opts.float.scope',
        'opts.float.pos',
        'opts.float.severity_sort',
        'opts.float.header',
        'opts.float.source',
        'opts.float.format',
        'opts.float.prefix',
        'opts.float.suffix',
        'float.focus_id',
        'float.border',
        'opts.severity_sort',
        ['opts.underline'] = subcommand_opt_vals.bool,
        ['opts.underline.severity'] = subcommand_opt_vals.severity,
        ['opts.virtual_text'] = subcommand_opt_vals.bool,
        ['opts.virtual_text.severity'] = subcommand_opt_vals.severity,
        ['opts.signs'] = subcommand_opt_vals.bool,
        ['opts.signs.severity'] = subcommand_opt_vals.severity,
        ['opts.float.bufnr'] = subcommand_opt_vals.bufs,
        ['opts.float.severity'] = subcommand_opt_vals.severity,
        ['opts.update_in_insert'] = subcommand_opt_vals.bool,
        ['opts.severity_sort.reverse'] = subcommand_opt_vals.bool,
      },
    },
    disable = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.bufnr, args.namespace
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        'namespace',
      },
      fn_override = function(bufnr, namespace)
        vim.diagnostic.enable(false, { bufnr = bufnr, ns_id = namespace })
      end,
    },
    enable = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.bufnr, args.namespace
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        'namespace',
      },
    },
    fromqflist = {
      arg_handler = subcommand_arg_handler.item,
      opts = { 'list' },
      fn_override = function(...)
        vim.diagnostic.show(nil, 0, vim.diagnostic.fromqflist(...))
      end,
    },
    get = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.bufnr, args.opts
      end,
      opts = {
        ['bufnr'] = subcommand_opt_vals.bufs,
        'opts.namespace',
        'opts.lnum',
        ['opts.severity'] = subcommand_opt_vals.severity,
      },
      fn_override = function(...)
        vim.print(vim.diagnostic.get(...))
      end,
    },
    get_namespace = {
      arg_handler = subcommand_arg_handler.item,
      opts = { 'namespace' },
      fn_override = function(...)
        vim.print(vim.diagnostic.get_namespace(...))
      end,
    },
    get_namespaces = {
      fn_override = function()
        vim.print(vim.diagnostic.get_namespaces())
      end,
    },
    get_next = {
      opts = {
        'wrap',
        'winid',
        'namespace',
        'pos',
        'float.namespace',
        'float.scope',
        'float.pos',
        'float.header',
        'float.source',
        'float.format',
        'float.prefix',
        'float.suffix',
        'float.focus_id',
        'float.border',
        'float.severity_sort',
        ['severity'] = subcommand_opt_vals.severity,
        ['float'] = subcommand_opt_vals.bool,
        ['float.bufnr'] = subcommand_opt_vals.bufs,
        ['float.severity'] = subcommand_opt_vals.severity,
      },
      fn_override = function(...)
        vim.print(vim.diagnostic.get_next(...))
      end,
    },
    get_prev = {
      opts = {
        'wrap',
        'winid',
        'namespace',
        'pos',
        'float.namespace',
        'float.scope',
        'float.pos',
        'float.header',
        'float.source',
        'float.format',
        'float.prefix',
        'float.suffix',
        'float.focus_id',
        'float.border',
        'float.severity_sort',
        ['severity'] = subcommand_opt_vals.severity,
        ['float'] = subcommand_opt_vals.bool,
        ['float.bufnr'] = subcommand_opt_vals.bufs,
        ['float.severity'] = subcommand_opt_vals.severity,
      },
      fn_override = function(...)
        vim.print(vim.diagnostic.get_prev(...))
      end,
    },
    jump = {
      opts = {
        'wrap',
        'winid',
        'namespace',
        'pos',
        'float.namespace',
        'float.scope',
        'float.pos',
        'float.header',
        'float.source',
        'float.format',
        'float.prefix',
        'float.suffix',
        'float.focus_id',
        'float.border',
        'float.severity_sort',
        ['severity'] = subcommand_opt_vals.severity,
        ['float'] = subcommand_opt_vals.bool,
        ['float.bufnr'] = subcommand_opt_vals.bufs,
        ['float.severity'] = subcommand_opt_vals.severity,
      },
    },
    hide = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.namespace, args.bufnr
      end,
      opts = {
        'namespace',
        ['bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    is_enabled = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.bufnr, args.namespace
      end,
      opts = {
        'namespace',
        ['bufnr'] = subcommand_opt_vals.bufs,
      },
      fn_override = function(...)
        vim.print(vim.diagnostic.is_enabled(...))
      end,
    },
    match = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.str,
          args.pat,
          args.groups,
          args.severity_map,
          args.defaults
      end,
      opts = {
        'str',
        'pat',
        'groups',
        'severity_map',
        'defaults',
      },
      fn_override = function(...)
        vim.print(vim.diagnostic.match(...))
      end,
    },
    open_float = {
      opts = {
        'pos',
        'scope',
        'header',
        'format',
        'prefix',
        'suffix',
        'namespace',
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['source'] = subcommand_opt_vals.bool,
        ['severity'] = subcommand_opt_vals.severity,
        ['severity_sort'] = subcommand_opt_vals.bool,
      },
    },
    reset = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.namespace, args.bufnr
      end,
      opts = {
        'namespace',
        ['bufnr'] = subcommand_opt_vals.bufs,
      },
    },
    set = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.namespace, args.bufnr, args.diagnostics, args.opts
      end,
      opts = {
        'namespace',
        'diagnostics',
        'opts.virtual_text.source',
        'opts.virtual_text.spacing',
        'opts.virtual_text.prefix',
        'opts.virtual_text.suffix',
        'opts.virtual_text.format',
        'opts.signs.priority',
        'opts.float',
        'opts.float.namespace',
        'opts.float.scope',
        'opts.float.pos',
        'opts.float.severity_sort',
        'opts.float.header',
        'opts.float.source',
        'opts.float.format',
        'opts.float.prefix',
        'opts.float.suffix',
        'opts.float.focus_id',
        'opts.float.border',
        'opts.severity_sort',
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['opts.signs'] = subcommand_opt_vals.bool,
        ['opts.signs.severity'] = subcommand_opt_vals.severity,
        ['opts.underline'] = subcommand_opt_vals.bool,
        ['opts.underline.severity'] = subcommand_opt_vals.severity,
        ['opts.virtual_text'] = subcommand_opt_vals.bool,
        ['opts.virtual_text.severity'] = subcommand_opt_vals.severity,
        ['opts.float.bufnr'] = subcommand_opt_vals.bufs,
        ['opts.float.severity'] = subcommand_opt_vals.severity,
        ['opts.update_in_insert'] = subcommand_opt_vals.bool,
        ['opts.severity_sort.reverse'] = subcommand_opt_vals.bool,
      },
    },
    setloclist = {
      opts = {
        'namespace',
        'winnr',
        'open',
        'title',
        ['severity'] = subcommand_opt_vals.severity,
      },
    },
    setqflist = {
      opts = {
        'namespace',
        'open',
        'title',
        ['severity'] = subcommand_opt_vals.severity,
      },
    },
    show = {
      ---@param args lsp_command_parsed_arg_t
      arg_handler = function(args)
        return args.namespace, args.bufnr, args.diagnostics, args.opts
      end,
      opts = {
        'namespace',
        'diagnostics',
        'opts.virtual_text.source',
        'opts.virtual_text.spacing',
        'opts.virtual_text.prefix',
        'opts.virtual_text.suffix',
        'opts.virtual_text.format',
        'opts.signs.priority',
        'opts.float',
        'opts.float.namespace',
        'opts.float.scope',
        'opts.float.pos',
        'opts.float.severity_sort',
        'opts.float.header',
        'opts.float.source',
        'opts.float.format',
        'opts.float.prefix',
        'opts.float.suffix',
        'opts.float.focus_id',
        'opts.float.border',
        'opts.severity_sort',
        ['bufnr'] = subcommand_opt_vals.bufs,
        ['opts.signs'] = subcommand_opt_vals.bool,
        ['opts.signs.severity'] = subcommand_opt_vals.severity,
        ['opts.underline'] = subcommand_opt_vals.bool,
        ['opts.underline.severity'] = subcommand_opt_vals.severity,
        ['opts.virtual_text'] = subcommand_opt_vals.bool,
        ['opts.virtual_text.severity'] = subcommand_opt_vals.severity,
        ['opts.float.bufnr'] = subcommand_opt_vals.bufs,
        ['opts.float.severity'] = subcommand_opt_vals.severity,
        ['opts.update_in_insert'] = subcommand_opt_vals.bool,
        ['opts.severity_sort.reverse'] = subcommand_opt_vals.bool,
      },
    },
    toqflist = {
      arg_handler = subcommand_arg_handler.item,
      opts = { 'diagnostics' },
      fn_override = function(...)
        vim.fn.setqflist(vim.diagnostic.toqflist(...))
      end,
    },
  },
}

---Get meta command function
---@param subcommand_info_list subcommand_info_t[] subcommands information
---@param fn_scope table|fun(name: string): function scope of corresponding functions for subcommands
---@param fn_name_alt string|nil name of the function to call given no subcommand
---@return function meta_command_fn
local function command_meta(subcommand_info_list, fn_scope, fn_name_alt)
  ---Meta command function, calls the appropriate subcommand with args
  ---@param tbl table information passed to the command
  return function(tbl)
    local fn_name, cmdline_args = parse_cmdline_args(tbl.fargs, fn_name_alt)
    if not fn_name then
      return
    end
    local fn = subcommand_info_list[fn_name]
        and subcommand_info_list[fn_name].fn_override
      or type(fn_scope) == 'table' and fn_scope[fn_name]
      or type(fn_scope) == 'function' and fn_scope(fn_name)
    if type(fn) ~= 'function' then
      return
    end
    local arg_handler = subcommand_info_list[fn_name].arg_handler
      or function(...)
        return ...
      end
    fn(arg_handler(cmdline_args, tbl))
  end
end

---Get command completion function
---@param meta string meta command name
---@param subcommand_info_list subcommand_info_t[] subcommands information
---@return function completion_fn
local function command_complete(meta, subcommand_info_list)
  ---Command completion function
  ---@param arglead string leading portion of the argument being completed
  ---@param cmdline string entire command line
  ---@param cursorpos number cursor position in it (byte index)
  ---@return string[] completion completion results
  return function(arglead, cmdline, cursorpos)
    -- If subcommand is not specified, complete with subcommands
    if cmdline:sub(1, cursorpos):match('^%A*' .. meta .. '%s+%S*$') then
      return vim.tbl_filter(
        function(cmd)
          return cmd:find(arglead, 1, true) == 1
        end,
        vim.tbl_filter(function(key)
          local info = subcommand_info_list[key] ---@type subcommand_info_t|table|nil
          return info
              and (info.arg_handler or info.params or info.opts or info.fn_override or info.completion)
              and true
            or false
        end, vim.tbl_keys(subcommand_info_list))
      )
    end
    -- If subcommand is specified, complete with its options or params
    local subcommand = utils.str.camel_to_snake(
      cmdline:match('^%s*' .. meta .. '(%w+)')
    ) or cmdline:match('^%s*' .. meta .. '%s+(%S+)')
    if not subcommand_info_list[subcommand] then
      return {}
    end
    -- Use subcommand's custom completion function if it exists
    if subcommand_info_list[subcommand].completion then
      return subcommand_info_list[subcommand].completion(
        arglead,
        cmdline,
        cursorpos
      )
    end
    -- Complete with subcommand's options or params
    local subcommand_info = subcommand_info_list[subcommand]
    if subcommand_info then
      return utils.cmd.complete(subcommand_info.params, subcommand_info.opts)(
        arglead,
        cmdline,
        cursorpos
      )
    end
    return {}
  end
end

---Setup commands
---@param meta string meta command name
---@param subcommand_info_list table<string, subcommand_info_t> subcommands information
---@param fn_scope table|fun(name: string): function scope of corresponding functions for subcommands
---@return nil
local function setup_commands(meta, subcommand_info_list, fn_scope)
  -- metacommand -> MetaCommand abbreviation
  utils.key.command_abbrev(meta:lower(), meta)
  -- Format: MetaCommand sub_command opts ...
  vim.api.nvim_create_user_command(
    meta,
    command_meta(subcommand_info_list, fn_scope),
    {
      bang = true,
      range = true,
      nargs = '*',
      complete = command_complete(meta, subcommand_info_list),
    }
  )
  -- Format: MetaCommandSubcommand opts ...
  for subcommand, _ in pairs(subcommand_info_list) do
    vim.api.nvim_create_user_command(
      meta .. utils.str.snake_to_camel(subcommand),
      command_meta(subcommand_info_list, fn_scope, subcommand),
      {
        bang = true,
        range = true,
        nargs = '*',
        complete = command_complete(meta, subcommand_info_list),
      }
    )
  end
end

---@return nil
local function setup_lsp_autoformat()
  vim.g.lsp_autofmt_opts = { async = true, timeout_ms = 500 }

  -- Automatically format code on buf save and insert leave
  vim.api.nvim_create_autocmd('BufWritePre', {
    desc = 'LSP auto format.',
    group = vim.api.nvim_create_augroup('LspAutoFmt', {}),
    callback = function(info)
      local b = vim.b[info.buf]
      local g = vim.g
      if
        b.lsp_autofmt_enabled
        or (b.lsp_autofmt_enabled == nil and g.lsp_autofmt_enabled)
      then
        vim.lsp.buf.format(b.lsp_autofmt_opts or g.lsp_autofmt_opts)
      end
    end,
  })
end

local lsp_autostop_pending
---Automatically stop LSP servers that no longer attach to any buffers
---
---  Once `LspDetach` is triggered, wait for 60s before checking and
---  stopping servers, in this way the callback will be invoked once
---  every 60 seconds at most and can stop multiple clients at once
---  if possible, which is more efficient than checking and stopping
---  clients on every `LspDetach` events
---
---@return nil
local function setup_lsp_stopdetached()
  vim.api.nvim_create_autocmd('LspDetach', {
    group = vim.api.nvim_create_augroup('LspAutoStop', {}),
    desc = 'Automatically stop detached language servers.',
    callback = function()
      if lsp_autostop_pending then
        return
      end
      lsp_autostop_pending = true
      vim.defer_fn(function()
        lsp_autostop_pending = nil
        for _, client in ipairs(vim.lsp.get_clients()) do
          if vim.tbl_isempty(client.attached_buffers) then
            utils.lsp.soft_stop(client)
          end
        end
      end, 60000)
    end,
  })
end

---Set up diagnostic signs and virtual text
---@return nil
local function setup_diagnostic_configs()
  local icons = utils.static.icons
  vim.diagnostic.config({
    severity_sort = true,
    jump = {
      float = true,
    },
    virtual_text = {
      spacing = 4,
      prefix = vim.trim(utils.static.icons.AngleLeft),
    },
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = icons.DiagnosticSignError,
        [vim.diagnostic.severity.WARN] = icons.DiagnosticSignWarn,
        [vim.diagnostic.severity.INFO] = icons.DiagnosticSignInfo,
        [vim.diagnostic.severity.HINT] = icons.DiagnosticSignHint,
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = 'DiagnosticSignError',
        [vim.diagnostic.severity.WARN] = 'DiagnosticSignWarn',
        [vim.diagnostic.severity.INFO] = 'DiagnosticSignInfo',
        [vim.diagnostic.severity.HINT] = 'DiagnosticSignHint',
      },
    },
  })
end

---Setup diagnostic handlers overrides
local function setup_diagnostic_overrides()
  ---Filter out diagnostics that overlap with diagnostics from other sources
  ---For each diagnostic, checks if there exists another diagnostic from a different
  ---namespace that has the same start line and column
  ---
  ---If multiple diagnostics overlap, prefer the one with higher severity
  ---
  ---This helps reduce redundant diagnostics when multiple language servers
  ---(usually a language server and a linter hooked to an lsp wrapper) report
  ---the same issue for the same range
  ---@param diags vim.Diagnostic[]
  ---@return vim.Diagnostic[]
  local function filter_overlapped(diags)
    ---Diagnostics cache, indexed by buffer number and line number (0-indexed)
    ---to avoid calling `vim.diagnostic.get()` for the same buffer and line
    ---repeatedly
    ---@type table<integer, table<integer, table<integer, vim.Diagnostic>>>
    local diags_cache = vim.defaulttable(function(bufnr)
      local ds = vim.defaulttable() -- mapping from lnum to diagnostics
      -- Avoid using another layer of default table index by lnum using
      -- `vim.diagnostic.get(bufnr, { lnum = lnum })` to get diagnostics
      -- by line number since it requires traversing all diagnostics in
      -- the buffer each time
      for _, d in ipairs(vim.diagnostic.get(bufnr)) do
        table.insert(ds[d.lnum], d)
      end
      return ds
    end)

    return vim
      .iter(diags)
      :filter(function(diag) ---@param diag diagnostic_t
        ---@class diagnostic_t: vim.Diagnostic
        ---@field _hidden boolean whether the diagnostic is shown as virtual text

        diag._hidden = vim
          .iter(diags_cache[diag.bufnr][diag.lnum])
          :any(function(d) ---@param d diagnostic_t
            return not d._hidden
              and d.namespace ~= diag.namespace
              and d.severity <= diag.severity
              and d.col == diag.col
          end)

        return not diag._hidden
      end)
      :totable()
  end

  ---Truncates multi-line diagnostic messages to their first line
  ---@param diags vim.Diagnostic[]
  ---@return vim.Diagnostic[]
  local function truncate_multiline(diags)
    return vim
      .iter(diags)
      :map(function(d) ---@param d vim.Diagnostic
        local first_line = vim.gsplit(d.message, '\n')()
        if not first_line or first_line == d.message then
          return d
        end
        return vim.tbl_extend('keep', {
          message = first_line,
        }, d)
      end)
      :totable()
  end

  vim.diagnostic.handlers.virtual_text.show = (function(cb)
    ---@param ns integer
    ---@param buf integer
    ---@param diags vim.Diagnostic[]
    ---@param opts vim.diagnostic.OptsResolved
    return function(ns, buf, diags, opts)
      return cb(ns, buf, truncate_multiline(filter_overlapped(diags)), opts)
    end
  end)(vim.diagnostic.handlers.virtual_text.show)
end

---Set up LSP and diagnostic
---@return nil
local function setup()
  if vim.g.loaded_lsp_plugin ~= nil then
    return
  end
  vim.g.loaded_lsp_plugin = true

  setup_lsp_overrides()
  setup_lsp_autoformat()
  setup_lsp_stopdetached()
  setup_diagnostic_overrides()
  setup_diagnostic_configs()
  setup_keymaps()
  setup_commands('Lsp', subcommands.lsp, function(name)
    return vim.lsp[name] or vim.lsp.buf[name]
  end)
  setup_commands('Diagnostic', subcommands.diagnostic, vim.diagnostic)
end

return { setup = setup }
