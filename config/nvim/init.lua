-- ~/.config/nvim/init.lua — configuración mínima sin plugins.
vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.relativenumber = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.undofile = true
o.signcolumn = "yes"
o.scrolloff = 5
o.clipboard = "unnamedplus"
o.splitright = true
o.splitbelow = true
o.updatetime = 250

vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Guardar" })
vim.keymap.set("n", "<leader>q", "<cmd>quit<cr>", { desc = "Salir" })
vim.keymap.set("n", "<esc>", "<cmd>nohlsearch<cr>")

-- Resalta el texto copiado
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.highlight.on_yank() end,
})
