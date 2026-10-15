# rosetta.nvim

A translation and proofreading workbench for Neovim. Edit an unsaved language
buffer and translate it into the other registered language buffers with
`:Rosetta run`. Native spelling and optional LTeX+ checking work independently.

## Requirements and loading

- Neovim **0.12.5+**.
- `curl` for translation using an OpenAI-compatible chat endpoint.
- Telescope and Plenary for the model and variant pickers.
- Optional, user-provisioned spell dictionaries and LTeX+.

Install the repository on your runtime path using your plugin manager. Rosetta
registers one command and `<Plug>` mappings. Requiring the public API and calling
`configure()` do not activate the workbench or read credentials.

## Configuration

```lua
local rosetta = require("rosetta")
local ok, err = rosetta.configure({
  languages = { "ca", "de", "en" },
  provider = {
    base_url = "https://your-provider.example/v1",
    model = "your-model-id",
    profiles = {
      ["your-model-id"] = {
        -- Replace these example limits with verified model/provider limits.
        context = 32768,
        completion = 4096,
        overhead = 64,
        min_output = 256,
        expansion = 2,
        reasoning_tokens = 0,
        reasoning_shares_completion = false,
        budget_field = "max_tokens", -- or max_completion_tokens
        probe_tokens = 32,
        estimate = function(text) return #text end,
        estimator_note = "Conservative UTF-8 byte estimate; verify for this tokenizer",
        supports = { temperature = true },
        chat = true,
      },
    },
  },
})
if not ok then vim.notify(err.message, vim.log.levels.ERROR) end

vim.keymap.set("n", "<leader>rs", "<Plug>(RosettaStart)")
vim.keymap.set("n", "<leader>rr", "<Plug>(RosettaRun)")
```

Supply the key through `ROSETTA_API_KEY`, or configure a credential command array.
Commands take precedence over the environment; a failed command has no fallback.
Provider activation discovers models and sends a small generation probe. The
probe uses no document text but is a real provider request.

Every `configure()` call replaces prior overrides with defaults plus the new
options. A failed candidate preserves the previous configuration. Provider
settings are captured on activation/reconnect; checker settings on registration
creation or effective locale change. See `:help rosetta-config`.

### Custom language identities

`registry` is additive. Built-in identities cannot be replaced, and every alias
and variant input must resolve unambiguously. Each definition needs explicit
checker mappings (`false` means unavailable):

```lua
require("rosetta").configure({
  languages = { "xyz", "en" },
  registry = {
    xyz = {
      name = "Example language",
      translation_name = "Example language",
      aliases = {},
      default = "xyz-XX",
      variants = {
        ["xyz-XX"] = {
          name = "Example regional variant",
          instruction = "Use the example regional conventions",
          spell = false,
          ltex = false,
        },
      },
    },
  },
})
```

This demonstrates the schema; use real language definitions for translation.

## Commands

| Command                           | Purpose                                                       |
| --------------------------------- | ------------------------------------------------------------- |
| `:Rosetta [start [languages...]]` | Start or restore the requested languages                      |
| `:Rosetta run`                    | Translate the current registered buffer                       |
| `:Rosetta stop`                   | Cancel provider/translation work, preserving editing/checking |
| `:Rosetta layout`                 | Restore remembered panes and retry columns                    |
| `:Rosetta reconnect`              | Capture current provider configuration and reload credentials |
| `:Rosetta model`                  | Select and probe a discovered model                           |
| `:Rosetta variant`                | Change the current registration's variant                     |
| `:checkhealth rosetta`            | Local configuration and dependency checks                     |

The Lua API additionally offers `registration()`, `reassign()` and `status()`.
Expected failures return `nil, { code = ..., message = ... }`. Asynchronous
operations accept `on_complete`; picker dismissal invokes no completion callback.
See `:help rosetta-api` for receipts and results.

Default backing paths are temporary session files. Use `:write /durable/path`
for a durable copy or `:saveas /durable/path` to rename. Rosetta does not save
translated text automatically. See `:help rosetta-files`.

## Development

- [Architecture and extension points](docs/architecture.md)
- [Testing and contributor checks](docs/testing.md)
- [LTeX+, spelling, and completion integrations](docs/integrations.md)
- [Compatibility](docs/compatibility.md)
- [Completion acceptance gate](docs/feasibility.md)

Run `mise run check` with mise, Neovim, and LuaLS installed. Mise manages StyLua
using `mise.toml`. Runtime tests use
local fixtures and do not require provider credentials, Telescope, or LTeX+.
