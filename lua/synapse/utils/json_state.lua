local json_utils = require("synapse.utils.json")
local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")

local M = {}

--- Update metadata fields (total, update_time, hash) in data
--- @param data table
local function update_metadata(data)
  -- Calculate total (number of main plugins + unique dependencies)
  local main_plugin_count = 0
  local unique_deps = {}
  
  if data.plugins and type(data.plugins) == "table" then
    main_plugin_count = #data.plugins
    
    -- Collect all unique dependencies
    for _, plugin in ipairs(data.plugins) do
      if plugin.depend and type(plugin.depend) == "table" then
        for _, dep_item in ipairs(plugin.depend) do
          local dep_repo = config_utils.parse_dependency(dep_item)
          if dep_repo then
            unique_deps[dep_repo] = true
          end
        end
      end
    end
  end
  
  -- Count unique dependencies
  local dep_count = 0
  for _ in pairs(unique_deps) do
    dep_count = dep_count + 1
  end
  
  -- Total = main plugins + unique dependencies
  local total = main_plugin_count + dep_count
  
  -- Get current timestamp
  local update_time = os.time()
  
  -- Convert timestamp to hexadecimal
  local hash = string.format("%x", update_time)
  
  -- Update metadata fields
  data.total = total
  data.update_time = update_time
  data.hash = hash
end

--- Ensure synapse.json exists, create empty file if it doesn't
--- @param package_path string
function M.ensure_json_exists(package_path)
  local json_path = json_utils.get_json_path(package_path)

  if vim.fn.filereadable(json_path) == 1 then
    return
  end

  local json_data = { plugins = {} }
  update_metadata(json_data)
  json_utils.write(json_path, json_data)
end

--- Get plugin branch and tag from synapse.json
--- @param package_path string
--- @param plugin_name string
--- @return string|nil branch
--- @return string|nil tag
function M.get_branch_tag(package_path, plugin_name)
  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)

  if data and data.plugins then
    for _, plugin in ipairs(data.plugins) do
      if plugin.name == plugin_name then
        return plugin.branch, plugin.tag
      end
    end
  end

  return nil, nil
end

--- Internal helper: collect all dependency repos from a JSON data table
--- @param data table
--- @return table<string, boolean>
local function collect_all_depend_repos(data)
  local all_depend_repos = {}
  if not data or not data.plugins then
    return all_depend_repos
  end

  for _, plugin in ipairs(data.plugins) do
    if plugin.depend and type(plugin.depend) == "table" then
      for _, dep_item in ipairs(plugin.depend) do
        local dep_repo = config_utils.parse_dependency(dep_item)
        if dep_repo then
          all_depend_repos[dep_repo] = true
        end
      end
    end
  end

  return all_depend_repos
end

--- Normalize depend field to ensure it's always an array
--- @param plugin table
local function normalize_depend_field(plugin)
  if plugin.depend then
    -- If depend is not an array, convert it
    if type(plugin.depend) ~= "table" then
      plugin.depend = {}
    else
      -- Check if it's an array (has only numeric keys)
      local is_array = true
      local has_numeric_keys = false
      for k, _ in pairs(plugin.depend) do
        if type(k) == "number" then
          has_numeric_keys = true
        else
          is_array = false
          break
        end
      end
      -- If it's not an array, convert to array
      if not is_array or not has_numeric_keys then
        plugin.depend = {}
      end
    end
  else
    plugin.depend = {}
  end
end

