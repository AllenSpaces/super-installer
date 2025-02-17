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
    local success_count = 0
    local progress_win = ui.create_window("Removing Plugins...", 4, 50)

    local function remove_next_plugin(index)
        if index > total then
            ui.update_progress(progress_win, "Removing: Completed", total, total)

            vim.api.nvim_win_close(progress_win.win_id, true)

            ui.show_results(errors, success_count, total, "Removal")
            return
        end
        local plugin = to_remove[index]
        ui.update_progress(progress_win, "Removing: " .. plugin, index - 1, total)
        M.remove_plugin(plugin, function(ok, err)
            if ok then
                success_count = success_count + 1
            else
                table.insert(errors, {plugin = plugin, error = err})
            end
            remove_next_plugin(index + 1)
        end)
    end

    remove_next_plugin(1)
end

function M.remove_plugin(plugin_name, callback)
    local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin_name

    if vim.fn.isdirectory(install_dir) ~= 1 then
        callback(true)
        return
    end

    local cmd = string.format("rm -rf %s", install_dir)
    vim.fn.jobstart(cmd, {
        on_exit = function(_, exit_code)
            if exit_code == 0 then
                callback(true)
            else
                local result = vim.fn.system(cmd .. " 2>&1")
                local error_msg = result:gsub("\n", " "):sub(1, 50) .. "..."
                callback(false, error_msg)
            end
        end
    })
end

return M