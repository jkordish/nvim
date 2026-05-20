-- Entry point. Order matters: options/keymaps before lazy so leader is set.
require("core.options")
require("core.keymaps")
require("core.autocmds")
require("core.lazy")
