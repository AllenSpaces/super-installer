local M = {}

function M.execute_command(cmd, callback)
    local stdout_chunks = {}
    local stderr_chunks = {}

    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                table.insert(stdout_chunks, line)
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                table.insert(stderr_chunks, line)
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code == 0 then
				local success_msg = table.concat(stdout_chunks, "\n")
                callback(true, success_msg:gsub("\n", " "))
            else
                local error_msg = table.concat(stderr_chunks, "\n")
                if #error_msg == 0 then
                    error_msg = "Unknown error occurred"
                else
                    error_msg = error_msg:gsub("\n", " "):sub(1, 50) .. "..."
                end
                callback(false, error_msg)
            end
        end
    })

	return job_id
end

function M.get_install_dir(plugin, type)
    if vim.fn.has('win32') == 1 then
		if type == "remove" then
			return vim.fn.expand("$env:LOCALAPPDATA") .. "\\nvim-data\\site\\pack\\packer\\start\\" .. plugin
		else
			return vim.fn.expand("$env:LOCALAPPDATA") .. "\\nvim-data\\site\\pack\\packer\\start\\" .. plugin:match("/([^/]+)$")
		end
        
    else
		if type == "remove" then
			return vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin
		else
			return vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. plugin:match("/([^/]+)$")
		end
    end
end

function M.get_repo_url(plugin, git_type)
	if git_type == "ssh" then
		return string.format("git@github.com:%s.git", plugin)
	else
		return string.format("https://github.com/%s.git", plugin)
	end
end

function M.table_duplicates(tb)
    local seen = {}

    local result = {}

    for _, value in ipairs(tb) do
        if not seen[value] then
            seen[value] = true
            table.insert(result, value)
        end
    end

    return result
end

return M
