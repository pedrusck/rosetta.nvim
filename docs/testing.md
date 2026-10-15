# Testing

## Commands

```sh
mise run test          # isolated Neovim tests
mise run format        # format all Lua files with StyLua
mise run format-check
mise run lint          # LuaLS with the current Neovim runtime metadata
mise run check         # formatting, LuaLS warnings, and tests, in order
```

Install mise, Neovim and LuaLS. StyLua is managed by the `[tools]` configuration
in `mise.toml`; `mise install` installs it explicitly, and task execution installs
missing configured tools automatically. Tasks run from the repository root even
when invoked from a subdirectory. `check` stops at the first failed task.

Set `LUA_LS=/path/to/lua-language-server` when it is not on PATH. `tests/lint.lua`
supplies `VIMRUNTIME` and stores diagnostics in a temporary directory. For an
editor's LuaLS session, expose the same `VIMRUNTIME` environment variable; the
checked-in `.luarc.json` uses it for Neovim API types.

To invoke the mise-managed StyLua directly:

```sh
mise exec -- stylua --check lua plugin tests
```

Run a single spec:

```sh
nvim --headless -u NONE -i NONE --noplugin -n -l tests/runner.lua tests/spec/provider_spec.lua
```

## Harness

`tests/run.lua` creates a fresh editor process for each spec. Startup configuration,
ShaDa and plugins are disabled. Swap and persistent undo are disabled in the
runner. Assertions report tracebacks and failures produce a nonzero exit status.
Test files may contain several scenarios sharing one explicitly controlled
fixture; module/autocmd state never crosses spec boundaries.

Provider fixtures hold HTTP/credential callbacks so tests can deliver responses
out of order, after cancellation, and after model/context changes. Checker tests
use a controlled LSP client adapter. Resource tests run local shell processes and
exercise bounded collection, termination and credential failure. No test reads
live provider credentials or downloads dependencies.

Undo needs a real editor input boundary. Its spec uses an embedded child Neovim
over RPC and sends typed edits separately from response callbacks; running the
entire scenario inside one Lua invocation would create misleading undo grouping.

## Coverage map

- `loading_spec`: deferred registration, configuration/completion/health isolation.
- `domain_spec`: replacement configuration, malformed input, aliases, logical
  text, command modifiers and HTTP framing.
- `provider_spec`: preparation, discovery failure, picker revisions, captured
  models, context replacement, recovery and callback settlement.
- `translation_spec`: preflight, supersession, cancellation, late responses,
  locale invalidation, modifiability and pending delivery.
- `lifecycle_spec` / `editor_spec`: registration identity, rename/unload, failed
  allocation, retained text, restoration and auxiliary window protection.
- `presentation_spec`: exception recovery, coalescing, user overrides, status
  precedence and pure layout decisions.
- `checking_spec`: captured checker profiles, diagnostic provenance, stale client
  callbacks, directive cache, action filtering and correction snapshots.
- `completion_spec`: protocol cancellation and stale collector responses.
- `pickers_spec`: stale variant selection and operation completion while stopped.
- `resources_spec`: file ownership, subprocess limits and credential framing.
- `http_spec`: real curl against an in-process loopback HTTP fixture, including
  authentication framing and request-file cleanup.
- `architecture_spec`: acyclic internal module dependencies.
- `undo_spec`: pre-delivery restoration, post-delivery typing and identical output.

CI runs formatting, LuaLS and tests on Linux/macOS at the declared minimum and
current pinned Neovim versions. New behavioral changes should add a scenario at
the narrowest boundary that captures the contract. Use real editor integration
for window, buffer, option, input and undo behavior.

## Manual integration acceptance

Real provider semantics, installed dictionaries, deployed LTeX+ variants and
Telescope interaction depend on the user's environment. Record their exact
versions/configuration when exercising them. Controlled fixtures verify Rosetta's
protocol handling and lifetimes; they do not certify an external deployment.

Correction completion remains gated. The backend tests are necessary but do not
establish consumer-side safe acceptance; see [feasibility.md](feasibility.md).
