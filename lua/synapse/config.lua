local M = {}

--- Default configuration
M.default = {
	method = "https",

	opts = {
		default = "OriginCoderPulse/synapse.nvim",
		package_path = vim.fn.stdpath("data") .. "/package",
		-- Directory to scan for .config.lua files (recursive)
		-- These files support both installation config and auto-setup
		config_path = vim.fn.stdpath("config"),

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
				hl = "SynapseHeader",
			},
			plug = {
				hl = "SynapsePlugin",
			},
			icons = {
				download = {
					glyph = "",
					hl = "SynapseDownload",
				},
				upgrade = {
					glyph = "󰚰",
					hl = "SynapseUpgrade",
				},
				remove = {
					glyph = "󰺝",
					hl = "SynapseRemove",
				},
				check = {
					glyph = "󱥾",
					hl = "SynapseCheck",
				},
				package = {
					glyph = "󰏖",
					hl = "SynapsePackage",
				},
				faild = {
					glyph = "󰬌",
					hl = "SynapseFaild",
				},
				success = {
					glyph = "",
					hl = "SynapseSuccess",
				},
				progress = {
					glyph = "",
					hl = {
						default = "SynapseProgressDefault",
						progress = "SynapseProgress",
					},
				},
			},
		},

		performance = {
			reset_packpath = true, -- reset the package path to improve startup time
			rtp = {
				reset = true, -- reset the runtime path to $VIMRUNTIME and your config directory
				---@type string[]
				paths = {}, -- add any custom paths here that you want to includes in the rtp
				---@type string[] list any plugins you want to disable here
				disabled_plugins = {
					-- "gzip",
					-- "matchit",
					-- "matchparen",
					-- "netrwPlugin",
					-- "tarPlugin",
					-- "tohtml",
					-- "tutor",
					-- "zipPlugin",
				},
			},
		},
	},

	keys = {
		download = "<leader>si",
		remove = "<leader>sr",
		upgrade = "<leader>su",
	},
}

--- Merge user config with default config
--- @param user_config table|nil
--- @return table
function M.merge(user_config)
	return vim.tbl_deep_extend("force", M.default, user_config or {})
end

return M
