# Synapse.nvim

A modern, lightweight plugin manager for Neovim with a beautiful UI and intelligent dependency management.

> 📖 **Full Documentation**: See `:help synapse` or [doc/synapse.txt](doc/synapse.txt) for complete documentation.

## Features

- 📦 **Configuration-based Management**: Manage plugins through simple Lua configuration files
- 🔗 **Automatic Dependency Resolution**: Automatically install, update, and protect plugin dependencies
- 🌿 **Branch & Tag Support**: Clone specific branches or lock to tag versions
- 🎨 **Beautiful UI**: Real-time progress display with customizable ASCII art headers
- ⚡ **Smart Updates**: Check for updates before applying them
- 🧹 **Auto Cleanup**: Remove unused plugins automatically
- 🔧 **Post-Install Commands**: Execute build commands after installation/update

## Installation

### 1. Clone to Neovim Default Plugin Directory

Clone the repository to Neovim's default plugin directory:

```bash
# Get Neovim data directory and clone
git clone https://github.com/OriginCoderPulse/synapse.nvim \
    "$(nvim --cmd 'echo stdpath("data")' --cmd 'qa')/site/pack/packer/start/synapse.nvim"
```

Or manually:

```bash
# Unix/Linux/macOS
git clone https://github.com/OriginCoderPulse/synapse.nvim \
    ~/.local/share/nvim/site/pack/packer/start/synapse.nvim

# Windows
git clone https://github.com/OriginCoderPulse/synapse.nvim \
    %LOCALAPPDATA%\nvim-data\site\pack\packer\start\synapse.nvim
```

### 2. Configure in init.lua

Add the following to your `init.lua`:

```lua
-- Add synapse.nvim to runtimepath (if using custom location)
vim.opt.runtimepath:prepend(os.getenv("HOME") .. "/.nvim-utils/package/synapse.nvim")

-- Setup synapse.nvim
require("synapse").setup()
```

**Note**: If you cloned to Neovim's default plugin directory (`~/.local/share/nvim/site/pack/packer/start/`), you don't need to set `runtimepath` manually.

### 3. Commands and Keymaps

**Commands**:
- `:SynapseDownload` - Install missing plugins
- `:SynapseUpgrade` - Update all plugins
- `:SynapseRemove` - Remove unused plugins
- `:SynapseError` - View error messages from failed operations

**Default Keymaps**:
- `<leader>si` - Install plugins (`:SynapseDownload`)
- `<leader>sr` - Remove unused plugins (`:SynapseRemove`)
- `<leader>su` - Update plugins (`:SynapseUpgrade`)

## Configuration

### 4.1 Custom Plugin Installation Directory

You can specify a custom directory for plugin installation:

```lua
require("synapse").setup({
    opts = {
        package_path = os.getenv("HOME") .. "/.nvim-utils/package",
        -- ... other options
    },
})
```

**Important**: If using a custom `package_path`, you must also add it to `runtimepath`:

```lua
-- Add custom package directory to runtimepath
vim.opt.runtimepath:append(os.getenv("HOME") .. "/.nvim-utils/package/*")
vim.opt.runtimepath:append(os.getenv("HOME") .. "/.nvim-utils/package/*/after")

require("synapse").setup({
    opts = {
        package_path = os.getenv("HOME") .. "/.nvim-utils/package",
    },
})
```

### 4.2 Custom Configuration Directory

**Important**: Only files ending with `.config.lua` will be automatically recognized and loaded for plugin setup.

There are two types of configuration directories:

1. **`load_config`**: Directory for `.config.lua` files (auto-loaded and auto-setup)
   - Files must end with `.config.lua` (e.g., `plugin.config.lua`)
   - These files are automatically loaded and plugins are automatically set up
   - Supports both `opts` (table) and `config` (function) formats

