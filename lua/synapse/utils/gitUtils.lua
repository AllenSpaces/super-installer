local M = {}

--- Get installation directory path for a plugin
--- @param plugin string Plugin identifier (e.g., "user/repo")
--- @param commandType string Type of command (e.g., "install", "update")
--- @param packagePath string Base package installation path
--- @return string Full installation directory path
function M.getInstallDir(plugin, commandType, packagePath)
	assert(type(plugin) == "string", "Invalid plugin name: " .. tostring(plugin))
	assert(type(commandType) == "string", "Invalid type parameter: " .. tostring(commandType))
	assert(type(packagePath) == "string", "Invalid packagePath: " .. tostring(packagePath))

	local pluginName = plugin:match("/([^/]+)$") or plugin:match("([^/]+)%.git$") or plugin
	pluginName = pluginName:gsub("%.git$", "")

	return string.format("%s/%s", packagePath, pluginName)
end

--- Get repository URL from plugin identifier
--- @param plugin string Plugin identifier (e.g., "user/repo" or full URL)
--- @param gitType string Git method ("ssh" or "https")
--- @return string Full repository URL
function M.getRepoUrl(plugin, gitType)
	-- If already a full URL, return as is
	if plugin:match("^https?://") or plugin:match("^git@") then
		return plugin:gsub("%.git$", "") .. ".git"
	end

	-- Otherwise process as user/repo format
	assert(plugin and plugin:find("/"), "Invalid plugin format, should be 'user/repo' or full URL")

	local baseUrl = (gitType == "ssh") and "git@github.com:%s.git" or "https://github.com/%s.git"

	return string.format(baseUrl, plugin:gsub("%.git$", ""))
end

--- Execute a shell command asynchronously
--- @param cmd string Command to execute
--- @param callback function Callback function(success, message)
--- @return number jobId Job ID for the async command
function M.executeCommand(cmd, callback)
	local stdoutChunks = {}
	local stderrChunks = {}

	local jobId = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				table.insert(stdoutChunks, line)
			end
		end,
		on_stderr = function(_, data, _)
			for _, line in ipairs(data) do
				table.insert(stderrChunks, line)
			end
		end,
		on_exit = function(_, exitCode)
			local success = exitCode == 0
			local successMsg = table.concat(stdoutChunks, "\n") or ""
			local stderrMsg = table.concat(stderrChunks, "\n") or ""
			local combinedOutput = successMsg .. "\n" .. stderrMsg

			if success then
				local isUpToDate = combinedOutput:lower():find("up%-to%-date") ~= nil
				local formattedMsg = combinedOutput:gsub("\n", " "):sub(1, 100)
				callback(
					true,
					isUpToDate and ("Already up-to-date: " .. formattedMsg) or ("Success: " .. formattedMsg)
				)
			else
				-- Return full error message without truncation
				local errorMsg = #stderrMsg > 0 and stderrMsg or "Unknown error occurred"
				callback(false, errorMsg)
			end
		end,
	})
	return jobId
end

return M

