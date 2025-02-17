local ui = require("super-installer.model.ui")

local M = {}

function M.start(config)
    local plugins = config.install.use
    if #plugins == 0 then return end

    local total = #plugins
    local errors = {}
    local success_count = 0
    local progress_win = ui.create_window("Installing Plugins...", 4, 50)

    local function install_next_plugin(index)
        if index > total then
            -- 所有插件安装完成，更新进度条到 100%
            ui.update_progress(progress_win, "Installing: Completed", total, total)
            -- 关闭进度窗口
            vim.api.nvim_win_close(progress_win.win_id, true)
            -- 打开结果窗口
            ui.show_results(errors, success_count, total, "Installation")
            return
        end
        local plugin = plugins[index]
        ui.update_progress(progress_win, "Installing: " .. plugin, index - 1, total)
        M.install_plugin(plugin, config.git, function(ok, err)
            if ok then
                success_count = success_count + 1
            else
                table.insert(errors, {plugin = plugin, error = err})
            end
            install_next_plugin(index + 1)
        end)
    end

    install_next_plugin(1)
end

function M.install_plugin(plugin, git_type, callback)
    local repo_url
    if git_type == "ssh" then
        repo_url = string.format("git@github.com:%s.git", plugin)
    else
        repo_url = string.format("https://github.com/%s.git", plugin)
    end

    local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin:match("/([^/]+)$")

    local cmd
    if vim.fn.isdirectory(install_dir) == 1 then
        cmd = string.format("cd %s && git pull", install_dir)
    else
        cmd = string.format("git clone --depth 1 %s %s", repo_url, install_dir)
    end

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