# Synapse.nvim

A modern, lightweight plugin manager for Neovim with a beautiful UI and intelligent dependency management.

## Features

- 📦 **Configuration-based Management**: Manage plugins through simple Lua configuration files
- 🔗 **Automatic Dependency Resolution**: Automatically install, update, and protect plugin dependencies
- 🌿 **Branch & Tag Support**: Clone specific branches or lock to tag versions
- 🎨 **Beautiful UI**: Real-time progress display with customizable ASCII art headers
- ⚡ **Smart Updates**: Check for updates before applying them
- 🧹 **Auto Cleanup**: Remove unused plugins automatically
- 🔧 **Post-Install Commands**: Execute build commands after installation/update

## Installation

### Step 1: Clone Synapse.nvim

Choose your preferred installation location:

**Option 1: Custom Package Directory**
```bash
# Create your package directory (choose any location you prefer)
mkdir -p ~/your-package-directory

# Clone synapse.nvim
git clone https://github.com/OriginCoderPulse/synapse.nvim ~/your-package-directory/synapse.nvim
```

**Option 2: Neovim Data Directory**
```bash
# Use Neovim's standard data directory
git clone https://github.com/OriginCoderPulse/synapse.nvim \
    "$(nvim --cmd 'echo stdpath("data")' --cmd 'qa')/site/pack/synapse.nvim"
```

### Step 2: Configure in init.lua

**Important**: 
1. Add synapse.nvim to `runtimepath` **before** requiring it
2. Load your configuration files **before** calling `synapse.setup()` if you need settings (like `leader` key) to be available when synapse sets up keymaps

```lua
-- Get Neovim's standard paths
local config_dir = vim.fn.stdpath("config")  -- ~/.config/nvim (Unix) or ~/AppData/Local/nvim (Windows)
local data_dir = vim.fn.stdpath("data")      -- ~/.local/share/nvim (Unix) or ~/AppData/Local/nvim-data (Windows)

-- Step 1: Add synapse.nvim to runtimepath (if using custom package directory)
local package_dir = vim.fn.expand("~/your-package-directory")
vim.opt.runtimepath:prepend(package_dir .. "/synapse.nvim")

-- Or if synapse.nvim is in Neovim's data directory, no need to set runtimepath
-- local package_dir = data_dir .. "/site/pack/packer/start"

-- Step 2: Load your configuration files BEFORE synapse.setup()
-- This ensures settings like leader key are available when synapse sets up keymaps
local load_config = require("synapse.core.load")
load_config.load_config(config_dir .. "/lua")

-- Step 3: Setup synapse.nvim
require("synapse").setup({
    method = "https",  -- or "ssh"
    opts = {
        -- Plugin installation directory
        package_path = package_dir,
        
        -- Configuration directory (scanned recursively for .lua files)
        -- Used for plugin installation/update configuration
        config_path = config_dir .. "/lua/plugins",
        
        -- UI customization
        ui = {
            style = "float",
        },
    },
    keys = {
        download = "<leader>i",
        remove = "<leader>r",
        upgrade = "<leader>u",
    },
})
```

**Note**: 
- Load configuration files **before** `synapse.setup()` if you need settings (like `leader` key) available when keymaps are set up
- All `.config.lua` files in the specified path will be loaded and executed immediately (no lazy loading)
- The order matters! Load configs → Setup synapse

## Configuration

### Basic Setup

