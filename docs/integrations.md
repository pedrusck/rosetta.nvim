# Checking and completion integrations

## Native spelling

Language definitions explicitly map variants to native spell names. `spell.lua`
checks installed dictionary metadata, including region availability, before
enabling a mapping. It never installs resources. User spell stores and native
`[s`, `]s`, `z=`, and `zg` remain native Neovim behavior.

Checking captures the original `spelllang`; presentation tracks window-local
`spell` and `winbar`. Values are restored only when they still equal Rosetta's
last write. Later user overrides win.

## LTeX+ ownership

Each registration has a dedicated owned client, with reuse disabled. The client
uses Markdown, its captured checker profile and the effective locale. Configure
only backend locales verified in your deployment:

```lua
require("rosetta").configure({
  checker = {
    enabled = true,
    cmd = { "ltex-ls-plus" },
    locales = { ["en-US"] = true, ["de-DE"] = true },
    debounce_ms = 300,
    settings = { ltex = { enabled = { "markdown" }, checkFrequency = "edit" } },
  },
})
```

The effective `ltex.language` is set by Rosetta. Hosted-only variants additionally
require `checker.hosted = true`. Locale-changing document directives make the
status unverified. Profile capture happens on registration creation or locale
change; rename restarts the URI-bound client with the same captured profile.

Ordinary LTeX clients must exclude buffers with `b:rosetta_owned` **before**
attachment. If configuring an ordinary client using a Neovim root callback, check
the marker before invoking `on_dir`:

```lua
root_dir = function(bufnr, on_dir)
  if vim.b[bufnr].rosetta_owned then return end
  local root = vim.fs.root(bufnr, { ".git" })
  if root then on_dir(root) end
end
```

Apply the ownership exclusion to every auto-attachment path. Rosetta reports an
additional LTeX client as a checking mismatch rather than stopping user clients.

## Diagnostic and action provenance

For owned clients, checking wraps outbound `didOpen`/`didChange` notifications to
associate document versions with changedtick, URI and epochs. A diagnostic is
eligible for correction collection only when its supplied version and URI match
the sent document and the buffer remains unchanged. Ordinary diagnostics still
flow through Neovim's handler even when they cannot establish correction context.

The owned client filters the known dictionary/rule/false-positive persistence
commands from action results. Its supplied command handlers refuse persistence.
An external persistence integration must establish context, storage ownership,
every writing path and cross-instance refresh independently.

## Experimental correction backend

The backend is not attached by workbench and no completion consumer is supported
yet. For development, construct `corrections.new` with `is_live` and a borrowed
`checker_record` accessor. Construct `completion.server(dispatchers, deps)` with
`find_uri` and that corrections service. These are internal development APIs.

Snapshot validation includes changedtick, registration, locale, checker epoch,
URI and URI epoch. Collection is bounded by captured correction settings. Only
single-document, single-line, command-free edits covering the requested position
are eligible. UTF-8/16/32 positions are converted through Neovim's strict helpers.

The protocol backend rejects obsolete requests, but a consumer must also reject
an item accepted after its document changed. See [feasibility.md](feasibility.md)
before changing `completion.supported()`.
