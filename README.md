# Super Installer

Super Installer is a Neovim plugin designed to simplify the process of installing, removing, and updating Neovim plugins. It provides a user-friendly UI to show the progress and error messages during these operations.

## Installation

### Mac

```shell
git clone https://github.com/wukuohao2003/super-installer ~/.local/share/nvim/site/pack/packer/start
```

### Windows

```shell
git clone https://github.com/wukuohao2003/super-installer "$env:LOCALAPPDATA\nvim-data\site\pack/packer/start"
```

## Configuration

You can customize the plugin by passing a configuration table to the `setup` function. Here is the default configuration:

```lua
require('super-installer').setup({
    -- Installation method, can be "ssh" or "https"
    git = "ssh",

    -- Plugins to install
    install = {
        -- Additional plugins to install, format: "{username}/{repo}"
        use = {}
    },

    -- Key mappings
    keymaps = {
        -- Key mapping to install plugins
        install = "<leader>si",

        -- Key mapping to remove undefined plugins
        remove = "<leader>sr",

        -- Key mapping to update plugins
        update = "<leader>su"
    }
})
```

### Configuration Options

#### `git`

- **Type**: String
- **Default**: `"ssh"`
- **Description**: Specifies the Git protocol to use for cloning repositories. Can be either `"ssh"` or `"https"`.

#### `install`

- **Type**: Table
  - **`use`**:
    - **Type**: Table of Strings
    - **Default**: `{}`
    - **Description**: A list of additional plugins to install. Each plugin should be in the format `"{username}/{repo}"`.

#### `keymaps`

- **Type**: Table
  - **`install`**:
    - **Type**: String
    - **Default**: `"<leader>si"`
    - **Description**: The key mapping to trigger the plugin installation process.
  - **`remove`**:
    - **Type**: String
    - **Default**: `"<leader>sr"`
    - **Description**: The key mapping to trigger the removal of undefined plugins.
  - **`update`**:
    - **Type**: String
    - **Default**: `"<leader>su"`
    - **Description**: The key mapping to trigger the plugin update process.

## Usage

### Installing Plugins

- **Using Key Mapping**: Press the key mapping defined in `keymaps.install` (default: `<leader>si`) in normal mode.
- **Using Command**: Run the `:SuperInstall` command in the Neovim command line.

### Removing Plugins

- **Using Key Mapping**: Press the key mapping defined in `keymaps.remove` (default: `<leader>sr`) in normal mode.
- **Using Command**: Run the `:SuperRemove` command in the Neovim command line. This will remove all plugins that are not defined in the `install` configuration.

### Updating Plugins

- **Using Key Mapping**: Press the key mapping defined in `keymaps.update` (default: `<leader>su`) in normal mode.
- **Using Command**: Run the `:SuperUpdate` command in the Neovim command line. This will update all the plugins defined in the `install` configuration.

## UI and Error Handling

### Progress UI

During the installation, removal, or update process, a floating window will appear, showing the name of the plugin being processed and a simple progress bar.

### Error Handling

If any errors occur during the process, a new floating window will appear after the process is completed. This window will list all the plugins that failed to install, remove, or update, along with the corresponding error messages. You can close this window by pressing the `q` key.

## Troubleshooting

### Permission Issues

Make sure Neovim has the necessary permissions to create, modify, and delete files in the `stdpath('data')/site/pack/plugins/start/` directory. You can change the directory permissions if needed.

### Network Issues

If you encounter problems during the installation or update process, check your network connection and make sure you can access the GitHub repositories. You can try to ping `github.com` to test the network connectivity.

### HTTP/2 Issues

If you get an error related to the HTTP/2 framing layer, you can try to disable HTTP/2 in Git by running the following command:

```bash
git config --global http.version HTTP/1.1
```

## Contributing

If you want to contribute to the Super Installer plugin, feel free to submit issues or pull requests on the GitHub repository.

## License

This plugin is released under the [Your License Name] license. See the `LICENSE` file in the repository for more details.