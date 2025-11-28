local ui = require("synapse.ui")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")

local M = {}

local is_update_aborted = false
local update_win = nil
local jobs = {}

function M.start(config)
	is_update_aborted = false
	jobs = {}

	-- 从 config_path 读取配置文件
	local configs = config_utils.load_config_files(config.opts.config_path)
	
	-- 添加默认插件
	local default_config = {
		repo = config.opts.default,
		branch = "main",
		config = {},
	}
	table.insert(configs, 1, default_config)

	-- 提取所有 repo 字段（包括依赖项）
	local plugins = {}
	local plugin_set = {}
	
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			-- 添加主插件
			if not plugin_set[plugin_config.repo] then
				table.insert(plugins, plugin_config.repo)
				plugin_set[plugin_config.repo] = true
			end
			
			-- 添加依赖项
			if plugin_config.depend and type(plugin_config.depend) == "table" then
				for _, dep_repo in ipairs(plugin_config.depend) do
					if not plugin_set[dep_repo] then
						table.insert(plugins, dep_repo)
						plugin_set[dep_repo] = true
					end
				end
			end
		end
	end

	if #plugins == 0 then
		ui.log_message("Nothing to update.")
		return
	end

	local function plugin_names(list)
		local names = {}
		for _, repo in ipairs(list) do
			table.insert(names, string_utils.get_plugin_name(repo))
		end
		return names
	end

	local function attach_close_autocmd(buf)
		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = buf,
			callback = function()
				is_update_aborted = true
				for _, job in ipairs(jobs) do
					vim.fn.jobstop(job)
				end
			end,
		})
	end

	local function start_update_flow(targets, attempt, aggregate)
		attempt = attempt or 1
		aggregate = aggregate or { errors = {}, success = 0, total = 0, checks = 0, check_success = 0 }
		if not targets or #targets == 0 then
			ui.log_message("Nothing to update.")
			return
		end

		is_update_aborted = false
		jobs = {}

		local close_registered = false

		local function ensure_close(buf)
			if close_registered then
				return
			end
			attach_close_autocmd(buf)
			close_registered = true
		end

		local function extract_retry_targets(check_errors)
			local retry_targets = {}
			local seen = {}
			for _, err in ipairs(check_errors or {}) do
				if err.repo and not seen[err.repo] then
					seen[err.repo] = true
					table.insert(retry_targets, err.repo)
				end
			end
			return retry_targets
		end

		local function format_icon(cfg)
			if type(cfg) == "table" then
				return cfg.glyph or cfg.text or cfg.icon or ""
			end
			return cfg or ""
		end

		local function finalize_run()
			local failure_count = #aggregate.errors
			local failed_lookup = {}
			local failed_names = {}
			for _, err in ipairs(aggregate.errors) do
				local name = err.plugin or err.repo or "unknown"
				if not failed_lookup[name] then
					failed_lookup[name] = true
					table.insert(failed_names, name)
				end
			end

			if failure_count > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(aggregate.errors, aggregate.success, aggregate.total, {
					ui = config.opts.ui,
					failed_plugins = failed_names,
					on_retry = function()
						-- Retry failed plugins
						local retry_targets = {}
						local seen = {}
						for _, err in ipairs(aggregate.errors) do
							local repo = err.repo
							if repo and not seen[repo] then
								table.insert(retry_targets, repo)
								seen[repo] = true
							end
						end
						if #retry_targets > 0 then
							start_update_flow(retry_targets)
						end
					end,
				})
			else
				ui.close({ message = "Upgrade Success", level = vim.log.levels.INFO })
			end
		end

		local progress_win = ui.open({
			header = config.opts.ui.header,
			icon = config.opts.ui.icons.check,
			plugins = plugin_names(targets),
			ui = config.opts.ui,
		})
		ensure_close(progress_win.buf)

		local function run_checks(queue, callback)
			local total = #queue
			local completed = 0
			local errors = {}
			local pending_update = {}

			local function proceed(index)
				if is_update_aborted then
					return
				end

				if index > total then
					aggregate.checks = aggregate.checks + total
					aggregate.check_success = aggregate.check_success + math.max(0, total - #errors)
					callback(pending_update, errors)
					return
				end

				local repo = queue[index]
				local plugin_name = string_utils.get_plugin_name(repo)

				ui.update_progress(
					progress_win,
					{ plugin = plugin_name, status = "active" },
					completed,
					total,
					config.opts.ui
				)

				M.check_plugin(repo, config.opts.package_path, function(ok, result)
					completed = completed + 1

					if ok and result == "need_update" then
						table.insert(pending_update, repo)
					elseif not ok then
						table.insert(errors, { plugin = plugin_name, error = result, repo = repo })
					end

					ui.update_progress(
						progress_win,
						{ plugin = plugin_name, status = ok and "done" or "failed" },
						completed,
						total,
						config.opts.ui
					)

					proceed(index + 1)
				end)
			end

			proceed(1)
		end

		local function run_updates(queue, check_failures, attempt_id, aggregate_stats, on_complete)
			if is_update_aborted then
				return
			end

			local update_errors = {}
			local update_win = ui.open({
				header = config.opts.ui.header,
				icon = config.opts.ui.icons.update,
				plugins = plugin_names(queue),
				ui = config.opts.ui,
			})
			ensure_close(update_win.buf)

			local total = #queue
			local completed = 0
			local success_count = 0

			local function finalize_updates()
				if is_update_aborted then
					return
				end

				aggregate_stats.success = aggregate_stats.success + success_count
				aggregate_stats.total = aggregate_stats.total + total
				vim.list_extend(aggregate_stats.errors, update_errors)

				if check_failures and #check_failures > 0 then
					if attempt_id < 2 then
						local retry_targets = extract_retry_targets(check_failures)
						if #retry_targets > 0 then
							start_update_flow(retry_targets, attempt_id + 1, aggregate_stats)
							return
						end
					else
						vim.list_extend(aggregate_stats.errors, check_failures)
					end
				end

				on_complete()
			end

			local function process(index)
				if is_update_aborted then
					return
				end

				if index > total then
					finalize_updates()
					return
				end

				local repo = queue[index]
				local plugin_name = string_utils.get_plugin_name(repo)

				ui.update_progress(
					update_win,
					{ plugin = plugin_name, status = "active" },
					completed,
					total,
					config.opts.ui
				)

				M.update_plugin(repo, config.opts.package_path, function(ok, err)
					completed = completed + 1
					if ok then
						success_count = success_count + 1
					else
						table.insert(update_errors, { plugin = plugin_name, error = err, repo = repo })
					end

					ui.update_progress(
						update_win,
						{ plugin = plugin_name, status = ok and "done" or "failed" },
						completed,
						total,
						config.opts.ui
					)

					process(index + 1)
				end)
			end

			process(1)
		end

		run_checks(targets, function(pending_update, check_errors)
			if is_update_aborted then
				return
			end

			local function handle_completion()
				if #check_errors > 0 then
					if attempt < 2 then
						local retry_targets = extract_retry_targets(check_errors)
						if #retry_targets > 0 then
							start_update_flow(retry_targets, attempt + 1, aggregate)
							return
						end
					else
						vim.list_extend(aggregate.errors, check_errors)
					end
				end
				finalize_run()
			end

			if #pending_update == 0 then
				handle_completion()
				return
			end

			run_updates(pending_update, check_errors, attempt, aggregate, handle_completion)
		end)
	end

	start_update_flow(plugins)
end

function M.check_plugin(plugin, package_path, callback)
	if is_update_aborted then
		return callback(false, "Stop")
	end

	local plugin_name = plugin:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", "")
	local install_dir = git_utils.get_install_dir(plugin_name, "update", package_path)
	if vim.fn.isdirectory(install_dir) ~= 1 then
		return callback(false, "Directory is not found")
	end

	local fetch_cmd = string.format("cd %s && git fetch --quiet", install_dir)
	local check_cmd = string.format("cd %s && git rev-list --count HEAD..@{upstream} 2>&1", install_dir)

	local job = git_utils.execute_command(fetch_cmd, function(fetch_ok, _)
		if not fetch_ok then
			return callback(false, "Warehouse synchronization failed")
		end

		git_utils.execute_command(check_cmd, function(_, result)
			local count = tonumber(result:match("%d+"))
			if count and count > 0 then
				callback(true, "need_update")
			else
				callback(true, "already_updated")
			end
		end)
	end)
	table.insert(jobs, job)
end

function M.update_plugin(plugin, package_path, callback)
	if is_update_aborted then
		return callback(false, "Stop")
	end

	local plugin_name = plugin:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", "")
	local install_dir = git_utils.get_install_dir(plugin_name, "update", package_path)
	local cmd = string.format("cd %s && git pull --quiet && git submodule update --init --recursive", install_dir)

	local job = git_utils.execute_command(cmd, function(ok, output)
		callback(ok, ok and "Success" or output)
	end)
	table.insert(jobs, job)
end

return M
