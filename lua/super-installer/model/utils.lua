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
			local success = exit_code == 0
			local success_msg = table.concat(stdout_chunks, "\n") or ""
			local stderr_msg = table.concat(stderr_chunks, "\n") or ""
			local combined_output = success_msg .. "\n" .. stderr_msg

			if success then
				local is_up_to_date = combined_output:lower():find("up%-to%-date") ~= nil
				local formatted_msg = combined_output:gsub("\n", " "):sub(1, 100)
				callback(
					true,
					is_up_to_date and ("Already up-to-date: " .. formatted_msg) or ("Success: " .. formatted_msg)
				)
			else
				local error_msg = #stderr_msg > 0 and (stderr_msg:gsub("\n", " "):sub(1, 50) .. "...")
					or "Unknown error occurred"
				callback(false, error_msg)
			end
		end,
	})
	return job_id
end

function M.get_install_dir(plugin, command_type)
	assert(type(plugin) == "string", "Invalid plugin name: " .. tostring(plugin))
	assert(type(command_type) == "string", "Invalid type parameter: " .. tostring(command_type))

	local base_path = vim.fn.has("win32") == 1 and (vim.fn.expand("$env:LOCALAPPDATA") .. "\\nvim-data")
		or vim.fn.stdpath("data")

	local plugin_name = plugin:match("/([^/]+)$") or plugin:match("([^/]+)%.git$") or plugin
	plugin_name = plugin_name:gsub("%.git$", "")

	return string.format("%s/site/pack/packer/start/%s", base_path, plugin_name)
end

function M.get_repo_url(plugin, git_type)
	assert(plugin and plugin:find("/"), "Invalid plugin format, should be 'user/repo'")

	local base_url = (git_type == "ssh") and "git@github.com:%s.git" or "https://github.com/%s.git"

	return string.format(base_url, plugin:gsub("%.git$", ""))
end

function M.table_duplicates(tb)
	local seen = {}
	local result = {}

	for _, value in ipairs(tb) do
		if type(value) == "string" and not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end

	return result
end

return M
