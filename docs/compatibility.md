# Compatibility

## Supported baseline

- Neovim **0.12.5+**, LuaJIT, and the modern `vim.uv`, `vim.system`, and LSP APIs.
- POSIX process groups and filesystem behavior on Linux/macOS.
- Curl with `--header @-`, `--suppress-connect-headers`, and the flags used in
  `transport.lua`. The original documented curl baseline is 8.7.1.
- OpenAI-compatible `/models` and `/chat/completions` routes; profile budget fields
  and supported generation parameters must match the chosen endpoint/model.

CI is configured for Neovim 0.12.5 and 0.12.6 on Linux/macOS. The refactor was
locally exercised on macOS with Neovim 0.12.6. Windows process-group termination is
not implemented by the current POSIX supervisor.

## Optional integrations

Telescope/Plenary load only when opening a picker. LTeX+ and dictionaries are
user-provisioned. A registered language name is not evidence of installed
dictionary support or a deployed model/checker capability. `languages.lua`
contains data provenance; health reports local availability without requests.

## Behavioral compatibility

The public API, command names, mappings, replacement configuration semantics,
opaque registration handles, native undo behavior and temporary-file ownership
contracts are retained. Public `status()` pending values remain display labels;
internal pending reasons are semantic identifiers.

Internal modules now expose constructors or narrow adapters instead of shared
singleton state. Code reaching into `workbench.state`, `provider.context`,
registration checker fields or `files.ledger` must use the public API or the
documented internal dependency contracts for development.

Correction completion remains gated for all consumers. A protocol fixture pass
is not a compatibility claim for a real completion UI.
