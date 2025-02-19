local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

local is_update_aborted = false
local update_win = nil
local job_id = nil

local plugins_to_update = {}

function M.start(config)
    is_update_aborted = false
    plugins_to_update = {}

    local plugins = config.install.use or {}
    if config.install.default then
        table.insert(plugins, 1, config.install.default)
    end

    plugins = utils.table_duplicates(plugins)

    if #plugins == 0 then
        ui.log_message("No plugins to update.")
        return
    end

    local total = #plugins
    local errors = {}
    local success_count = 0
    local progress_win_check = ui.create_window("Checking Plugins", 65)

    vim.api.nvim_create_autocmd("WinClosed", {
        buffer = progress_win_check.buf,
        callback = function()
            if(job_id) then
                vim.fn.jobstop(job_id)
            end
            is_update_aborted = true
            ui.log_message("Plugin update aborted by user.")
        end,
    })

    local function update_next_plugin(index, win)
        if is_update_aborted then
            return
        end

        if index > #plugins_to_update then
            ui.update_progress(win, "Update: Completed", #plugins_to_update, #plugins_to_update, config.ui.progress.icon)
            vim.api.nvim_win_close(win.win_id, true)
            ui.show_results(errors, success_count, #plugins_to_update, "Updating")
            return
        end

        local plugin = plugins_to_update[index]
        ui.update_progress(win, "Updating: " .. plugin, index - 1, #plugins_to_update, config.ui.progress.icon)

        M.update_plugin(plugin, function(ok, err)
            if ok then
                success_count = success_count + 1
            else
                table.insert(errors, { plugin = plugin, error = err })
            end
            update_next_plugin(index + 1, win)
        end)
    end

    local function check_next_plugin(index)
        if is_update_aborted then
            return
        end

        if index > total then
            if #errors > 0 then
                ui.update_progress(
                    progress_win_check,
                    "Checking: Completed with errors",
                    total,
                    total,
                    config.ui.progress.icon
                )
                vim.api.nvim_win_close(progress_win_check.win_id, true)
                ui.show_results(errors, success_count, total, "Checking")
            else
                if #plugins_to_update == 0 then
                    ui.log_message("No plugins need to be updated.")
                    vim.api.nvim_win_close(progress_win_check.win_id, true)
                else
                    vim.notify(plugins_to_update)
                    vim.api.nvim_win_close(progress_win_check.win_id, true)
                    update_win = ui.create_window("Updating Plugins", 65)

                    vim.api.nvim_create_autocmd("WinClosed", {
                        buffer = update_win.buf,
                        callback = function()
                            is_update_aborted = true
                            ui.log_message("Plugin update aborted by user.")
                        end,
                    })

                    update_next_plugin(1, update_win)
                end
            end
            return
        end

        local plugin = plugins[index]
        ui.update_progress(progress_win_check, "Checking: " .. plugin, index - 1, total, config.ui.progress.icon)

        M.check_plugin(plugin, function(ok, result)
            if ok then
                if string.find(result, "up-to-date") then
                    table.insert(plugins_to_update, plugin)
                end
            else
                table.insert(errors, { plugin = plugin, error = result })
            end
            check_next_plugin(index + 1)
        end)
    end

    check_next_plugin(1)
end

function M.check_plugin(plugin, callback)
    if is_update_aborted then
        callback(false)
        return
    end

    local install_dir = utils.get_install_dir(plugin, "update")

    if vim.fn.isdirectory(install_dir) ~= 1 then
        callback(false)
        return
    end

    local fetch_cmd = string.format("cd %s && git fetch -v", install_dir)

    job_id = utils.execute_command(fetch_cmd, callback)
end

function M.update_plugin(plugin, callback)
    if is_update_aborted then
        callback(false, "Update aborted by user")
        return
    end

    local install_dir = utils.get_install_dir(plugin, "update")
    local cmd = string.format("cd %s && git pull", install_dir)

    job_id = utils.execute_command(cmd, callback)
end

return M