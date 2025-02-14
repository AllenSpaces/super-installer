local M = {}

M.setup = function(config)
    local super_config = {
        -- 安装插件的方式
        git = "ssh",

        -- default 为默认安装的插件
        install = {
            default = "wukuohao2003/super-installergit.git",

            -- 安装的插件 格式为 {username}/{repo}，例如 "wukuohao2003/super-installer"，
            use = {}
        },

        -- 快捷键绑定
        keymaps = {
            -- 安装插件快捷键
            install = "<leader>si",

            -- 移除未定义的插件
            remove = "<leader>sr",

            -- 更新插件
            update = "<leader>su",
        }
    }

    -- 合并默认配置和用户配置
    super_config = vim.tbl_deep_extend("force", super_config, config or {})

    local installer = require('super-installer.model.install')
    local remover = require('super-installer.model.remove')

    -- 定义 SuperInstall 命令
    vim.api.nvim_create_user_command('SuperInstall', function()
        installer.install_plugins(super_config)
    end, {})

    -- 定义 SuperRemove 命令
    vim.api.nvim_create_user_command('SuperRemove', function()
        remover.remove_unused_plugins(super_config)
    end, {})

    -- 设置快捷键
    vim.keymap.set('n', super_config.keymaps.install, '<Cmd>SuperInstall<CR>', { noremap = true, silent = true })
    vim.keymap.set('n', super_config.keymaps.remove, '<Cmd>SuperRemove<CR>', { noremap = true, silent = true })

end

return {
    setup = M.setup,
}