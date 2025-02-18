local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

local is_installation_aborted = false

function M.start(config)

    is_installation_aborted = false

    local plugins = config.install.use or {}
    if config.install.default then
        table.insert(plugins, 1, config.install.default)
    end

    if #plugins == 0 then
        ui.log_message("No plugins to install.")
        return
    end

    local total = #plugins
    local errors = {}
    local success_count = 0
    local progress_win = ui.create_window("Installing Plugins", 65)


    vim.api.nvim_create_autocmd("WinClosed", {
        buffer = progress_win.buf,
        callback = function()
            is_installation_aborted = true
            ui.log_message("Plugin installation aborted by user.")
        end
    })

    local function install_next_plugin(index)

        if is_installation_aborted then
            return
        end

        if index > total then
            ui.update_progress(progress_win, "Installing: Completed", total, total)
            vim.api.nvim_win_close(progress_win.win_id, true)
            ui.show_results(errors, success_count, total, "Installation")
            return
        end

        local plugin = plugins[index]
        ui.update_progress(progress_win, "Installing: " .. plugin, index - 1, total)
        M.install_plugin(plugin, config.git, function(ok, err)
            if ok then
                success_count = success_count + 1
            else
                table.insert(errors, { plugin = plugin, error = err })
            end
            install_next_plugin(index + 1)
        end)
    end

    install_next_plugin(1)
end

function M.install_plugin(plugin, git_type, callback)

    if is_installation_aborted then
        return
    end

    local repo_url = utils.get_repo_url(plugin, git_type)
    local install_dir = utils.get_install_dir(plugin)

    local cmd
    if vim.fn.isdirectory(install_dir) == 1 then
        cmd = string.format("cd %s && git pull", install_dir)
    else
        cmd = string.format("git clone --depth 1 %s %s", repo_url, install_dir)
    end

    utils.execute_command(cmd, callback)
end

return M