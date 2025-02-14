local M = {}
local ui = require("super-installer.model.ui")

local function get_install_path(plugin_name)
    return vim.fn.stdpath("data") .. "/site/pack/super-installer/start/" .. plugin_name:gsub("/", "-")
end

local function get_repo_url(plugin, config)
    if config.git == "ssh" then
        return "git@github.com:" .. plugin .. ".git"
    else
        return "https://github.com/" .. plugin .. ".git"
    end
end

function M.run()
    local config = require("super-installer").config
    local plugins = vim.deepcopy(config.install.use)
    table.insert(plugins, 1, config.install.default)

    local total = #plugins
    local current = 0
    local errors = {}

    ui.show_install_ui(total)

    for _, plugin in ipairs(plugins) do
        current = current + 1
        ui.update_install_ui(current, total, plugin)

        local install_path = get_install_path(plugin)
        local repo_url = get_repo_url(plugin, config)

        -- 检查是否已安装
        if vim.fn.isdirectory(install_path) == 0 then
            local cmd = string.format("git clone --depth 1 %s %s", repo_url, install_path)
            local result = os.execute(cmd)
            if result ~= 0 then
                table.insert(errors, {
                    plugin = plugin,
                    error = "Exit code: " .. tostring(result)
                })
            end
        end
    end

    ui.close_install_ui()

    if #errors > 0 then
        ui.show_result_ui(errors, "Installation Errors")
    end
end

return M