return {
  {
    -- Fix python indent
    -- Without this plugin:
    -- a = [|] -> press <Enter> ->
    -- a = [
    --         |
    --         ]
    -- With this plugin:
    -- a =  [
    --     |
    -- ]
    'Vimjas/vim-python-pep8-indent',
    ft = 'python',
  },
}