--- Update synapse.json with plugin information (only for main plugins)
--- This keeps dependency repos as full repo strings
--- @param package_path string
--- @param plugin_name string
--- @param plugin_config table
--- @param actual_branch string|nil
--- @param actual_tag string|nil
--- @param is_main_plugin boolean
function M.update_main_plugin(package_path, plugin_name, plugin_config, actual_branch, actual_tag, is_main_plugin)
  if not is_main_plugin then
    return
  end

  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)
  if not data then
    data = { plugins = {} }
  end
  
  -- Normalize all existing plugins' depend fields
  for _, plugin in ipairs(data.plugins) do
    normalize_depend_field(plugin)
  end

  -- Collect depend repos from current plugin_config
  local depend_repos = {}
  if plugin_config.depend and type(plugin_config.depend) == "table" then
    for _, dep_item in ipairs(plugin_config.depend) do
      local dep_repo = config_utils.parse_dependency(dep_item)
      if dep_repo then
        table.insert(depend_repos, dep_repo)
      end
    end
  end

  -- Collect all repos that appear in any plugin's depend field (including current plugin)
  local all_depend_repos = collect_all_depend_repos(data)
  for _, dep_repo in ipairs(depend_repos) do
    all_depend_repos[dep_repo] = true
  end

  local current_repo = plugin_config.repo

  -- If this repo is in any depend field, don't save it as a main plugin
  if all_depend_repos[current_repo] then
    return
  end

  -- Check if plugin already exists
  local found = false
  local found_index = nil
  for i, plugin in ipairs(data.plugins) do
    if plugin.name == plugin_name then
      found = true
      found_index = i
      break
    end
  end

  local function set_branch_and_tag(target)
    local branch = actual_branch or plugin_config.branch
    if branch and branch ~= "main" and branch ~= "master" then
      target.branch = branch
    else
      target.branch = nil
    end

    local tag = actual_tag or plugin_config.tag
    if tag then
      target.tag = tag
    else
      target.tag = nil
    end
  end

  if found then
    -- Ensure this plugin is not now only a dependency of others
    local is_in_other_depend = false
    for _, plugin in ipairs(data.plugins) do
      if plugin.name ~= plugin_name and plugin.depend and type(plugin.depend) == "table" then
        for _, dep_item in ipairs(plugin.depend) do
          local dep_repo = config_utils.parse_dependency(dep_item)
          if dep_repo == current_repo then
            is_in_other_depend = true
            break
          end
        end
      end
      if is_in_other_depend then
        break
      end
    end

    if is_in_other_depend then
      table.remove(data.plugins, found_index)
      update_metadata(data)
      json_utils.write(json_path, data)
      return
    end

    -- Update existing entry
    data.plugins[found_index].repo = current_repo
    data.plugins[found_index].depend = depend_repos
    set_branch_and_tag(data.plugins[found_index])
  else
    -- Add new plugin if not found
    local entry = {
      name = plugin_name,
      repo = current_repo,
      depend = depend_repos,
    }
    set_branch_and_tag(entry)
    table.insert(data.plugins, entry)
  end

  update_metadata(data)
  json_utils.write(json_path, data)
end

--- Remove plugin record from synapse.json
--- @param package_path string
--- @param plugin_name string
function M.remove_plugin_entry(package_path, plugin_name)
  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)

  if not data or not data.plugins then
    return
  end

  for i, plugin in ipairs(data.plugins) do
    if plugin.name == plugin_name then
      table.remove(data.plugins, i)
      break
    end
  end

  update_metadata(data)
  json_utils.write(json_path, data)
end

--- Get dependencies of a plugin from synapse.json
--- @param package_path string
--- @param plugin_name string
--- @return table|nil
function M.get_plugin_dependencies(package_path, plugin_name)
  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)

  if not data or not data.plugins then
    return nil
  end

  for _, plugin in ipairs(data.plugins) do
    if plugin.name == plugin_name then
      return plugin.depend or {}
    end
  end

  return nil
end

--- Check if a dependency is referenced by other plugins
--- @param dep_name string
--- @param package_path string
--- @param exclude_plugin string|nil
--- @return boolean
function M.is_dependency_referenced(dep_name, package_path, exclude_plugin)
  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)

  if not data or not data.plugins then
    return false
  end

  for _, plugin in ipairs(data.plugins) do
    if plugin.name ~= exclude_plugin and plugin.depend then
      for _, dep_item in ipairs(plugin.depend) do
        local dep_repo = config_utils.parse_dependency(dep_item)
        if dep_repo then
          local dep_plugin_name = string_utils.get_plugin_name(dep_repo)
          if dep_plugin_name == dep_name then
            return true
          end
        end
      end
    end
  end

  return false
end

--- Add a dependency to a main plugin's depend field in synapse.json
--- Only updates if the main plugin already exists in json
--- @param package_path string
--- @param main_plugin_name string
--- @param dep_repo string
function M.add_dependency_to_main_plugin(package_path, main_plugin_name, dep_repo)
  local json_path = json_utils.get_json_path(package_path)
  local data, _ = json_utils.read(json_path)
  if not data or not data.plugins then
    -- Main plugin not in json yet, will be updated when main plugin is installed
    return
  end

  -- Normalize all existing plugins' depend fields
  for _, plugin in ipairs(data.plugins) do
    normalize_depend_field(plugin)
  end
  
  -- Find the main plugin in json
  local found_index = nil
  for i, plugin in ipairs(data.plugins) do
    if plugin.name == main_plugin_name then
      found_index = i
      break
    end
  end

  if found_index then
    -- Plugin exists, ensure depend is an array
    normalize_depend_field(data.plugins[found_index])
    
    -- Check if dependency already exists
    local dep_exists = false
    for _, existing_dep in ipairs(data.plugins[found_index].depend) do
      if existing_dep == dep_repo then
        dep_exists = true
        break
      end
    end
    
    -- Add dependency if it doesn't exist
    if not dep_exists then
      table.insert(data.plugins[found_index].depend, dep_repo)
      update_metadata(data)
      json_utils.write(json_path, data)
    end
  end
  -- If main plugin not found in json, it will be created when main plugin is installed
end

return M

