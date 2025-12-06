# Synapse.nvim

A modern, lightweight plugin manager for Neovim with a beautiful UI, intelligent dependency management, and automatic plugin setup.

## Features

- 🚀 **Fast Installation**: Quick plugin installation with progress tracking
- 🎨 **Beautiful UI**: Modern floating window interface
- 🔗 **Dependency Management**: Automatic dependency resolution
- 🧹 **Auto Cleanup**: Remove unused plugins automatically
- 🔧 **Post-Install Commands**: Execute build commands after installation/update
- ⚙️ **Auto Setup**: Automatically set up plugins from `.config.lua` files
- 📦 **Import Support**: Load plugin configurations from non-standard files using the `imports` field
- 🌳 **Nested Imports**: Support for arbitrary depth nested import structures

## Installation

### Using a Plugin Manager

If you're using another plugin manager to install Synapse.nvim:

```lua
-- Example with any plugin manager
{
    "OriginCoderPulse/synapse.nvim",
    config = function()
        require("synapse").setup({})
    end,
}
```

### Manual Installation

1. Clone the repository:

```bash
git clone https://github.com/OriginCoderPulse/synapse.nvim.git ~/.config/nvim/lua/synapse
```

2. Add to your Neovim configuration:

```lua
require("synapse").setup({})
```

## Configuration

### Basic Setup

```lua
require("synapse").setup({
    method = "https",  -- or "ssh"
    opts = {
        -- Custom plugin installation directory (optional)
        package_path = os.getenv("HOME") .. "/.nvim-utils/package",

        -- Directory to scan for .config.lua files (optional)
        -- Default: vim.fn.stdpath("config")
        config_path = vim.fn.stdpath("config"),

        -- Performance optimizations
        performance = {
            reset_packpath = true,
            rtp = {
                reset = true,
                paths = {},
                disabled_plugins = {},
            },
        },
    },

    -- Import field: Load configurations from non-standard files
    -- Supports arbitrary depth nested structures
    imports = {
        lua = {
            test = {
                test1 = { "ok" },  -- Loads config_path/lua/test/test1/ok.lua
            },
        },
    },

    keys = {
        download = "<leader>si",
        remove = "<leader>sr",
        upgrade = "<leader>su",
    },
})
```

### Setup Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `method` | `string` | `"https"` | Git method for cloning repositories. Options: `"https"` or `"ssh"` |
| `opts.package_path` | `string` | `vim.fn.stdpath("data") .. "/package"` | Directory where plugins will be installed |
| `opts.config_path` | `string` | `vim.fn.stdpath("config")` | Directory to scan for `.config.lua` files (recursive) |
| `opts.default` | `string` | `"OriginCoderPulse/synapse.nvim"` | Default plugin repository to install |
| `opts.ui.style` | `string` | `"float"` | UI window style. Options: `"float"`, `"split"` |
| `opts.performance.reset_packpath` | `boolean` | `true` | Reset the package path to improve startup time |
| `opts.performance.rtp.reset` | `boolean` | `true` | Reset the runtime path to basic paths |
| `opts.performance.rtp.paths` | `string[]` | `{}` | Custom paths to include in the runtime path |
| `opts.performance.rtp.disabled_plugins` | `string[]` | `{}` | List of plugins to disable |
| `imports` | `table` | `nil` | Import configurations from non-standard files |
| `keys.download` | `string` | `"<leader>si"` | Keymap to open plugin installation UI |
| `keys.remove` | `string` | `"<leader>sr"` | Keymap to open plugin removal UI |
| `keys.upgrade` | `string` | `"<leader>su"` | Keymap to open plugin upgrade UI |

### Import Field Format

The `imports` field supports arbitrary depth nested structures:

```lua
imports = {
    lua = {
        "config1",  -- Loads config_path/lua/config1.lua
        test = {
            "config2",  -- Loads config_path/lua/test/config2.lua
            test1 = { "config3" },  -- Loads config_path/lua/test/test1/config3.lua
        },
    },
}
```

