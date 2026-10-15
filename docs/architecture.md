# Architecture

The public surface is `require("rosetta")`, `:Rosetta`, the documented `<Plug>`
mappings, and `:checkhealth rosetta`. Internal modules are implementation details.
Behavioral contracts are documented in `doc/rosetta.txt`; this document explains
how those contracts are implemented.

## Composition and dependency direction

```text
plugin -> commands -> public API -> workbench
                                 -> config

workbench constructs:
  session, provider, translation, checking, layout, presentation

provider -> chat -> profiles, text
provider -> injected credentials and HTTP functions
translation -> injected session/provider; chat, text
checking -> spell, files; injected configuration/liveness/change notification
layout -> layout_plan; injected slots/configuration/liveness
presentation -> view; injected registration lookup and view model
transport -> process, files, config
credentials -> process
```

Feature services do not require workbench or discover sibling instances through
module globals. Their `new(deps)` constructors perform no editor or external
initialization. Workbench lazily constructs one service graph for the editor.
Activation installs lifecycle callbacks and creates buffers/clients/requests.

`actions.lua` is shared data loaded during command registration. Optional UI
dependencies are loaded only when a picker opens. Health reads metadata and
configuration without constructing the service graph.

## Ownership

| Owner          | Mutable state                                                                                             |
| -------------- | --------------------------------------------------------------------------------------------------------- |
| `session`      | Lifecycle status, language slots, registration membership, handles, remembered variants, identity epochs  |
| `provider`     | Captured provider configuration, credential, discovery, selected model, probes, child requests, observers |
| `translation`  | Active run, target completion, queued delivery, outcomes and semantic pending reasons                     |
| `checking`     | Client IDs, diagnostic provenance, captured profiles, native option history and directive cache           |
| `layout`       | Tab, designated pane windows, orientation and resize scheduling                                           |
| `presentation` | Applied window options and coalesced refresh scheduling                                                   |
| `files`        | Private directory identity and path ownership ledger                                                      |
| `process`      | Active process handles and termination timers                                                             |

Session slots and checker records are borrowed internal views. Consumers must not
mutate them. Public status queries return new tables. Provider credentials and
contexts are never returned to pickers or translation. A captured execution
object exposes only `model`, `prepare`, `dispatch`, and `is_current`.

Registration records contain document identity only. Checker and translation
records use weak-key maps keyed by registration. Layout keys pane preservation
by registration identity, so replacing a language slot object retains its pane.

## Reconciliation and lifecycle

1. Resolve requested identities/variants against captured language definitions.
2. Prepare a plan and allocate missing buffers. Allocation failure deletes staged
   resources and preserves previous committed registrations.
3. Cancel invalidated work, retire removed registrations, and commit membership.
4. Attach/reconfigure checkers for fresh or changed locales.
5. Restore layout and activate/observe provider readiness.

Checker/display failures after commitment keep editing available. An inactive
provider does not invalidate membership. `stop` keeps checking, documents and
remembered languages; shutdown cancels work and cleans owned files.

The lifecycle module wires Neovim events to coordinator callbacks. Rename may
emit delete events; retirement is classified after the sequence. Actual buffer
detachment sets the detached flag immediately, even if the buffer is reloaded
before scheduled handlers run. A retired opaque handle never resolves to its
replacement.

## Asynchronous contract

| Layer                        | Callback/cancellation behavior                                                                  |
| ---------------------------- | ----------------------------------------------------------------------------------------------- |
| Process supervisor           | Completion is scheduled once, including spawn failure, timeout and cancellation                 |
| Credential environment read  | Scheduled once unless cancelled before delivery                                                 |
| Provider request wrapper     | Suppresses cancelled requests and obsolete contexts                                             |
| Provider observers           | Scheduled once when preparation/probing settles, or when cancelled                              |
| Translation                  | Each accepted target settles once; aggregate callback is scheduled once when all targets settle |
| Correction collector         | Scheduled results only while current; cancellation suppresses delivery                          |
| In-process completion server | Protocol cancellation replies once with request-cancelled                                       |
| Picker                       | Opening returns a receipt; dismissal creates no operation/callback                              |

Injected HTTP and credential functions must invoke completion asynchronously,
after returning their handle, matching the production adapters. Tests may retain
callbacks and invoke them later to exercise deliberate response ordering.

Each layer owns its children. Process cancellation sends TERM to the owned
process group, then KILL after a short grace period. Provider cancellation clears
the credential and cancels outstanding requests. Translation cancellation settles
all unfinished targets, including results waiting for Normal mode.

The code shares scheduled callback/error utilities; feature-specific cancellation
remains explicit because suppressing internal callbacks and completing public
operations are different contracts.

## Validity tokens

| Feature            | Captured validity                                                                  |
| ------------------ | ---------------------------------------------------------------------------------- |
| Translation        | Operation identity, provider context, source/target registration and locale epochs |
| Model picker/probe | Provider context and model revision                                                |
| Variant picker     | Opaque registration and locale epoch                                               |
| Correction         | Registration, changedtick, URI, URI epoch, locale epoch and checker epoch          |

Translation captures model/configuration before dispatch. Selecting another model
does not invalidate the captured run. A reconnect replaces the context and cancels
the run. Target edits after dispatch are intentionally replaceable; corrections
instead require an exact document snapshot.

Provider preparation states are `preparing -> usable|failed`. Model states are
`unselected -> probing -> validated|failed`. Missing profile metadata can defer a
probe until discovery finishes. Authentication/rate-limit errors on generation
routes set a recovery flag; siblings remain eligible to complete. Readiness is a
derived boolean, not a second independently mutable state.

Translation target states are `running -> waiting -> succeeded`, with `failed`
and `cancelled` terminal paths. Pending language/variant reasons live separately
and clear only when an accepted run captures that registration.

## Rendering and layout

Refresh requests coalesce per scheduled turn. Presentation builds a view model
through injected callbacks, formats it with `view.lua`, and applies options only
while their last values still match Rosetta's previous writes. It resets its
reentrancy guard even after errors. Checker directive inspection occurs on
document changes; labels consume the cached result and mark stale data unverified.

`layout_plan.lua` contains pure split-tree and orientation decisions. Layout owns
the imperative window changes. A complete managed subtree is required before
reflow. Growth preserves rows; explicit restoration retries columns. Resize never
creates registrations or resurrects closed panes.

## Extending the plugin

- **Language/variant:** use the validated registry schema or add built-in data in
  `languages.lua`; keep mappings explicit and add resolution tests.
- **Chat protocol:** extend `chat.lua` and transport routing together, preserving
  complete preflight and strict logical-text response validation.
- **Budget policy:** change `profiles.lua`; test boundary values and failed
  preflight without disturbing the accepted run.
- **Checker:** add an owned adapter with captured configuration, current-document
  provenance and idempotent detach. Do not add fields to registration records.
- **UI:** change the view model and `view.lua`, or supply another picker adapter
  using entries/labels/selection closures. Preserve stale-token validation.
- **Action:** update `actions.lua`, coordinator/API dispatch, help tags, and command
  tests. Keep optional dependencies out of startup registration.

Rosetta buffers use Markdown for editor integrations but membership is explicit.
An unguarded `ftplugin/markdown.lua` would affect ordinary Markdown buffers; any
future filetype-specific setup must check ownership and respect buffer lifetime.