```lua
local config_dir = vim.fn.stdpath("config")
local data_dir = vim.fn.stdpath("data")

require("synapse").setup({
    -- Git clone method: "ssh" or "https"
    method = "https",
    
    opts = {
        -- Plugin installation directory
        package_path = data_dir .. "/site/pack/packer/start",
        
        -- Configuration directory (scanned recursively for .lua files)
        config_path = config_dir .. "/lua/plugins",
        
        -- Note: load_config is no longer used in synapse.setup()
        -- Load your .config.lua files manually BEFORE synapse.setup() if needed
        
        -- UI customization
        ui = {
            style = "float",
            header = {
                text = {
                    "███████╗██╗   ██╗███╗   ██╗ █████╗ ██████╗ ███████╗███████╗",
                    "██╔════╝╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔════╝██╔════╝",
                    "███████╗ ╚████╔╝ ██╔██╗ ██║███████║██████╔╝███████╗█████╗  ",
                    "╚════██║  ╚██╔╝  ██║╚██╗██║██╔══██║██╔═══╝ ╚════██║██╔══╝  ",
                    "███████║   ██║   ██║ ╚████║██║  ██║██║     ███████║███████╗",
                    "╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝",
                },
                hl = "SynapseHeader",  -- or hex color: "#e6d5fb"
            },
            plug = {
                hl = "SynapsePlugin",  -- or hex color: "#d5fbd9"
            },
            icons = {
                download = { glyph = "", hl = "SynapseDownload" },
                upgrade = { glyph = "󰚰", hl = "SynapseUpgrade" },
                remove = { glyph = "󰺝", hl = "SynapseRemove" },
                check = { glyph = "󱥾", hl = "SynapseCheck" },
                success = { glyph = "", hl = "SynapseSuccess" },
                faild = { glyph = "󰬌", hl = "SynapseFaild" },
                progress = {
                    glyph = "",
                    hl = {
                        default = "SynapseProgressDefault",
                        progress = "SynapseProgress",
                    },
                },
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

### Custom Package Directory Setup

If you want to use a custom package directory:

1. **Create the directory**:
```bash
mkdir -p ~/your-custom-packages
```

2. **Add to runtimepath in init.lua** (before requiring synapse):
```lua
local package_dir = vim.fn.expand("~/your-custom-packages")

