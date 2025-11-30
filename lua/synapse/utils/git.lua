local M = {}

--- Get installation directory for a plugin
--- @param plugin string
--- @param command_type string
--- @param package_path string
--- @return string
function M.get_install_dir(plugin, command_type, package_path)
	assert(type(plugin) == "string", "Invalid plugin name: " .. tostring(plugin))
	assert(type(command_type) == "string", "Invalid type parameter: " .. tostring(command_type))
	assert(type(package_path) == "string", "Invalid package_path: " .. tostring(package_path))

	local plugin_name = plugin:match("/([^/]+)$") or plugin:match("([^/]+)%.git$") or plugin
	plugin_name = plugin_name:gsub("%.git$", "")

	return string.format("%s/%s", package_path, plugin_name)
end

--- Get repository URL from plugin identifier
--- @param plugin string
--- @param git_type string
--- @return string
function M.get_repo_url(plugin, git_type)
	-- If already a full URL, return as is
	if plugin:match("^https?://") or plugin:match("^git@") then
		return plugin:gsub("%.git$", "") .. ".git"
	end

	-- Otherwise process as user/repo format
	assert(plugin and plugin:find("/"), "Invalid plugin format, should be 'user/repo' or full URL")

	local base_url = (git_type == "ssh") and "git@github.com:%s.git" or "https://github.com/%s.git"

	return string.format(base_url, plugin:gsub("%.git$", ""))
end

--- Execute a shell command asynchronously
--- @param cmd string
--- @param callback function
--- @return number job_id
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
				-- Return full error message without truncation
				local error_msg = #stderr_msg > 0 and stderr_msg or "Unknown error occurred"
				callback(false, error_msg)
			end
		end,
	})
	return job_id
end

return M

