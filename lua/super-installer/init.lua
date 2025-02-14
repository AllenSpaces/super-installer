local M = {}

M.config = {}

M.setup = function(user_config)
    local default_config = {
        git = "ssh",
        install = {
            default = "wukuohao2003/super-installer",
            use = {}
        },
        keymaps = {
            install = "<leader>si",
            remove = "<leader>sr",
            update = "<leader>su",
        }
    }

    M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

    -- 创建用户命令
    vim.api.nvim_create_user_command("SuperInstall", function()
        require("super-installer.model.install").run()
    end, {})

    vim.api.nvim_create_user_command("SuperRemove", function()
        require("super-installer.model.remove").run()
    end, {})

    -- 设置快捷键映射
    local function map_keys()
        if M.config.keymaps.install then
            vim.keymap.set("n", M.config.keymaps.install, "<cmd>SuperInstall<CR>", { silent = true })
        end
        if M.config.keymaps.remove then
            vim.keymap.set("n", M.config.keymaps.remove, "<cmd>SuperRemove<CR>", { silent = true })
        end
    end

    map_keys()
end

return M