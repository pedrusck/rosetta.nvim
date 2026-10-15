# Correction completion acceptance gate (G-02)

`completion.supported()` remains false. Rosetta includes an in-process protocol
backend and bounded correction collector for development, but has no accepted
completion consumer integration.

Before enabling a named consumer/version, record reproducible acceptance evidence
for all of the following:

1. UTF-8, UTF-16 and UTF-32 positions with non-ASCII text, combining characters and
   supplementary-plane characters.
2. Exact replacement ranges at the beginning, middle and end of words/lines.
3. Document changes between request, response, menu display and final acceptance.
4. Locale changes, rename, checker restart, registration retirement and buffer
   replacement while a menu is open.
5. Cancellation, timeout, out-of-order responses, action resolution and shutdown.
6. Correct native undo behavior and preservation of unrelated edits/registers.
7. Rejection of unsupported edits, commands, additional documents, stale versions
   and oversized results.
8. Bounded collection with native suggestion settings and a real deployed LTeX+
   profile; no unintended persistence action.

Record the consumer, Neovim and checker versions; exact configuration; fixture
inputs; expected ranges; and observed results. Commit automated regressions where
possible and a repeatable manual procedure for menu acceptance. Existing backend
tests cover cancellation and snapshot invalidation, not this full acceptance
matrix. Keep the gate closed until a consumer has complete evidence.
