local M = {}

local defaults = {
    match = {
        filetypes = {},
        buftypes = {},
    },
    labels = {
        charset = {
            "j", "k", "l", "a", "s", "d", "f", "h", "g",
            "u", "i", "o", "p", "q", "w", "e", "r", "y", "t",
            "n", "m", "z", "x", "c", "b", "v",
        },
        hlgroup = "DismissLabel",
    },
}

local config = defaults

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
    return vim.tbl_contains(config.match.filetypes, vim.bo[buf].filetype)
        or vim.tbl_contains(config.match.buftypes, vim.bo[buf].buftype)
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

local function assign_labels(windows)
    local labeled_windows = {}

    -- Sort by window number so label assignment stays predictable.
    table.sort(windows, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    for i, win in ipairs(windows) do
        local key = config.labels.charset[i]
        -- Each label character selects one dismissible window.
        if not key then break end
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
        -- Both floats are positioned relative to the target window and never take focus.
        local base = {
            relative = "win",
            win = target,
            style = "minimal",
            border = "none",
            focusable = false,
            noautocmd = true,
        }
        -- The mask float blanks the target window by painting over it with Normal.
        local mask_win = vim.api.nvim_open_win(mask_buf, false, vim.tbl_extend("force", base, {
            row = 0,
            col = 0,
            width = w,
            height = math.max(h - 1, 1), -- do not cover the bottom win separator / statusline
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

function M.dismiss()
    local current = vim.api.nvim_get_current_win()

    -- If the cursor is already in a dismissible window, dismiss it immediately.
    if is_dismissible_win(current) then
        pcall(vim.api.nvim_win_close, current, true)
        return
    end

    local wins = get_dismissible_wins()

    -- Return immediately when the current tabpage has no dismissible windows.
    if #wins == 0 then
        return
    end

    -- Close the only dismissible window directly when there is no choice to make.
    if #wins == 1 then
        pcall(vim.api.nvim_win_close, wins[1], true)
        return
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
        return
    end

    local target = labeled_windows[key]

    if target then
        -- The chosen label resolves directly to the window that should be closed.
        pcall(vim.api.nvim_win_close, target, true)
    end
end

return M
