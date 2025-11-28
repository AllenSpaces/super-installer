# Synapse.nvim

A modern, lightweight plugin manager for Neovim with a beautiful UI and intelligent dependency management.

![Example](gif/Example.gif)

## Features

- 📦 **Configuration-based Management**: Manage plugins through simple Lua configuration files
- 🔗 **Automatic Dependency Resolution**: Automatically install, update, and protect plugin dependencies
- 🌿 **Branch Support**: Clone specific branches for each plugin
- 🎨 **Beautiful UI**: Real-time progress display with customizable ASCII art headers
- ⚡ **Smart Updates**: Check for updates before applying them
- 🧹 **Auto Cleanup**: Remove unused plugins automatically

## Installation

### Mac/Linux

```bash
git clone https://github.com/OriginCoderPulse/synapse.nvim ~/.nvim-utils/package/synapse.nvim
```

### Windows

```bash
git clone https://github.com/OriginCoderPulse/synapse.nvim "$env:LOCALAPPDATA\nvim-data\site\pack/packer/start"
```

## Quick Start

Add to your Neovim configuration:

```lua
require('synapse').setup({
    method = "https",  -- or "ssh"

    opts = {
        default = "OriginCoderPulse/synapse.nvim",
        package_path = os.getenv("HOME") .. "/.synapse/package",
        config_path = os.getenv("HOME") .. "/.config/nvim",
    },

    keys = {
        download = "<leader>si",
        remove = "<leader>sr",
        upgrade = "<leader>su",
    },
})
```

## Configuration

### Basic Setup

```lua
require('synapse').setup({
    -- Git clone method: "ssh" or "https"
    method = "https",

    opts = {
        -- Default plugin (usually synapse itself)
        default = "OriginCoderPulse/synapse.nvim",
        
        -- Plugin installation directory
        package_path = os.getenv("HOME") .. "/.synapse/package",
        
        -- Configuration directory (scanned recursively for .lua files)
        config_path = os.getenv("HOME") .. "/.config/nvim",
        
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
                hl = "SynapseHeader",  -- or use hex color: "#e6d5fb"
            },
            plug = {
                hl = "SynapsePlugin",  -- or use hex color: "#d5fbd9"
            },
            icons = {
                download = { glyph = "", hl = "SynapseDownload" },  -- or "#fbe4d5"
                upgrade = { glyph = "󰚰", hl = "SynapseUpgrade" },
                remove = { glyph = "󰺝", hl = "SynapseRemove" },
                check = { glyph = "󱥾", hl = "SynapseCheck" },
                success = { glyph = "", hl = "SynapseSuccess" },  -- or "#bbc0ed"
                faild = { glyph = "󰬌", hl = "SynapseFaild" },  -- or "#edbbbb"
                progress = {
                    glyph = "",
                    hl = {
                        default = "SynapseProgressDefault",  -- or "#5c6370"
                        progress = "SynapseProgress",  -- or "#fbe4d5"
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

### Plugin Configuration Files

Create `.lua` files in your `config_path` directory (supports subdirectories):

```lua
-- ~/.config/nvim/plugins/telescope.lua
return {
    -- Repository URL (required)
    repo = "nvim-telescope/telescope.nvim",
    
    -- Clone configuration (optional)
    clone_conf = {
        branch = "main",  -- Default: "main"
    },
    
    -- Dependencies (optional)
    depend = {
        "nvim-lua/plenary.nvim",
    },
    
    -- Plugin configuration function (optional)
    config = function()
        require("telescope").setup({
            -- Your configuration
        })
    end,
}
```

## Usage

### Commands

- `:SynapseDownload` - Install missing plugins
- `:SynapseUpgrade` - Update all plugins
- `:SynapseRemove` - Remove unused plugins

### Keymaps (default)

- `<leader>si` - Install plugins
- `<leader>sr` - Remove unused plugins
- `<leader>su` - Update plugins

## UI Features

![Example](gif/Example.gif)

### Progress Window

- **Header**: Customizable multi-line ASCII art (centered)
- **Plugin List**: Shows up to 10 plugins at a time with dynamic scrolling
- **Progress Bar**: Visual progress indicator with customizable colors
- **Status Icons**: Different icons for pending, active, success, and failed states

### Window Controls

- `q` or `Esc` - Close window
- `R` - Retry failed operations (when viewing failures)

## Architecture

The project follows a modular architecture:

```
lua/synapse/
├── init.lua          # Main entry point
├── config.lua        # Configuration management
├── commands.lua      # User commands and keymaps
├── core/             # Core functionality
│   ├── install.lua   # Installation logic
│   ├── remove.lua    # Removal logic
│   └── update.lua    # Update logic
├── ui/               # UI components
│   ├── init.lua      # UI main interface
│   ├── state.lua     # State management
│   ├── window.lua    # Window management
│   ├── renderer.lua  # Rendering logic
│   └── highlights.lua # Highlight groups
└── utils/            # Utility functions
    ├── string.lua    # String utilities
    ├── git.lua       # Git operations
    └── config.lua    # Config file loading
