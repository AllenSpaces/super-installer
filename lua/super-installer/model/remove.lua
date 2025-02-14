local M = {}
local ui = require("super-installer.model.ui")

local function get_installed_plugins()
    local install_dir = vim.fn.stdpath("data") .. "/site/pack/super-installer/start/"
    return vim.split(vim.fn.glob(install_dir .. "/*"), "\n")
end

local function get_configured_plugins()
    local config = require("super-installer").config
    local plugins = {}
    
    for _, plugin in ipairs(config.install.use) do
        table.insert(plugins, plugin:gsub("/", "-"))
    end
    table.insert(plugins, config.install.default:gsub("/", "-"))
    
    return plugins
end

function M.run()
    local installed = get_installed_plugins()
    local configured = get_configured_plugins()
    local to_remove = {}
    local errors = {}

    -- 找出需要移除的插件
    for _, path in ipairs(installed) do
        local name = vim.fn.fnamemodify(path, ":t")
        if not vim.tbl_contains(configured, name) then
            table.insert(to_remove, {path = path, name = name})
        end
    end

    ui.show_remove_ui(#to_remove)

    for i, plugin in ipairs(to_remove) do
        ui.update_remove_ui(i, #to_remove, plugin.name)
        local result = os.execute(string.format("rm -rf %s", vim.fn.shellescape(plugin.path)))
        if result ~= 0 then
            table.insert(errors, {
                plugin = plugin.name,
                error = "Exit code: " .. tostring(result)
            })
        end
    end

    ui.close_remove_ui()

    if #errors > 0 then
        ui.show_result_ui(errors, "Removal Errors")
    end
end

return M