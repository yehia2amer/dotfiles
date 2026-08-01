local function tsgo_root_dir(bufnr, on_dir)
  local lockfiles = { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }
  local project_root = vim.fs.root(bufnr, lockfiles) or vim.fs.root(bufnr, { ".git" })
  local deno_root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc", "deno.lock" })

  if deno_root and (not project_root or #deno_root >= #project_root) then
    return
  end

  on_dir(project_root or vim.fn.getcwd())
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers.tsserver = { enabled = false }
      opts.servers.ts_ls = { enabled = false }
      opts.servers.vtsls = { enabled = false }
      opts.servers.tsgo = { mason = false }

      -- The pinned nvim-lspconfig predates its built-in tsgo definition.
      opts.setup.tsgo = function(_, server_opts)
        server_opts.mason = nil
        vim.lsp.config("tsgo", vim.tbl_deep_extend("force", {
          cmd = { "tsgo", "--lsp", "--stdio" },
          filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
          root_dir = tsgo_root_dir,
        }, server_opts))
        vim.lsp.enable("tsgo")
        return true
      end
    end,
  },
}
