local M = {}

---@class dismiss.Config.Match
---@field filetypes string[]
---@field buftypes string[]
---@field condition? fun(win: integer): boolean

---@class dismiss.ConfigOptions.Match
---@field filetypes? string[]
---@field buftypes? string[]
---@field condition? fun(win: integer): boolean

---@class dismiss.Config.Labels
---@field charset string
---@field hlgroup string

---@class dismiss.ConfigOptions.Labels
---@field charset? string
---@field hlgroup? string

---@class dismiss.Config
---@field prefer_focused boolean
---@field match dismiss.Config.Match
---@field labels dismiss.Config.Labels

---@class dismiss.ConfigOptions
---@field prefer_focused? boolean
---@field match? dismiss.ConfigOptions.Match
---@field labels? dismiss.ConfigOptions.Labels

---@type dismiss.Config
local defaults = {
    prefer_focused = true,
    match = {
        filetypes = {},
        buftypes = {},
        condition = nil,
    },
    labels = {
        charset = "jklasdfhguiopqwert",
        hlgroup = "DismissLabel",
    },
}

---@type dismiss.Config
local config = vim.deepcopy(defaults)

---@param opts? dismiss.ConfigOptions
function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local function derive_highlight_group()
    -- Use the configured label highlight when it exists; otherwise derive it from Visual.
    if vim.fn.hlexists(config.labels.hlgroup) == 1 then
        return
    end

    local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
    visual.bold = true
    vim.api.nvim_set_hl(0, config.labels.hlgroup, visual)
end

local function is_dismissible_win(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local condition_matches = false

    if type(config.match.condition) == "function" then
        local ok, matches = pcall(config.match.condition, win)
        condition_matches = ok and matches == true
    end

    return vim.tbl_contains(config.match.filetypes, vim.bo[buf].filetype)
        or vim.tbl_contains(config.match.buftypes, vim.bo[buf].buftype)
        or condition_matches
end

local function get_dismissible_wins()
    local wins = {}

    -- Only consider normal tabpage windows. Floats are part of the picker UI itself.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" and is_dismissible_win(win) then
            table.insert(wins, win)
        end
    end

    return wins
end

function M.has_dismissable_win()
    return #get_dismissible_wins() > 0
end

local function assign_labels(windows)
    local labeled_windows = {}

    -- Sort by window number so label assignment stays predictable.
    table.sort(windows, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    for i, win in ipairs(windows) do
        local key = config.labels.charset:sub(i, i)
        -- Each label character selects one dismissible window.
        if key == "" then break end
        labeled_windows[key] = win
    end

    return labeled_windows
end

local function show_overlays(labeled_windows)
    local overlays = {}

    -- Labels are shown inside temporary floats, so ensure the label highlight exists first.
    derive_highlight_group()

    for key, target in pairs(labeled_windows) do
        local mask_buf = vim.api.nvim_create_buf(false, true)
        local label_buf = vim.api.nvim_create_buf(false, true)
        local w = vim.api.nvim_win_get_width(target)
        local h = vim.api.nvim_win_get_height(target)
        local has_winbar = vim.api.nvim_get_option_value("winbar", { win = target }) ~= ""
        -- Windows with a winbar need the mask to be one row shorter than the
        -- window. Otherwise, it covers the bottom win separator or statusline.
        local mask_height = has_winbar and math.max(h - 1, 1) or h
        -- Both floats are positioned relative to the target window and never take focus.
        local base = {
            relative = "win",
            win = target,
            style = "minimal",
            border = "none",
            focusable = false,
            noautocmd = true,
        }
        local mask_win = vim.api.nvim_open_win(mask_buf, false, vim.tbl_extend("force", base, {
            row = 0,
            col = 0,
            width = w,
            height = mask_height,
            zindex = 100,
        }))
        vim.api.nvim_set_option_value(
            "winhighlight",
            "NormalFloat:Normal",
            { win = mask_win }
        )

        -- The label float provides the box styling; the buffer only needs the centered label.
        vim.api.nvim_buf_set_lines(label_buf, 0, -1, false, { "", "  " .. key, "" })

        -- A second float sits on top of the mask and provides the visible centered label.
        local label_win = vim.api.nvim_open_win(label_buf, false, vim.tbl_extend("force", base, {
            row = math.floor((h - 3) / 2),
            col = math.floor((w - 5) / 2),
            width = 5,
            height = 3,
            zindex = 200,
        }))
        vim.api.nvim_set_option_value(
            "winhighlight",
            "NormalFloat:" .. config.labels.hlgroup,
            { win = label_win }
        )

        overlays[#overlays + 1] = {
            mask_win = mask_win,
            mask_buf = mask_buf,
            label_win = label_win,
            label_buf = label_buf,
        }
    end

    vim.cmd("redraw")

    return overlays
end

local function hide_overlays(overlays)
    for _, overlay in ipairs(overlays) do
        -- Cleanup is protected because windows or buffers can disappear while input is pending.
        pcall(vim.api.nvim_win_close, overlay.label_win, true)
        pcall(vim.api.nvim_buf_delete, overlay.label_buf, { force = true })
        pcall(vim.api.nvim_win_close, overlay.mask_win, true)
        pcall(vim.api.nvim_buf_delete, overlay.mask_buf, { force = true })
    end
end

---@return boolean
function M.dismiss()
    local current_win = vim.api.nvim_get_current_win()
    local current_win_config = vim.api.nvim_win_get_config(current_win)

    -- Floats are transient UI; close the focused one immediately.
    if current_win_config.relative ~= "" then
        pcall(vim.api.nvim_win_close, current_win, true)
        return true
    end

    -- When prefer_focused is set, dismiss the focused window directly without a picker.
    if config.prefer_focused and is_dismissible_win(current_win) then
        pcall(vim.api.nvim_win_close, current_win, true)
        return true
    end

    local wins = get_dismissible_wins()

    -- Return immediately when the current tabpage has no dismissible windows.
    if #wins == 0 then
        return false
    end

    -- Close the only dismissible window directly when there is no choice to make.
    if #wins == 1 then
        pcall(vim.api.nvim_win_close, wins[1], true)
        return true
    end

    -- With multiple candidates, label them, render overlays, and wait for one keypress.
    local labeled_windows = assign_labels(wins)
    local overlays = show_overlays(labeled_windows)
    -- getchar() blocks until a single selection key or <Esc>.
    local ok, ch = pcall(vim.fn.getchar)
    hide_overlays(overlays)

    local key = ok and vim.fn.nr2char(ch)

    -- Ignore cancelled input and keys that do not map to a labeled window.
    if not key or key == vim.fn.nr2char(27) then
        return false
    end

    local target = labeled_windows[key]

    if target then
        -- The chosen label resolves directly to the window that should be closed.
        pcall(vim.api.nvim_win_close, target, true)
        return true
    end

    return false
end

return M
