local ui = require('super-installer.model.ui')
local vim = vim

local function remove_plugin(plugin)
    local base_dir = vim.fn.stdpath('data') .. '/site/pack/plugins/start/'
    local plugin_dir = base_dir .. vim.fn.fnamemodify(plugin, ':t')
    local cmd = string.format('rm -rf %s', plugin_dir)

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
                err_msg = err_msg or string.format("Failed to remove %s, exit code: %d", plugin, exit_code)
            end
        end
    })

    while vim.fn.jobwait({ job_id }, 100)[1] == -1 do
        vim.cmd('redraw')
    end

    return success, err_msg
end

-- 检查并移除插件
local function remove_unused_plugins(config)
    local use_ssh = config.git == "ssh"
    local current_plugins = vim.fn.globpath(vim.fn.stdpath('data') .. '/site/pack/plugins/start/', '*', 0, 1)
    local all_config_plugins = { config.install.default }
    for _, plugin in ipairs(config.install.use) do
        table.insert(all_config_plugins, plugin)
    end
    local to_remove = {}

    for _, plugin_dir in ipairs(current_plugins) do
        local plugin = vim.fn.fnamemodify(plugin_dir, ':t')
        local found = false
        for _, config_plugin in ipairs(all_config_plugins) do
            if vim.fn.fnamemodify(config_plugin, ':t') == plugin then
                found = true
                break
            end
        end
        if not found then
            table.insert(to_remove, plugin)
        end
    end

    local errors = {}
    for _, plugin in ipairs(to_remove) do
        local success, err = remove_plugin(plugin)
        if not success then
            table.insert(errors, err)
        end
    end

    if #errors > 0 then
        ui.create_error_win(errors)
    end
end

return {
    remove_unused_plugins = remove_unused_plugins
}