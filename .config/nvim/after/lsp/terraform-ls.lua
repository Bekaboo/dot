-- Terraform language server
-- https://github.com/hashicorp/terraform-ls

return {
  filetypes = { 'terraform', 'terraform-vars' },
  cmd = { 'terraform-ls', 'serve' },
  root_markers = { '.terraform' },
}
