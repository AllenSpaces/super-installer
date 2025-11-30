local M = {}

--- Default configuration
M.default = {
	method = "https",

	opts = {
		default = "OriginCoderPulse/synapse.nvim",
		package_path = os.getenv("HOME") .. "/.synapse/package",
		config_path = os.getenv("HOME") .. "/.config/nvim",
		load_config = os.getenv("HOME") .. "/.config/nvim/lua/",

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

