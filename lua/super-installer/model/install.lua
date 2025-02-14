local ui = require('super-installer.model.ui')
local vim = vim

local function download_plugin(plugin, use_ssh)
    local base_dir = vim.fn.stdpath('data') .. '/site/pack/packer/start'
    local repo_url
    if use_ssh then
        repo_url = 'git@github.com:' .. plugin .. '.git'
    else
        repo_url = 'https://github.com/' .. plugin .. '.git'
    end

    local cmd = string.format('git clone %s %s%s', repo_url, base_dir, vim.fn.fnamemodify(plugin, ':t'))

    ui.create_float_win()
    local success = false
    local err_msg = nil
    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                local progress = 0
                for _, line in ipairs(data) do
                    progress = math.min(progress + 0.1, 1)
                    ui.update_float_win(plugin, progress)
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                err_msg = table.concat(data, '\n')
            end
        end,
        on_exit = function(_, exit_code)
            ui.close_float_win()
            success = exit_code == 0
            if not success then
                err_msg = err_msg or string.format("Failed to install %s, exit code: %d", plugin, exit_code)
            end
        end
    })

    while vim.fn.jobwait({ job_id }, 100)[1] == -1 do
        vim.cmd('redraw')
    end

    return success, err_msg
end

local function install_plugins(config)
    local use_ssh = config.git == "ssh"
    local plugins = { config.install.default }
    for _, plugin in ipairs(config.install.use) do
        table.insert(plugins, plugin)
    end

    print(plugins)

    local errors = {}
    for _, plugin in ipairs(plugins) do
        local success, err = download_plugin(plugin, use_ssh)
        if not success then
            table.insert(errors, err)
        end
    end

    if #errors > 0 then
        ui.create_error_win(errors)
    end
end

return {
    install_plugins = install_plugins
}