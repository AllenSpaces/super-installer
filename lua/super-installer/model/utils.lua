local M = {}

function M.execute_command(cmd, callback)
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

function M.get_install_dir(plugin)
    return vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin:match("/([^/]+)$")
end

function M.get_repo_url(plugin, git_type)
    if git_type == "ssh" then
        return string.format("git@github.com:%s.git", plugin)
    else
        return string.format("https://github.com/%s.git", plugin)
    end
end

return M