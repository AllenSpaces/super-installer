local float_win_id = nil
local float_buf_id = nil
local error_win_id = nil
local error_buf_id = nil

local function create_float_win()
    local screen_width = vim.opt.columns:get()
    local screen_height = vim.opt.lines:get()
    local win_width = math.floor(screen_width * 0.4)
    local win_height = 3
    local col = math.floor((screen_width - win_width) / 2)
    local row = math.floor((screen_height - win_height) / 2)

    float_buf_id = vim.api.nvim_create_buf(false, true)
    float_win_id = vim.api.nvim_open_win(float_buf_id, false, {
        relative = "editor",
        width = win_width,
        height = win_height,
        col = col,
        row = row,
        border = "rounded",
        style = "minimal",
    })
end

local function update_float_win(plugin_name, progress)
    if float_buf_id then
        local lines = {
            "Processing: " .. plugin_name,
            string.rep("=", math.floor(progress * 20)) .. string.rep(" ", 20 - math.floor(progress * 20))
        }
        vim.api.nvim_buf_set_lines(float_buf_id, 0, -1, false, lines)
    end
end

local function close_float_win()
    if float_win_id then
        vim.api.nvim_win_close(float_win_id, true)
        float_win_id = nil
    end
    if float_buf_id then
        vim.api.nvim_buf_delete(float_buf_id, { force = true })
        float_buf_id = nil
    end
end

local function create_error_win(errors)
    local screen_width = vim.opt.columns:get()
    local screen_height = vim.opt.lines:get()
    local win_width = math.floor(screen_width * 0.6)
    local win_height = #errors + 2
    local col = math.floor((screen_width - win_width) / 2)
    local row = math.floor((screen_height - win_height) / 2)

    error_buf_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(error_buf_id, 0, -1, false, { "Plugins with errors:" })
    vim.api.nvim_buf_set_lines(error_buf_id, 1, -1, false, errors)
    error_win_id = vim.api.nvim_open_win(error_buf_id, true, {
        relative = "editor",
        width = win_width,
        height = win_height,
        col = col,
        row = row,
        border = "rounded",
        style = "minimal",
    })

    vim.api.nvim_buf_set_keymap(error_buf_id, "n", "q", "<Cmd>q<CR>", { noremap = true, silent = true })
end

return {
    create_float_win = create_float_win,
    update_float_win = update_float_win,
    close_float_win = close_float_win,
    create_error_win = create_error_win
}