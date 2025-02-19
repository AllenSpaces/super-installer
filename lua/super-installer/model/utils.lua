local M = {}

function M.execute_command(cmd, callback)
	local stdout_chunks = {} 
	local timer = vim.loop.new_timer()
    local job_id

    timer:start(5000, 0, function()
        if job_id then
            vim.fn.jobstop(job_id)
            callback(false, "Command timed out after 5 seconds")
        end
        timer:stop()
        timer:close()
    end)

	job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                table.insert(stdout_chunks, line)
            end
        end,
		on_exit = function(_, exit_code)
			timer:stop()
            timer:close()
			if exit_code == 0 then
				local output = table.concat(stdout_chunks, "\n")
				callback(true, output)
			else
				local result = vim.fn.system(cmd .. " 2>&1")
				local error_msg = result:gsub("\n", " "):sub(1, 50) .. "..."
				callback(false, error_msg)
			end
		end,
	})
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

return M
