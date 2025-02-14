local M = {
    config = {}
}

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

    -- 合并配置
    M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

    -- 创建用户命令
    vim.api.nvim_create_user_command("SuperInstall", function()
        require("super-installer.model.install").start(M.config)
    end, {})

    vim.api.nvim_create_user_command("SuperRemove", function()
        require("super-installer.model.remove").start(M.config)
    end, {})
end

return M