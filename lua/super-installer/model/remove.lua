local ui = require("super-installer.model.ui")

local M = {}

function M.start(config)
    local used_plugins = {}
    for _, plugin in ipairs(config.install.use) do
        used_plugins[plugin] = true
    end

    local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start/"
    local installed_plugins = vim.split(vim.fn.glob(install_dir .. "/*"), "\n")
    local to_remove = {}

    for _, path in ipairs(installed_plugins) do
        local plugin_name = vim.fn.fnamemodify(path, ":t")
        if not used_plugins[plugin_name] then
            table.insert(to_remove, plugin_name)
        end
    end

    local total = #to_remove
    local errors = {}
    local success_count = 0  -- 声明并初始化成功卸载数量

    local win = ui.create_window("Removing Plugins...", 4, 50)

    for i, plugin in ipairs(to_remove) do
        ui.update_progress(win, "Removing: " .. plugin, i, total)
        local ok, err = M.remove_plugin(plugin)
        if ok then
            success_count = success_count + 1
        else
            table.insert(errors, {plugin = plugin, error = err})
        end
    end
    -- 确保最后显示 100% 进度
    ui.update_progress(win, "Removing: Completed", total, total)

    vim.api.nvim_win_close(win.win_id, true)
    ui.show_results(errors, success_count, total, "Removal")
end

function M.remove_plugin(plugin_name)
    local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin_name

    if vim.fn.isdirectory(install_dir) ~= 1 then
        return true
    end

    local cmd = string.format("rm -rf %s 2>&1", install_dir)
    local result = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
        return false, result:gsub("\n", " "):sub(1, 50) .. "..."
    end

    return true
end

return M