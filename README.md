# Super Installer

Super Installer 是一个 Neovim 插件管理器，用于简化插件的安装、移除和更新过程。它提供了友好的 UI 界面来显示操作进度和错误信息。

## 特性

- 📦 **基于配置文件的插件管理**：通过配置文件管理插件，支持递归扫描子目录
- 🔗 **依赖项自动管理**：自动安装、更新和保护插件的依赖项
- 🌿 **分支支持**：支持指定克隆分支，默认为主分支
- 🎨 **友好的 UI**：实时显示安装进度和错误信息
- ⚡ **自动安装**：启动时自动安装缺失的插件

## 安装

### Mac/Linux

```bash
git clone https://github.com/AllenSpaces/super-installer ~/.nvim-utils/package/super-installer
```

### Windows

```bash
git clone https://github.com/AllenSpaces/super-installer "$env:LOCALAPPDATA\nvim-data\site\pack/packer/start"
```

## 配置

### 基本配置

在你的 Neovim 配置文件中添加以下内容：

```lua
require('super-installer').setup({
    -- Git 克隆方式，可选 "ssh" 或 "https"
    methods = "https",

    opts = {
        -- 默认插件（通常是 super-installer 本身）
        default = "AllenSpaces/super-installer",
        
        -- 插件安装路径
        package_path = os.getenv("HOME") .. "/.super/package",
        
        -- 配置文件目录（从此目录读取插件配置）
        config_path = os.getenv("HOME") .. "/.config/nvim",
    },

    keymaps = {
        install = "<leader>si",  -- 安装插件
        remove = "<leader>sr",   -- 移除未使用的插件
        update = "<leader>su",   -- 更新插件
    },

    ui = {
        progress = {
            icon = "",  -- 进度条图标
        },
        manager = {
            icon = {
                install = "",
                update = "",
                remove = "󰺝",
                check = "󱫁",
                package = "󰏖",
            },
        },
    },
})
```

### 配置文件格式

在 `config_path` 目录下创建 `.lua` 文件来定义插件配置。Super Installer 会递归扫描该目录下的所有 `.lua` 文件。

配置文件格式：

```lua
return {
    -- 插件仓库地址（必需）
    repo = "username/repo-name",
    
    -- 克隆配置（可选）
    clone_conf = {
        branch = "main",  -- 克隆分支，默认为 "main"
    },
    
    -- 依赖项列表（可选）
    depend = {
        "dependency1/repo1",
        "dependency2/repo2",
    },
    
    -- 插件配置函数（可选）
    config = function()
        -- 插件配置代码
        require("plugin-name").setup({
            -- 配置选项
        })
    end,
}
```

### 配置示例

#### 基本插件配置

```lua
-- ~/.config/nvim/mason.lua
return {
    repo = "williamboman/mason.nvim",
    clone_conf = {},
    config = function()
        require("mason").setup({
            -- 配置选项
        })
    end,
}
```

#### 带依赖项的插件配置

```lua
-- ~/.config/nvim/telescope.lua
return {
    repo = "nvim-telescope/telescope.nvim",
    clone_conf = {},
    depend = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope-live-grep-args.nvim",
    },
    config = function()
        require("telescope").setup({
            -- 配置选项
        })
    end,
}
```

#### 指定分支的插件配置

```lua
-- ~/.config/nvim/custom-plugin.lua
return {
    repo = "username/repo-name",
    clone_conf = {
        branch = "develop",  -- 克隆 develop 分支
    },
    config = function()
        -- 配置代码
    end,
}
```

## 使用方法

### 安装插件

Super Installer 会在 Neovim 启动时自动安装缺失的插件。你也可以手动触发：

- **使用快捷键**：按 `<leader>si`（默认）
- **使用命令**：执行 `:SuperInstall`

### 更新插件

- **使用快捷键**：按 `<leader>su`（默认）
- **使用命令**：执行 `:SuperUpdate`

### 移除未使用的插件

移除所有不在配置文件中定义的插件：

- **使用快捷键**：按 `<leader>sr`（默认）
- **使用命令**：执行 `:SuperRemove`

## 依赖项管理

Super Installer 会自动处理插件的依赖项：

1. **自动安装**：安装主插件时，会自动安装其所有依赖项
2. **去重处理**：多个插件共享同一依赖项时，只会安装一次
3. **自动更新**：更新时会同时更新主插件和依赖项
4. **智能保护**：移除插件时，依赖项会被保护，除非没有其他插件使用

### 依赖项优先级

如果依赖项本身也是主插件（在配置文件中定义），会使用主插件的配置；否则使用默认配置（branch: "main"）。

## UI 和错误处理

### 进度显示

在执行安装、更新或移除操作时，会显示一个浮动窗口，显示：
- 当前处理的插件名称
- 进度条和百分比
- 操作状态

### 错误处理

如果操作过程中出现错误，会在操作完成后显示错误报告窗口，列出所有失败的插件和对应的错误信息。按 `q` 键关闭窗口。

## 配置选项说明

### `methods`

- **类型**：String
- **默认值**：`"https"`
- **可选值**：`"ssh"` 或 `"https"`
- **说明**：指定 Git 克隆协议

### `opts.default`

- **类型**：String
- **默认值**：`"AllenSpaces/super-installer"`
- **说明**：默认插件仓库地址

### `opts.package_path`

- **类型**：String
- **默认值**：`~/.super/package`
- **说明**：插件安装路径

### `opts.config_path`

- **类型**：String
- **默认值**：`~/.config/nvim`
- **说明**：配置文件目录，Super Installer 会递归扫描此目录下的所有 `.lua` 文件

### `keymaps`

- **类型**：Table
- **说明**：快捷键映射配置
  - `install`：安装插件快捷键（默认：`<leader>si`）
  - `remove`：移除插件快捷键（默认：`<leader>sr`）
  - `update`：更新插件快捷键（默认：`<leader>su`）

## 配置文件字段说明

### `repo`（必需）

- **类型**：String
- **格式**：`"username/repo-name"` 或完整 URL
- **说明**：插件仓库地址

### `clone_conf`（可选）

- **类型**：Table
- **说明**：克隆配置
  - `branch`：克隆分支，默认为 `"main"`

### `depend`（可选）

- **类型**：Array of Strings
- **说明**：依赖项列表，每个依赖项格式为 `"username/repo-name"`

### `config`（可选）

- **类型**：Function
- **说明**：插件配置函数，在插件加载后执行

## 常见问题

### 插件没有被识别

确保：
1. 配置文件在 `config_path` 目录下（支持子目录）
2. 配置文件返回一个包含 `repo` 字段的表
3. `repo` 字段不为空

### 依赖项没有被安装

检查：
1. `depend` 字段格式是否正确（字符串数组）
2. 依赖项仓库地址是否正确
3. 网络连接是否正常

### 权限问题

确保 Neovim 有权限在 `package_path` 目录下创建、修改和删除文件。

### 网络问题

如果遇到安装或更新问题，检查：
1. 网络连接是否正常
2. 是否可以访问 GitHub
3. SSH 密钥配置是否正确（如果使用 SSH 方式）

## 贡献

欢迎提交 Issue 或 Pull Request！

## 许可证

MIT License