```

## Configuration Options

### `method`

- **Type**: `string`
- **Default**: `"https"`
- **Values**: `"ssh"` or `"https"`
- **Description**: Git clone protocol

### `opts.default`

- **Type**: `string`
- **Default**: `"OriginCoderPulse/synapse.nvim"`
- **Description**: Default plugin repository

### `opts.package_path`

- **Type**: `string`
- **Default**: `~/.synapse/package`
- **Description**: Directory where plugins are installed

### `opts.config_path`

- **Type**: `string`
- **Default**: `~/.config/nvim`
- **Description**: Directory to scan for plugin configuration files (recursive)

### `opts.ui`

- **Type**: `table`
- **Description**: UI customization options

#### `opts.ui.header`

- **Type**: `table`
- **Fields**:
  - `text`: Array of strings for multi-line ASCII art header
  - `hl`: Highlight group name or hex color (e.g., `"SynapseHeader"` or `"#e6d5fb"`)

#### `opts.ui.plug`

- **Type**: `table`
- **Fields**:
  - `hl`: Highlight group name or hex color for plugin names (e.g., `"SynapsePlugin"` or `"#d5fbd9"`)

#### `opts.ui.icons`

- **Type**: `table`
- **Description**: Icon definitions for different operations
- **Fields for each icon**:
  - `glyph`: Icon character (string)
  - `hl`: Highlight group name or hex color (e.g., `"SynapseDownload"` or `"#fbe4d5"`)

**Note**: All `hl` parameters support both highlight group names (strings) and hex color values (e.g., `"#bbc0ed"`). When a hex color is provided, a highlight group is automatically created.

## Dependency Management

Synapse automatically handles plugin dependencies:

1. **Auto-install**: Dependencies are installed automatically
2. **Deduplication**: Shared dependencies are installed only once
3. **Priority**: If a dependency is also a main plugin, its configuration takes precedence
4. **Protection**: Dependencies are protected during removal unless unused

## Examples

### Basic Plugin

```lua
-- ~/.config/nvim/plugins/mason.lua
return {
    repo = "williamboman/mason.nvim",
    config = function()
        require("mason").setup()
    end,
}
```

### Plugin with Dependencies

```lua
-- ~/.config/nvim/plugins/telescope.lua
return {
    repo = "nvim-telescope/telescope.nvim",
    depend = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope-live-grep-args.nvim",
    },
    config = function()
        require("telescope").setup({})
    end,
}
```

### Plugin with Custom Branch

```lua
-- ~/.config/nvim/plugins/custom.lua
return {
    repo = "username/repo-name",
    clone_conf = {
        branch = "develop",
    },
    config = function()
        -- Your config
    end,
}
```

### Custom UI Colors

You can use hex colors directly in `hl` parameters:

```lua
require('synapse').setup({
    opts = {
        ui = {
            header = {
                text = { "Your Header" },
                hl = "#e6d5fb",  -- Use hex color directly
            },
            plug = {
                hl = "#d5fbd9",  -- Plugin name color
            },
            icons = {
                success = {
                    glyph = "✓",
                    hl = "#bbc0ed",  -- Success icon color
                },
                faild = {
                    glyph = "✗",
                    hl = "#edbbbb",  -- Failure icon color
                },
                progress = {
                    glyph = "▸",
                    hl = {
                        default = "#5c6370",  -- Default progress color
                        progress = "#fbe4d5",  -- Active progress color
                    },
                },
            },
        },
    },
})
```

Or use highlight group names:

```lua
require('synapse').setup({
    opts = {
        ui = {
            header = {
                text = { "Your Header" },
                hl = "SynapseHeader",  -- Use highlight group name
            },
            -- ... other config
        },
    },
})
```

## Troubleshooting

### Plugins Not Recognized

- Ensure configuration files are in `config_path` (supports subdirectories)
- Check that files return a table with a `repo` field
- Verify `repo` field is not empty

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

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License
