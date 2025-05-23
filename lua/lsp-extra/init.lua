local M = {}

--- @class lsp_extra.HoverOpts : vim.lsp.buf.hover.Opts

--- @class lsp_extra.SignatureHelpOpts : vim.lsp.buf.signature_help.Opts

--- @class lsp_extra.CompletionOpts : vim.lsp.completion.BufferOpts
--- @field trigger_on_all_characters? boolean

--- @class lsp_extra.DiagnosticsOpts : vim.diagnostic.Opts

--- @class lsp_extra.Keymaps
--- @field definition? string
--- @field type_definition? string
--- @field references? string
--- @field implementations? string
--- @field document_symbols? string
--- @field workspace_symbols? string
--- @field code_action? string
--- @field rename? string
--- @field completion? string
--- @field diagnostics? string
--- @field diagnostics_float? string
--- @field signature_help? string
--- @field hover? string

--- @class lsp_extra.Opts
--- @field auto_enable? boolean
--- @field auto_enable_ignore? string[]
--- @field completion? lsp_extra.CompletionOpts
--- @field hover? lsp_extra.HoverOpts
--- @field signature_help? lsp_extra.SignatureHelpOpts
--- @field diagnostics? lsp_extra.DiagnosticsOpts
--- @field disable_semantic_tokens? boolean
--- @field remove_default_keymaps? boolean
--- @field keymaps? lsp_extra.Keymaps
--- @field on_attach? fun(client: vim.lsp.Client, bufnr: integer)

--- Automatically load language servers in the lsp config directory.
--- @param opts lsp_extra.Opts
local function setup_language_servers(opts)
  if not opts.auto_enable then
    return
  end

  local lsp_dir = vim.fn.stdpath("config") .. "/lsp"
  local lsp_files = vim.fn.readdir(lsp_dir) --- @type string[]

  for _, file in ipairs(lsp_files) do
    local name = file:gsub("%.lua$", "")
    local enabled = not opts.auto_enable_ignore or not vim.tbl_contains(opts.auto_enable_ignore, name)
    vim.lsp.enable(name, enabled)
  end
end

--- Set keymap.
--- @param mode string|string[]
--- @param keymap? string
--- @param bufnr? integer
--- @param desc string
local function set_keymap(mode, keymap, fn, bufnr, desc, remap)
  if keymap then
    vim.keymap.set(mode, keymap, fn, { buffer = bufnr, desc = desc, remap = remap })
  end
end

--- Delete keymap.
--- @param mode string|string[]
--- @param keymap string
--- @param bufnr? integer
local function del_keymap(mode, keymap, bufnr)
  vim.keymap.del(mode, keymap, { buffer = bufnr })
end

--- Remove the default LSP keymaps.
--- If [bufnr] is given then it removes only the buffer specific ones.
--- See |lsp-defaults-disable|
--- @param opts lsp_extra.Opts
local function remove_default_keymaps(opts, bufnr)
  if opts.remove_default_keymaps then
    if bufnr then
      pcall(del_keymap, "n", "K", bufnr)
    else
      pcall(del_keymap, "n", "grn")
      pcall(del_keymap, { "n", "x" }, "gra")
      pcall(del_keymap, "n", "grr")
      pcall(del_keymap, "n", "gri")
      pcall(del_keymap, "n", "gO")
      pcall(del_keymap, "i", "<c-s>")
    end
  end
end

--- Set LSP keymaps for the given buffer.
--- @param opts lsp_extra.Opts
--- @param bufnr integer
local function set_keymaps(opts, bufnr)
  local function hover()
    vim.lsp.buf.hover(opts.hover)
  end

  local function signature_help()
    vim.lsp.buf.signature_help(opts.signature_help)
  end

  local function workspace_symbols()
    vim.lsp.buf.workspace_symbol("")
  end

  local function completion()
    vim.lsp.completion.get()
  end

  local function diagnostics()
    vim.diagnostic.setqflist({ open = true })
  end

  if opts.keymaps then
    set_keymap("n", opts.keymaps.definition, vim.lsp.buf.definition, bufnr, "LSP definition")
    set_keymap("n", opts.keymaps.type_definition, vim.lsp.buf.type_definition, bufnr, "LSP type definition")
    set_keymap("n", opts.keymaps.references, vim.lsp.buf.references, bufnr, "LSP references")
    set_keymap("n", opts.keymaps.implementations, vim.lsp.buf.implementation, bufnr, "LSP implementations")
    set_keymap("n", opts.keymaps.document_symbols, vim.lsp.buf.document_symbol, bufnr, "LSP document symbols")
    set_keymap("n", opts.keymaps.workspace_symbols, workspace_symbols, bufnr, "LSP workspace symbols")
    set_keymap("n", opts.keymaps.code_action, vim.lsp.buf.code_action, bufnr, "LSP code action")
    set_keymap("n", opts.keymaps.rename, vim.lsp.buf.rename, bufnr, "LSP rename")
    set_keymap("i", opts.keymaps.completion, completion, bufnr, "LSP completion")
    set_keymap("i", opts.keymaps.signature_help, signature_help, bufnr, "LSP signature help")
    set_keymap("n", opts.keymaps.hover, hover, bufnr, "LSP hover", true)

    set_keymap("n", opts.keymaps.diagnostics, diagnostics, bufnr, "Diagnostics in open buffers")
    set_keymap("n", opts.keymaps.diagnostics_float, vim.diagnostic.open_float, bufnr, "Diagnostics for current line")
  end
end

--- Setup LSP on attach autocmd.
--- @param opts lsp_extra.Opts
local function setup_on_attach(opts)
  local group = vim.api.nvim_create_augroup("LspExtra", { clear = true })

  -- See |lsp-attach|
  local triggerCharacters = {}
  for i = 32, 126 do
    table.insert(triggerCharacters, string.char(i))
  end

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      if not client then
        return
      end

      if opts.completion and client:supports_method("textDocument/completion") then
        vim.lsp.completion.enable(true, client.id, args.buf, opts.completion)

        if opts.completion.trigger_on_all_characters then
          client.server_capabilities.completionProvider.triggerCharacters = triggerCharacters
        end
      end

      if opts.disable_semantic_tokens then
        client.server_capabilities.semanticTokensProvider = nil
      end

      remove_default_keymaps(opts, args.buf)
      set_keymaps(opts, args.buf)

      if opts.on_attach then
        opts.on_attach(client, args.buf)
      end
    end,
    group = group,
    desc = "LSP on attach",
  })
end

--- Setup diagnostics config.
--- @param opts lsp_extra.Opts
local function setup_diagnostics(opts)
  vim.diagnostic.config(opts.diagnostics)
end

--- @param opts? lsp_extra.Opts
function M.setup(opts)
  opts = opts or {}
  remove_default_keymaps(opts)
  setup_language_servers(opts)
  setup_diagnostics(opts)
  setup_on_attach(opts)
end

return M
