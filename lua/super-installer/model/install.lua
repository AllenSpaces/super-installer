local ui = require("super-installer.model.ui")

local M = {}

function M.start(config)
    local plugins = config.install.use
    if #plugins == 0 then return end

    local total = #plugins
    local errors = {}
    local success_count = 0
    local win = ui.create_window("Installing Plugins...", 4, 50)

    print("Window created with win_id: " .. win_id)

    for i, plugin in ipairs(plugins) do
        print("Updating progress for plugin: " .. plugin .. ", index: " .. i .. ", total: " .. total)
        ui.update_progress(win, "Installing: " .. plugin, i - 1, total)
        local ok, err = M.install_plugin(plugin, config.git)
        if ok then
            success_count = success_count + 1
        else
            table.insert(errors, {plugin = plugin, error = err})
        end
    end
    -- 确保最后显示 100% 进度
    ui.update_progress(win, "Installing: Completed", total, total)

    vim.api.nvim_win_close(win.win_id, true)
    ui.show_results(errors, success_count, total, "Installation")
end

function M.install_plugin(plugin, git_type)
    local repo_url
    if git_type == "ssh" then
        repo_url = string.format("git@github.com:%s.git", plugin)
    else
        repo_url = string.format("https://github.com/%s.git", plugin)
    end

    local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin:match("/([^/]+)$")

    if vim.fn.isdirectory(install_dir) == 1 then
        local pull_cmd = string.format("cd %s && git pull 2>&1", install_dir)
        local pull_result = vim.fn.system(pull_cmd)
        if vim.v.shell_error ~= 0 then
            return false, pull_result:gsub("\n", " "):sub(1, 50) .. "..."
        end
    else
        local clone_cmd = string.format("git clone --depth 1 %s %s 2>&1", repo_url, install_dir)
        local clone_result = vim.fn.system(clone_cmd)
        if vim.v.shell_error ~= 0 then
            return false, clone_result:gsub("\n", " "):sub(1, 50) .. "..."
        end
    end
    return true
end

return M