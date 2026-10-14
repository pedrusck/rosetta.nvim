---@meta

---@alias rosetta.Outcome 'succeeded'|'failed'|'cancelled'
---@alias rosetta.PendingReason 'language_changed'|'variant_changed'

---@class rosetta.StartReceipt
---@field accepted true
---@field tab? integer
---@field languages string[]

---@class rosetta.RunReceipt
---@field accepted true
---@field id integer
---@field targets integer

---@class rosetta.Noop
---@field noop true

---@class rosetta.ProviderReceipt
---@field accepted true
---@field generation integer

---@class rosetta.PickerReceipt
---@field accepted true Picker opened; dismissal does not invoke on_complete.

---@class rosetta.RunResult
---@field id integer
---@field outcomes table<string, rosetta.Outcome>

---@class rosetta.ProviderStatus
---@field ready boolean
---@field label string
---@field generation integer
---@field model? string
---@field revision? integer
---@field recovery? boolean

---@class rosetta.Cancelled
---@field cancelled true
---@field generation integer
---@field model? string

---@class rosetta.VariantResult
---@field variant string

---@alias rosetta.CompletionResult rosetta.RunResult|rosetta.ProviderStatus|rosetta.Cancelled|rosetta.Noop|rosetta.VariantResult

---@class rosetta.LanguageStatus
---@field id string
---@field variant string
---@field buffer? integer
---@field pending? string Display label, retained for public API compatibility.
---@field outcome? rosetta.Outcome|'running'|'waiting'

---@class rosetta.Status
---@field state 'unconfigured'|'active'|'stopped'
---@field languages rosetta.LanguageStatus[]
---@field provider rosetta.ProviderStatus

---@class rosetta.LanguageSlot
---@field id string
---@field variant string
---@field definition table
---@field registration? rosetta.RegistrationRecord

---@class rosetta.RegistrationRecord
---@field buf integer
---@field ref rosetta.Registration
---@field registration_id integer
---@field slot rosetta.LanguageSlot
---@field locale_epoch integer
---@field uri_epoch integer
---@field detached? boolean

---@class rosetta.RequestHandle
---@field cancel fun() Idempotent; callback behavior depends on its owning service.

---@class rosetta.Execution
---@field model string
---@field is_current fun(): boolean Checks provider generation, not model revision.
---@field prepare fun(messages: table[], source: string): table
---@field dispatch fun(body: table, callback: fun(response: table)): rosetta.RequestHandle

---@class rosetta.TranslationOperation
---@field id integer
---@field source rosetta.RegistrationRecord
---@field source_locale_epoch integer
---@field execution rosetta.Execution
---@field model string
---@field targets table[]
---@field remaining integer
---@field results table<string, rosetta.Outcome>
---@field callback? fun(result: rosetta.RunResult)

---@class rosetta.ProviderContext
---@field config table Captured provider configuration.
---@field generation integer
---@field model_revision integer
---@field state 'preparing'|'usable'|'failed'
---@field model_state 'unselected'|'probing'|'validated'|'failed'
---@field model? string
---@field key? string Private to provider/transport.
---@field handles table<rosetta.RequestHandle, boolean>
---@field listeners function[]

---@class rosetta.CorrectionSnapshot
---@field reg rosetta.RegistrationRecord
---@field checker table Borrowed checker record; consumers do not mutate it.
---@field tick integer
---@field locale_epoch integer
---@field uri_epoch integer
---@field checker_epoch integer
---@field uri string
---@field line string
---@field row integer
---@field byte integer
---@field encoding string

return {}
