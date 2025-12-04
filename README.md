# Synapse.nvim

A modern, lightweight plugin manager for Neovim with a beautiful UI and intelligent dependency management.

## Features

- 🚀 **Fast Installation**: Quick plugin installation with progress tracking
- 🎨 **Beautiful UI**: Modern floating window interface
- 🔗 **Dependency Management**: Automatic dependency resolution
- 🧹 **Auto Cleanup**: Remove unused plugins automatically
- 🔧 **Post-Install Commands**: Execute build commands after installation/update
- ⚙️ **Auto Setup**: Automatically set up plugins from `.config.lua` files

## Installation

### Using a Plugin Manager

If you're using another plugin manager to install Synapse.nvim:

```lua
-- Using lazy.nvim
{
    "OriginCoderPulse/synapse.nvim",
    config = function()
        require("synapse").setup({})
    end,
}

-- Using packer.nvim
use {
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
    opts = {
        -- Custom plugin installation directory (optional)
        package_path = os.getenv("HOME") .. "/.nvim-utils/package",
        
        -- Directory to scan for .config.lua files (optional)
        -- Default: vim.fn.stdpath("config")
        config_path = vim.fn.stdpath("config"),
    },
})
```

### Configuration Options

#### `opts.package_path` (string)
- **Description**: Directory where plugins will be installed
- **Default**: `vim.fn.stdpath("data") .. "/package"`
- **Example**: `"/home/user/.local/share/nvim/package"`

#### `opts.config_path` (string)
- **Description**: Directory to scan for `.config.lua` plugin configuration files (recursive)
- **Default**: `vim.fn.stdpath("config")`
- **Example**: `"/home/user/.config/nvim"`

#### `opts.default` (string)
- **Description**: Default plugin repository to install
- **Default**: `"OriginCoderPulse/synapse.nvim"`

#### `opts.ui.style` (string)
- **Description**: UI window style
- **Default**: `"float"`
- **Options**: `"float"`, `"split"`

#### `keys.download` (string)
- **Description**: Keymap to open plugin installation UI
- **Default**: `"<leader>si"`

#### `keys.remove` (string)
- **Description**: Keymap to open plugin removal UI
- **Default**: `"<leader>sr"`

#### `keys.upgrade` (string)
- **Description**: Keymap to open plugin upgrade UI
- **Default**: `"<leader>su"`

## Plugin Configuration Files

### File Format

Create `.config.lua` files in your `config_path` directory (or subdirectories). These files support both plugin installation configuration and automatic setup.

**Important**: Only files ending with `.config.lua` will be recognized and automatically processed.

### Configuration File Structure

Each `.config.lua` file must return a table with the following optional fields:

#### Required Fields

- **`repo`** (string): Plugin repository URL in format `"username/repository"`
  - Example: `"nvim-lualine/lualine.nvim"`

#### Installation Configuration Fields

- **`tag`** (string): Lock plugin to a specific version tag
  - Example: `"v1.2.3"`
  - Takes precedence over `branch`

- **`clone_conf.branch`** (string): Clone a specific branch
  - Example: `{ branch = "main" }`
  - Only used if `tag` is not specified

- **`execute`** (string|table): Commands to run after installation/update
  - Example (string): `"make"`
  - Example (table): `{ "make", "cargo build --release" }`

- **`primary`** (string): Custom plugin name for `require()`
  - Use this if the actual require name differs from the extracted name
  - Example: If repo is `"username/plugin-name"` but you require it as `"custom-name"`, set `primary = "custom-name"`

- **`depend`** (table): Plugin dependencies
  - Simple format: `{ "username/dependency" }`
  - With configuration:
    ```lua
    {
        "username/dependency",
        primary = "custom-name",  -- Optional
        opt = {                   -- Optional: configuration for dependency
            option1 = "value1",
        }
    }
    ```

#### Auto-Setup Configuration Fields

- **`opts`** (table): Configuration table passed to `plugin.setup(opts)`
  - Automatically calls `plugin.setup(opts)` if the plugin has a `setup` function
  - Example:
    ```lua
    opts = {
        option1 = "value1",
        option2 = "value2",
    }
    ```

- **`config`** (function): Manual setup function
  - Receives the plugin module as a parameter
  - Use this for custom setup logic
  - Example:
    ```lua
    config = function(plugin)
        plugin.setup({})
        -- Additional setup code
    end
    ```

- **`initialization`** (function): Function executed before `plugin.setup()`
  - Receives a package wrapper that allows accessing plugin submodules
  - Use this to configure plugin submodules before setup
  - Example:
    ```lua
    initialization = function(package)
        -- Access submodules: package({ "submodule" }) or package.submodule
        local install = package({ "install" })
        install.prefer_git = true
    end
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
    primary = "nvim-treesitter",
    initialization = function(package)
        local install = package({ "install" })
        install.prefer_git = true
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

1. **Installation**: Create `.config.lua` files in your `config_path` directory
2. **Auto-Setup**: On Neovim startup, Synapse scans for `.config.lua` files and automatically:
   - Loads plugin configurations
   - Calls `plugin.setup(opts)` for plugins with `opts` field
   - Executes `config` function for plugins with `config` field
   - Applies dependency configurations

3. **Loading Order**:
   - Main plugins are set up first
   - Then dependency configurations are applied

## Troubleshooting

### Plugins Not Recognized

- Ensure configuration files end with `.config.lua` and are in `config_path` directory (supports subdirectories)
- Check that files return a table with a `repo` field
- Verify `repo` field is not empty

### Plugins Not Set Up

- Verify the plugin has a `setup` function if using `opts` format
- Check that `opts` is a table type (not a function)
- For manual setup, use `config` function format
- Ensure the plugin is properly installed before setup

### Keymaps Not Working

- Verify keymaps are not conflicting with other plugins
- Check that the setup function was called correctly
- Try using commands directly: `:SynapseDownload`, `:SynapseRemove`, `:SynapseUpgrade`

## License

See LICENSE file for details.

