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

function M.get_install_dir(plugin, command_type, package_path)
	assert(type(plugin) == "string", "Invalid plugin name: " .. tostring(plugin))
	assert(type(command_type) == "string", "Invalid type parameter: " .. tostring(command_type))
	assert(type(package_path) == "string", "Invalid package_path: " .. tostring(package_path))

	local plugin_name = plugin:match("/([^/]+)$") or plugin:match("([^/]+)%.git$") or plugin
	plugin_name = plugin_name:gsub("%.git$", "")

	return string.format("%s/%s", package_path, plugin_name)
end

function M.get_repo_url(plugin, git_type)
	-- 如果已经是完整的 URL，直接返回
	if plugin:match("^https?://") or plugin:match("^git@") then
		return plugin:gsub("%.git$", "") .. ".git"
	end
	
	-- 否则按照原来的方式处理
	assert(plugin and plugin:find("/"), "Invalid plugin format, should be 'user/repo' or full URL")

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

-- 递归获取目录下所有 .lua 文件
local function get_lua_files(dir_path)
	local files = {}
	
	-- 获取当前目录下的 .lua 文件
	local current_files = vim.split(vim.fn.glob(dir_path .. "/*.lua"), "\n")
	for _, file in ipairs(current_files) do
		if file ~= "" then
			table.insert(files, file)
		end
	end
	
	-- 递归获取子目录下的文件
	local subdirs = vim.split(vim.fn.glob(dir_path .. "/*/"), "\n")
	for _, subdir in ipairs(subdirs) do
		if subdir ~= "" and vim.fn.isdirectory(subdir) == 1 then
			local subdir_files = get_lua_files(subdir)
			for _, file in ipairs(subdir_files) do
				table.insert(files, file)
			end
		end
	end
	
	return files
end

-- 从 config_path 目录读取所有配置文件（递归扫描）
function M.load_config_files(config_path)
	local configs = {}
	
	if vim.fn.isdirectory(config_path) ~= 1 then
		return configs
	end
	
	-- 递归获取所有 .lua 文件
	local lua_files = get_lua_files(config_path)
	
	for _, file_path in ipairs(lua_files) do
		if file_path ~= "" then
			local ok, config = pcall(function()
				-- 加载文件并执行，获取返回的配置表
				local chunk = loadfile(file_path)
				if chunk then
					return chunk()
				end
				return nil
			end)
			
			if ok and config and type(config) == "table" then
				-- 检查是否有 repo 字段
				if config.repo and type(config.repo) == "string" and config.repo ~= "" then
					-- 提取配置信息
					local plugin_config = {
						repo = config.repo,
						branch = "main", -- 默认主分支
						config = config.config or {},
						depend = {}, -- 依赖项列表
					}
					
					-- 如果有 clone_conf，使用其中的 branch
					if config.clone_conf and type(config.clone_conf) == "table" and config.clone_conf.branch then
						plugin_config.branch = config.clone_conf.branch
					end
					
					-- 如果有 depend 字段，提取依赖项
					if config.depend and type(config.depend) == "table" then
						for _, dep in ipairs(config.depend) do
							if type(dep) == "string" and dep ~= "" then
								table.insert(plugin_config.depend, dep)
							end
						end
					end
					
					table.insert(configs, plugin_config)
				end
			end
		end
	end
	
	return configs
end

return M