-- Add custom package directory to runtimepath
vim.opt.runtimepath:append(package_dir .. "/*")
vim.opt.runtimepath:append(package_dir .. "/*/after")
```

3. **Configure synapse with matching package_path**:
```lua
require("synapse").setup({
    opts = {
        package_path = package_dir,
        -- ... other options
    },
})
```

**Important Notes**:
- `runtimepath` must be set **before** `require("synapse").setup()`
- The `package_path` in synapse config must match the directory in `runtimepath`
- Use `/*` pattern in runtimepath to include all subdirectories
- Use `/*/after` pattern to include `after` directories for plugins

## Plugin Configuration Files

Synapse uses two types of configuration files:

### 1. Installation Configuration Files (`.lua` files in `config_path`)

These files define which plugins to install, their dependencies, versions, and post-install commands.

**Location**: `config_path` directory (recursively scanned)

**Example**: `config_dir/lua/plugins/example.lua`

```lua
return {
    -- Repository URL (required)
    repo = "username/plugin-name",
    
    -- Dependencies (optional)
    depend = {
        "username/dependency-plugin",
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
    
    -- Plugin configuration function (optional)
    config = function()
        require("plugin-name").setup({})
    end,
}
```

### 2. Load Configuration Files (`.config.lua` files)

These files contain plugin configuration functions. You should load them **before** `synapse.setup()` if you need settings (like `leader` key) to be available when synapse sets up keymaps.

**Location**: Your Neovim config directory (e.g., `~/.config/nvim/lua/`)

**Loading in init.lua**:

```lua
-- Load configuration files BEFORE synapse.setup()
local load_config = require("synapse.core.load")
load_config.load_config(vim.fn.stdpath("config") .. "/lua")

-- Now setup synapse (leader key is already set)
require("synapse").setup({
    -- ... your config
})
```

**Example**: `config_dir/lua/configs/custom.config.lua`

```lua
return {
    config = function()
        local status, plugin = pcall(require, "plugin-name")
        if not status then
            vim.notify("plugin-name is not found ...", vim.log.levels.ERROR, { title = "Nvim" })
            return
        end
        plugin.setup({
            -- Your configuration
        })
    end,
}
```

**Lazy Loading**: You can defer configuration loading:

```lua
-- Load on specific event
return {
    loaded = {
        event = { "BufEnter", "BufWinEnter" },
    },
    config = function()
        -- Configuration code
    end,
}
```

```lua
-- Load on specific file type
return {
    loaded = {
        ft = { "python", "lua" },
    },
    config = function()
        -- Configuration code
    end,
}
```

## Usage

### Commands

- `:SynapseDownload` - Install missing plugins
- `:SynapseUpgrade` - Update all plugins
- `:SynapseRemove` - Remove unused plugins
- `:SynapseError` - View error messages from failed operations (toggle window)

### Keymaps (default)

- `<leader>si` - Install plugins
- `<leader>sr` - Remove unused plugins
- `<leader>su` - Update plugins

## Configuration Options

### `method`

- **Type**: `string`
- **Default**: `"https"`
- **Values**: `"ssh"` or `"https"`
- **Description**: Git clone protocol

### `opts.package_path`

- **Type**: `string`
- **Default**: `vim.fn.stdpath("data") .. "/site/pack/packer/start"`
- **Description**: Directory where plugins are installed. Must match the directory added to `runtimepath` if using a custom location.

### `opts.config_path`

- **Type**: `string`
- **Default**: `vim.fn.stdpath("config") .. "/lua/plugins"`
- **Description**: Directory to scan for plugin installation configuration files (recursive). Scans for all `.lua` files that define plugin repositories, dependencies, tags, and execute commands.

### Loading Configuration Files

**Note**: `load_config` is no longer a configuration option. Instead, you should manually load your `.config.lua` files **before** `synapse.setup()` if you need settings (like `leader` key) to be available.

**Example**:

```lua
-- In your init.lua, BEFORE synapse.setup()
local load_config = require("synapse.core.load")
load_config.load_config(vim.fn.stdpath("config") .. "/lua")

-- Then setup synapse
require("synapse").setup({
    -- ... your config
})
```

**Why load before setup?**
- If your configs set `leader` key or other basic settings, they need to be loaded before `synapse.setup()` executes
- This ensures keymaps can use `<leader>` correctly
- Configs loaded before setup are executed immediately (no lazy loading)

### `opts.ui`

- **Type**: `table`
- **Description**: UI customization options

See the [UI Features](#ui-features) section for details.

### `keys`

- **Type**: `table`
- **Description**: Keymap configuration
- **Fields**:
  - `download`: Install plugin keymap (default: `<leader>si`)
  - `remove`: Remove plugin keymap (default: `<leader>sr`)
  - `upgrade`: Update plugin keymap (default: `<leader>su`)

## UI Features

### Progress Window

- **Header**: Customizable multi-line ASCII art (centered)
- **Plugin List**: Shows up to 10 plugins at a time with dynamic scrolling
- **Progress Bar**: Visual progress indicator with customizable colors
- **Status Icons**: Different icons for pending, active, success, and failed states

### Window Controls

- `q` or `Esc` - Close window
- `R` - Retry failed operations (when viewing failures)

### Error Window

When operations fail, error information is automatically saved. Use `:SynapseError` to view all error messages:

- **Format**: Errors are displayed in Markdown format
  - Plugin name as level 1 heading (`# PluginName`)
  - Error message using error admonition syntax (`> [!ERROR]`)
- **Window**: 
  - Same size as install/update windows (70% width, 60% height)
  - Title: " Synapse Error " (centered)
  - Buffer name: `SynapseError`
  - Filetype: `markdown` (for syntax highlighting)
- **Features**:
  - Automatically wraps long error messages
  - Removes trailing empty lines
  - Toggle with `:SynapseError` command (opens if closed, closes if open)
  - Errors are cleared when retrying operations (press `R` to retry)
- **Controls**:
  - `q` or `Esc` - Close error window

## Dependency Management

Synapse automatically handles plugin dependencies:

1. **Auto-install**: Dependencies are installed automatically
2. **Deduplication**: Shared dependencies are installed only once
3. **Priority**: If a dependency is also a main plugin, its configuration takes precedence
4. **Protection**: Dependencies are protected during removal unless unused

## Version Management

Synapse supports both branch and tag-based version control:

- **Tag Support**: Use `tag` field in plugin configuration to lock to a specific version
  - When `tag` is specified, it takes precedence over `branch`
  - Tag information is saved to `synapse.yaml` for persistence
  - Updates will respect tag changes in configuration

- **Branch Support**: Use `clone_conf.branch` to specify a branch
  - Default branch is used if not specified
  - Branch information is saved to `synapse.yaml` (only if not "main" or "master")

- **synapse.yaml**: Automatically created in `package_path` directory
  - Records installed plugins with their repository, branch, tag, and dependencies
  - Only main plugins are recorded (dependencies are stored in `depend` field)
  - Used to maintain consistency across installations and updates

- **Post-Install Commands**: Use `execute` field to run build commands
  - Commands are executed after successful Git clone/update
  - Supports both installation and update operations
  - Commands run in the plugin's installation directory
  - Useful for compiled plugins that require build steps

## Examples

### Complete Setup Example

```lua
-- Get Neovim's standard paths
local config_dir = vim.fn.stdpath("config")
local data_dir = vim.fn.stdpath("data")

-- Step 1: Add synapse.nvim to runtimepath (if using custom package directory)
local package_dir = vim.fn.expand("~/your-package-directory")
vim.opt.runtimepath:prepend(package_dir .. "/synapse.nvim")

-- Or if synapse.nvim is in Neovim's data directory:
-- local package_dir = data_dir .. "/site/pack/packer/start"

-- Step 2: Load configuration files BEFORE synapse.setup()
-- This ensures settings like leader key are available when synapse sets up keymaps
local load_config = require("synapse.core.load")
load_config.load_config(config_dir .. "/lua")

-- Step 3: Setup synapse.nvim
require("synapse").setup({
    method = "https",
    opts = {
        package_path = package_dir,
        config_path = config_dir .. "/lua/plugins",
        ui = {
            style = "float",
        },
    },
    keys = {
        download = "<leader>i",
        remove = "<leader>r",
        upgrade = "<leader>u",
    },
})
```

**Note**: Loading configs **before** `synapse.setup()` ensures that `custom.config` (which sets `leader` key) is executed before synapse sets up keymaps, so the keymaps can use `<leader>` correctly.

### Plugin with Dependencies

```lua
-- config_dir/lua/plugins/example.lua
return {
    repo = "username/plugin-name",
    depend = {
        "username/dependency-plugin",
        "username/another-dependency",
    },
    config = function()
        require("plugin-name").setup({})
    end,
}
```

### Plugin with Tag Version

```lua
-- config_dir/lua/plugins/versioned.lua
return {
    repo = "username/plugin-name",
    tag = "v1.2.3",  -- Lock to specific tag version
    config = function()
        require("plugin-name").setup({})
    end,
}
```

### Plugin with Post-Install Commands

```lua
-- config_dir/lua/plugins/compiled.lua
return {
    repo = "username/compiled-plugin",
    execute = {
        "make",
        "cargo build --release",
    },
    config = function()
        require("compiled-plugin").setup({})
    end,
}
```

## Troubleshooting

### Neovim Opens with Black Screen

If Neovim opens with a black screen, check:

1. **Runtimepath not set**: Ensure `runtimepath` is set **before** requiring synapse
2. **Package path mismatch**: Verify `package_path` matches the directory in `runtimepath`
3. **Plugin loading errors**: Check error messages with `:SynapseError` command

### Plugins Not Recognized

- Ensure installation configuration files (`.lua`) are in `config_path` (supports subdirectories)
- Check that files return a table with a `repo` field
- Verify `repo` field is not empty

### Keymaps Not Working

- Ensure you load configuration files (`.config.lua`) **before** `synapse.setup()` if they set `leader` key
- Check that `leader` key is set before synapse tries to set up keymaps
- Example:
```lua
-- Load configs first (sets leader key)
local load_config = require("synapse.core.load")
load_config.load_config(vim.fn.stdpath("config") .. "/lua")

-- Then setup synapse (leader key is now available)
require("synapse").setup({ ... })
```

### Dependencies Not Installed

- Check `depend` field format (array of strings)
- Verify repository URLs are correct
- Check network connectivity

### Permission Issues

- Ensure Neovim has write permissions in `package_path`
- Check directory ownership

### Network Issues

- Verify internet connectivity
- Check GitHub accessibility
- Verify SSH keys (if using SSH method)

### Execute Commands Fail

- Ensure the required build tools are installed (make, cargo, npm, etc.)
- Check that the plugin directory contains the necessary build files
- Verify the command syntax is correct
- Check file permissions in the plugin directory
- Review error messages in the UI for specific command failures
- Use `:SynapseError` command to view detailed error messages
- Some commands may require additional environment variables or PATH settings

### Viewing Error Messages

- Use `:SynapseError` command to view all error messages from failed operations
- Error messages are displayed in Markdown format with full content (no truncation)
- Errors are automatically saved when operations fail
- Error cache is cleared when retrying operations (press `R` in the progress window)
- Error window can be toggled with `:SynapseError` command

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License