**Rules:**
- Array elements (numeric keys with string values) are appended directly to the current path
- String keys create subdirectories and continue recursion
- Mixed arrays and string keys in the same table are both processed

## Plugin Configuration Files

### File Format

Create `.config.lua` files in your `config_path` directory (or subdirectories). These files support both plugin installation configuration and automatic setup.

**Important**: Only files ending with `.config.lua` will be recognized and automatically processed. For non-standard files, use the `imports` field in your main configuration.

### Configuration File Structure

Each `.config.lua` file must return a table with the following fields:

#### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `repo` | `string` | Plugin repository URL in format `"username/repository"` | `"nvim-lualine/lualine.nvim"` |

#### Installation Configuration Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `tag` | `string` | Lock plugin to a specific version tag. Takes precedence over `branch` | `"v1.2.3"` |
| `branch` | `string` | Clone a specific branch. Only used if `tag` is not specified | `"main"` |
| `execute` | `string\|table` | Commands to run after installation/update | `"make"` or `{ "make", "cargo build --release" }` |
| `primary` | `string` | Custom plugin name for `require()`. Use if the actual require name differs from the extracted name | `"custom-name"` |
| `depend` | `table` | Plugin dependencies. See dependency format below | See examples |

#### Auto-Setup Configuration Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `opts` | `table` | Configuration table passed to `plugin.setup(opts)`. Automatically calls `plugin.setup(opts)` if the plugin has a `setup` function | `{ option1 = "value1" }` |
| `config` | `function` | Manual setup function. Use for custom setup logic. Receives the plugin module as parameter if available | `function(plugin) plugin.setup({}) end` |
| `initialization` | `function` | Function executed before `plugin.setup()`. Receives a package wrapper for accessing plugin submodules | `function(package) local install = package({ "install" }) end` |

**Note**: All plugins are loaded immediately on startup. Plugins are automatically added to the runtime path and configured during Neovim initialization.

### Dependency Format

Dependencies can be specified in two formats:

**Simple format:**
```lua
depend = {
    "username/dependency",
}
```

**With configuration:**
```lua
depend = {
    {
        "username/dependency",
        primary = "custom-name",  -- Optional
        opt = {                   -- Optional: configuration for dependency
            option1 = "value1",
        }
    }
}
```

### Configuration Examples

#### Basic Plugin Setup

```lua
-- ~/.config/nvim/lua/pkgs/lualine.config.lua
return {
    repo = "nvim-lualine/lualine.nvim",
    primary = "lualine",
    opts = {
        options = {
            theme = "auto",
            icons_enabled = true,
        },
    },
}
```

#### Plugin with Manual Setup

```lua
-- ~/.config/nvim/lua/pkgs/autopairs.config.lua
return {
    repo = "windwp/nvim-autopairs",
    primary = "nvim-autopairs",
    config = function(plugin)
        plugin.setup({})
        -- Additional integration code
    end,
}
```

#### Plugin with Initialization

```lua
-- ~/.config/nvim/lua/pkgs/tree-sitter.config.lua
return {
    repo = "nvim-treesitter/nvim-treesitter",
    primary = "nvim-treesitter.configs",
    initialization = function(package)
        -- Access submodules: package({ "submodule" }) or package.submodule
        local install = package({ "install" })
        install.prefer_git = true

        -- Support for nested structures
        local nested = package({ test = { test1 = { "ok" } } })
    end,
    opts = {
        -- Tree-sitter configuration
    },
}
```

#### Plugin with Dependencies

