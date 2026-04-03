# dismiss.nvim

Next to my main coding window, I usually have a sidebar on the left, a symbol outline on the right, and a quickfix or trouble list on the bottom. I always found it annoying to close one of them, because I had to navigate to that window and press `<c-w>q`. This plugin provides a single dismiss command that closes your desired window based on rules or a picker.

* First you define a set of `dismissible` windows by filetype, buftype, or a custom match condition.
* Once `dismiss()` is called, it determines which `dismissible` window to close by checking these rules:
    * Current window is a float? Close it.
    * Only one `dismissible` window open? Close it.
    * Current window is `dismissible`? Close it (configurable).
    * More than one `dismissible` window open? Show a labeled picker and let the user decide.

## 🚀 API

```lua
---@param opts? dismiss.ConfigOptions
require("dismiss").setup(opts)
```

Initializes and configures the plugin. See [Configuration](#configuration).

```lua
---@return boolean
require("dismiss").has_dismissable_win()
```

Returns `true` when the current tabpage contains at least one dismissible window.

```lua
---@return boolean
require("dismiss").dismiss()
```

Closes a dismissible window according to the rules described above. Returns `true` when a window was closed, `false` when nothing was dismissed (no dismissible windows, or the picker was cancelled).

## ⚡️ Requirements

Neovim `0.9.0` or newer

## 📦 Installation with `lazy.nvim`

```lua
{
    "tummetott/dismiss.nvim",
    lazy = true,
    ---@type dismiss.ConfigOptions
    opts = {
        -- Optional config overrides
    },
    keys = {
        {
            "<c-q>",
            function()
                require("dismiss").dismiss()
            end,
            desc = "Dismiss window",
        },
    },
}
```

## Configuration

```lua
---@type dismiss.ConfigOptions
{
    -- When true, dismiss() closes the focused window directly if it is
    -- dismissible, without showing the picker.
    prefer_focused = true,

    -- Rules for matching dismissible windows.
    match = {
        -- Match normal windows by filetype.
        filetypes = {},
        -- Match normal windows by buftype.
        buftypes = {},
        -- Callback that receives a window id and returns `true` when that
        -- window should be treated as dismissible.
        condition = nil,
    },

    -- Picker appearance.
    labels = {
        -- Characters used as picker labels.
        charset = "jklasdfhguiopqwertnmzxcbv",
        -- Highlight group used for the label overlay.
        hlgroup = "DismissLabel",
    },
}
```

Matching is additive. A window is dismissible when its buffer matches `filetypes`, `buftypes`, or `condition`. At least one matcher must be configured; with all matchers unset, the plugin does nothing.

If `match.condition` throws an error, `dismiss.nvim` ignores it and treats the window as not matched.

If `labels.hlgroup` does not exist, the plugin derives it from `Visual` with `bold = true`.

## 🪟 Picker controls

* Press the displayed label to close the corresponding window.
* `<Esc>` or any unlabeled key cancels the operation.

## 👯 Similar Plugins

* `s1n7ax/nvim-window-picker`
* `radioactivepb/smartclose.nvim`