2. **`config_path`**: Directory for `.lua` files (plugin installation only)
   - Files end with `.lua` (e.g., `plugin.lua`)
   - These files are only used for plugin installation configuration
   - Do NOT use `.config.lua` extension here

```lua
require("synapse").setup({
    opts = {
        -- Directory to scan for .config.lua files (recursive)
        -- Only files ending with .config.lua will be auto-loaded and auto-setup
        load_config = vim.fn.stdpath("config") .. "/lua",
        
        -- Directory to scan for plugin installation configs (.lua files)
        -- Files here are only used for installation, not auto-setup
        config_path = vim.fn.stdpath("config") .. "/lua/plugins",
    },
})
```

**Example**: Create `~/.config/nvim/lua/pkgs/example.config.lua` (note: must end with `.config.lua`):

```lua
-- Method 1: opts as table (automatically calls plugin.setup(opts))
-- opts must be a table type
return {
    repo = "username/plugin-name",
    primary = "plugin-name",  -- Optional: specify require name
    opts = {
        -- Configuration options will be passed to plugin.setup()
        option1 = "value1",
        option2 = "value2",
    },
}
    
-- Method 2: config as function (manual setup)
-- config must be a function type
-- The function receives the plugin reference as a parameter
return {
    repo = "username/plugin-name",
    primary = "plugin-name",  -- Optional: specify require name
    config = function(plugin)
        -- plugin is the require("plugin-name") result
        -- No need to manually require, it's already loaded
        plugin.setup({
            -- Your configuration
        })
    end,
}
```

**Important Notes**: 
- **File naming**: Only files ending with `.config.lua` will be automatically loaded and set up
- **`opts` format** (must be a **table** type) - Synapse will automatically:
  1. Extract the plugin name from the `repo` field (or use `primary` if specified)
  2. Try to `require` the plugin
  3. Call `plugin.setup(opts_table)` if the plugin has a `setup` function
- **`config` format** (must be a **function** type) - You have full control over plugin setup
  - The function receives the plugin reference as a parameter: `config = function(plugin) ... end`

#### Additional Configuration Options

**`primary` field**: Specify the actual require name if it differs from the extracted name:

```lua
return {
    repo = "username/plugin-name",
    primary = "custom-plugin-name",  -- Use this as require name
    opts = {
        option1 = "value1",
    },
}
```

**`initialization` field**: Execute a function before plugin setup. The function receives a package wrapper that allows accessing plugin submodules:

```lua
return {
    repo = "username/plugin-name",
    initialization = function(package)
        -- package is a wrapper that allows accessing plugin submodules
        -- Access submodules using: package({ "submodule", "path" })
        -- Or using method calls: package.submodule()
        -- This runs before plugin.setup() is called
    end,
    opts = {
        option1 = "value1",
    },
}
```

### 4.3 Plugin Installation Configuration Format

**Important**: Files in `config_path` directory are used **only for plugin installation**, not for auto-setup.

- Use `.lua` extension (e.g., `example.lua`) in `config_path` directory
- These files define which plugins to install, but do NOT automatically set them up
- For auto-setup, create `.config.lua` files in `load_config` directory instead

Create `.lua` files in your `config_path` directory to define which plugins to install:

**Basic Format** (`config_path/example.lua` - note: `.lua` extension, NOT `.config.lua`):