```lua
-- ~/.config/nvim/lua/pkgs/mason.config.lua
return {
    repo = "williamboman/mason.nvim",
    primary = "mason",
    depend = {
        {
            "williamboman/mason-lspconfig.nvim",
            primary = "mason-lspconfig",
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

#### Plugin with Version Lock

```lua
-- ~/.config/nvim/lua/pkgs/versioned.config.lua
return {
    repo = "username/plugin-name",
    tag = "v1.2.3",
    opts = {
        option1 = "value1",
    },
}
```

#### Plugin with Build Commands

```lua
-- ~/.config/nvim/lua/pkgs/compiled.config.lua
return {
    repo = "username/compiled-plugin",
    execute = {
        "make",
        "cargo build --release",
    },
    opts = {
        option1 = "value1",
    },
}
```

#### Generic Configuration File (No Plugin)

```lua
-- ~/.config/nvim/lua/configs/custom.config.lua
-- Files without a 'repo' field are treated as generic configuration files
return {
    config = function()
        -- Your custom configuration code
        vim.opt.number = true
        vim.opt.relativenumber = true
    end,
}
```

#### Using Import Field

```lua
-- ~/.config/nvim/init.lua
require("synapse").setup({
    opts = {
        config_path = vim.fn.stdpath("config"),
    },
    imports = {
        lua = {
            test = { "config" },  -- Loads ~/.config/nvim/lua/test/config.lua
        },
    },
})

-- ~/.config/nvim/lua/test/config.lua (not a .config.lua file)
return {
    repo = "username/plugin-name",
    opts = {
        option1 = "value1",
    },
}
```

## Commands

- **`:SynapseDownload`**: Open plugin installation UI
- **`:SynapseRemove`**: Open plugin removal UI
- **`:SynapseUpgrade`**: Open plugin upgrade UI
- **`:SynapseError`**: Show all error messages

## Keymaps

- **`<leader>si`**: Open plugin installation UI (SynapseDownload)
- **`<leader>sr`**: Open plugin removal UI (SynapseRemove)
- **`<leader>su`**: Open plugin upgrade UI (SynapseUpgrade)

You can customize these keymaps in your configuration:

```lua
require("synapse").setup({
    keys = {
        download = "<leader>pi",  -- Custom keymap
        remove = "<leader>pr",
        upgrade = "<leader>pu",
    },
})
```

## How It Works

1. **Installation**: Create `.config.lua` files in your `config_path` directory, or use the `imports` field to load configurations from non-standard files
2. **Auto-Setup**: On Neovim startup, Synapse scans for `.config.lua` files and import files, then automatically:
   - Adds all installed plugins to the runtime path
   - Loads plugin configurations
   - Calls `plugin.setup(opts)` for plugins with `opts` field
   - Executes `config` function for plugins with `config` field
   - Applies dependency configurations
3. **Loading Order**:
   - All plugins are added to the runtime path first
   - Main plugins are set up (non-plugin config files are executed)
   - Then dependency configurations are applied
   - All plugins are available immediately after startup

## Plugin Directory Structure

Synapse.nvim uses a structured directory layout for plugin management:

- **Main plugins**: `package_path/plugin-name/plugin-name/`
- **Dependencies**: `package_path/main-plugin-name/depend/dependency-name/`
- **Shared dependencies**: `package_path/public/dependency-name/`
- **Synapse plugin**: `package_path/synapse.nvim/`

## Troubleshooting

### Plugins Not Recognized

- Ensure configuration files end with `.config.lua` and are in `config_path` directory (supports subdirectories)
- For non-standard files, use the `imports` field in your main configuration
- Check that files return a table with a `repo` field (for plugin configs) or a `config` function (for generic configs)
- Verify `repo` field is not empty for plugin configurations

### Plugins Not Set Up

- Verify the plugin has a `setup` function if using `opts` format
- Check that `opts` is a table type (not a function)
- For manual setup, use `config` function format
- Ensure the plugin is properly installed before setup
- Check that the plugin is added to the runtime path

### Plugins Not Found

- Verify the plugin is installed in the correct directory structure
- Check that `package_path` is correctly configured
- Ensure the plugin name matches the directory name
- Use the `primary` field if the require name differs from the directory name

### Keymaps Not Working

- Verify keymaps are not conflicting with other plugins
- Check that the setup function was called correctly
- Try using commands directly: `:SynapseDownload`, `:SynapseRemove`, `:SynapseUpgrade`

## License

See LICENSE file for details.
