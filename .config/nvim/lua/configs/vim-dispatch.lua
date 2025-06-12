local handlers = vim.g.dispatch_handlers
local job_handler ---@type string?

for i, handler in ipairs(handlers) do
  if handler == 'job' then
    job_handler = table.remove(handlers, i)
    break
  end
end

-- Prefer job handler over other handlers, e.g. tmux
if job_handler then
  table.insert(handlers, 1, job_handler)
end

vim.g.dispatch_handlers = handlers