```lua
return {
    -- Repository URL (required)
    repo = "username/plugin-name",
    
    -- Dependencies (optional)
    depend = {
        -- String format (simple dependency)
        "username/dependency-plugin",
        
        -- Table format with opt configuration
        {
            "username/another-dependency",
            opt = {
                -- Configuration options for the dependency
                option1 = "value1",
                option2 = "value2",
            }
        },
        
        -- Table format with primary and opt (same level)
        {
            "username/third-dependency",
            primary = "custom-dep-name",  -- Specify require name
            opt = {
                -- Configuration options for the dependency
                option1 = "value1",
                option2 = "value2",
            }
        },
    },
    
    -- Tag version (optional, takes precedence over branch)
    tag = "v1.0.0",
    
    -- Branch (optional, only if no tag specified)
    clone_conf = {
        branch = "main",
    },
    
    -- Post-install/update commands (optional)
    execute = {
        "make",
        "cargo build --release",
    },  -- Or use a single string: execute = "make"
    
    -- Primary plugin name (optional)
    -- Use this if the require name differs from the extracted name
    primary = "custom-plugin-name",
    
    -- Note: opts and config fields in config_path files are NOT automatically executed
    -- They are only used for dependency configuration via the 'opt' field
    -- For auto-setup, create a .config.lua file in load_config directory instead
}
```

**Examples**:

#### Installation Configuration Examples (`.lua` files in `config_path`)

These files are used **only for plugin installation**, not for auto-setup:

```lua
-- config_path/mason.config.lua (installation config only)
return {
    repo = "williamboman/mason.nvim",
    depend = {
        {
            "williamboman/mason-lspconfig.nvim",
            opt = {
                ensure_installed = { "lua_ls", "pyright" },
                automatic_installation = true,
            }
        },
    },
}
```

```lua
-- config_path/versioned.config.lua (installation config only)
return {
    repo = "username/plugin-name",
    tag = "v1.2.3",  -- Lock to specific tag version
}
```

```lua
-- config_path/compiled.lua (installation config only)
return {
    repo = "username/compiled-plugin",
    execute = {
        "make",
        "cargo build --release",
    },
}
```

#### Auto-Setup Configuration Examples (`.config.lua` files in `load_config`)

**Important**: Only files ending with `.config.lua` in `load_config` directory will be automatically loaded and set up.

```lua
-- load_config/pkgs/lualine.config.lua (auto-setup with opts table)
return {
    repo = "nvim-lualine/lualine.nvim",
    primary = "lualine",  -- Optional: specify require name
    opts = {
        options = {
            theme = "auto",
            icons_enabled = true,
        },
    },
}
```

```lua
-- load_config/pkgs/autopairs.config.lua (auto-setup with config function)
return {
    repo = "windwp/nvim-autopairs",
    primary = "nvim-autopairs",
    config = function(plugin)
        -- plugin is the require("nvim-autopairs") result
        plugin.setup({})
        
        -- Setup cmp integration
        local status, cmp = pcall(require, "cmp")
        if status then
            local autopairs_cmp = require("nvim-autopairs.completion.cmp")
            if autopairs_cmp and autopairs_cmp.on_confirm_done then
                cmp.event:on("confirm_done", autopairs_cmp.on_confirm_done)
            end
        end
    end,
}
```

```lua
-- load_config/pkgs/custom-name.config.lua (auto-setup with primary field)
return {
    repo = "username/plugin-name",
    primary = "custom-plugin-name",  -- Use this as require name
    opts = {
        option1 = "value1",
    },
}
```

```lua
-- load_config/pkgs/with-init.config.lua (auto-setup with initialization function)
return {
    repo = "username/plugin-name",
    primary = "plugin-name",
    initialization = function(package)
        -- Access plugin submodules before setup
        -- package is a wrapper that supports: package({ "submodule" }) or package.submodule()
        local install = package({ "install" })
        -- Or: local install = package.install()
    end,
    opts = {
        option1 = "value1",
    },
}
```

```lua
-- load_config/pkgs/mason.config.lua (auto-setup with dependency configuration)
return {
    repo = "williamboman/mason.nvim",
    primary = "mason",
    depend = {
        {
            "williamboman/mason-lspconfig.nvim",
            primary = "mason-lspconfig",  -- Specify require name
            opt = {
                ensure_installed = { "lua_ls", "pyright" },
                automatic_installation = true,
            }
        },
    },
    opts = {
        -- Mason configuration
    },
}
```

### 4.4 Custom Keymaps

You can customize the keymaps:

```lua
require("synapse").setup({
    keys = {
        download = "<leader>i",  -- Install plugins
        remove = "<leader>r",    -- Remove unused plugins
        upgrade = "<leader>u",   -- Update plugins
    },
})
```

## Complete Configuration Example

```lua
-- Add synapse.nvim to runtimepath (if using custom location)
vim.opt.runtimepath:prepend(os.getenv("HOME") .. "/.nvim-utils/package/synapse.nvim")

require("synapse").setup({
    -- Git clone method: "ssh" or "https"
    method = "https",
    
    opts = {
        -- Custom plugin installation directory
        package_path = os.getenv("HOME") .. "/.nvim-utils/package",
        
        -- Directory for plugin installation configs (.lua files)
        config_path = os.getenv("HOME") .. "/.config/nvim/lua/plugins",
        
        -- Directory for plugin load configs (.config.lua files, auto-loaded)
        load_config = os.getenv("HOME") .. "/.config/nvim/lua",
        
        -- UI customization
        ui = {
            style = "float",
        },
    },
    
    -- Custom keymaps
    keys = {
        download = "<leader>i",
        remove = "<leader>r",
        upgrade = "<leader>u",
    },
})
```

**Note**: If using custom `package_path`, don't forget to add it to `runtimepath`:

```lua
vim.opt.runtimepath:append(os.getenv("HOME") .. "/.nvim-utils/package/*")
vim.opt.runtimepath:append(os.getenv("HOME") .. "/.nvim-utils/package/*/after")
```

## Dependency Management

Synapse automatically handles plugin dependencies:

1. **Auto-install**: Dependencies are installed automatically
2. **Deduplication**: Shared dependencies are installed only once
3. **Priority**: If a dependency is also a main plugin, its configuration takes precedence
4. **Protection**: Dependencies are protected during removal unless unused
5. **Configuration with `opt`**: Dependencies can be configured using the `opt` field

**Loading Order**:
1. All `.config.lua` files from `load_config` directory are loaded first (main plugins are automatically set up)
2. Then dependencies with `opt` are configured (ensuring proper initialization order)

**File Naming Rules**:
- **`.config.lua` files** (in `load_config` directory): Automatically loaded and plugins are automatically set up
- **`.lua` files** (in `config_path` directory): Used only for plugin installation configuration, NOT auto-setup

This ensures that if `plugin-a` depends on `plugin-b`, and both have configurations, `plugin-b` will be set up before `plugin-a`'s dependency configuration is applied.

**Plugin Name Resolution**:

Synapse automatically extracts plugin names from the `repo` field, but you can override this using the `primary` field. The resolution order is:

1. `primary` field (if specified) - highest priority
2. Extract from `repo` field (e.g., "user/plugin-name" -> "plugin-name")
3. Extract from module name (e.g., "pkgs.plugin.config" -> "plugin")
4. Extract from file path

If `primary` is not specified, Synapse will try multiple variations when requiring the plugin:
- Original extracted name
- Lowercase version (if contains uppercase)
- Without "-nvim" or ".nvim" suffix

This helps handle different plugin naming conventions automatically.

## Troubleshooting

### Plugins Not Recognized

- **For plugin installation**: Ensure installation configuration files (`.lua`) are in `config_path` (supports subdirectories)
- **For auto-setup**: Ensure configuration files end with `.config.lua` and are in `load_config` directory
- Check that files return a table with a `repo` field
- Verify `repo` field is not empty
- **Important**: Only `.config.lua` files are automatically loaded and set up. Regular `.lua` files in `config_path` are only used for installation.

### Keymaps Not Working

- Ensure `leader` key is set before `synapse.setup()` is called
- Check that keymaps are not overridden by other configurations

### Dependencies Not Installed

- Check `depend` field format (array of strings or tables)
- Verify repository URLs are correct
- Check network connectivity

## License

MIT License
