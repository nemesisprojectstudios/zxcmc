# Security & trust note

ZxCMC is an automation tool. Everything it does, it does **on your behalf, with
your privileges** — there is no sandbox, no permission layer, and no
capability negotiation between ZxCMC and your operating system. This page
explains what that means in practice: which inputs are dangerous, what the
built-in guardrails do and do not protect, and how to evaluate a config file
or release before trusting it.

## The trust model in one paragraph

A ZxCMC binding is a promise to run something on your machine later, possibly
without you watching. Shell commands run with your user account's full
rights. `@` actions run arbitrary AutoHotkey code — that is a full
programming language with file, network and window access. Therefore the
config files and profiles you import are **programs**, and any file you did
not write yourself should be treated exactly like a downloaded script: read
it before it can fire.

## What executes, and when

| Input | Executes | When |
|---|---|---|
| Command-mapper actions (no prefix) | shell command through the default shell | when the trigger fires (hotkey / hotstring / pixel) |
| `&cmd` actions | shell command through the shell selected in Settings | when the trigger fires |
| `@code` actions | arbitrary AutoHotkey v2 code via a temporary script | when the trigger fires |
| `>` and `>>` actions | raw key/text sending into whatever window is focused | when the trigger fires |
| Macro `run:` / `rw:` actions | shell commands (hidden console) | when the macro runs |
| `keybinds.cfg` / imported profiles | all of the above, once registered | at startup, or at trigger time |
| `zxcmcsettings.ini`, `theme.cfg` | preference values only (validated; color fields must match `RRGGBB`) | never execute code |

Timing matters: importing a config with the sidebar **Import** does not run
anything — registration happens only if you accept. But a config line sitting
in `keybinds.cfg` is live from the next launch, with no further prompt.

## Guardrails that exist

- **Import confirmation gate.** Both the sidebar *Import* and the Profiles-tab
  *Import...* parse the incoming text fully, reject malformed lines with line
  numbers, and show a Yes/No/Cancel preview before anything is registered.
  Answering **No** loads the entries disabled; **Cancel** aborts without
  changes. Use this to review an untrusted file with it still inert.
- **Malformed-line rejection.** Lines that are not `KEY;ACTION`, that use an
  empty profile name, an invalid key or a duplicate id are rejected and
  reported (dialog, or tray tip + `error.log` when started hidden) — they
  never become bindings.
- **`bash -n` syntax validation.** When the selected shell is bash, `&`
  commands are syntax-checked before saving. This catches typos, *not*
  malice — a syntactically valid `rm -rf` passes.
- **Atomic config saves.** All config writes go to a `.tmp` file that
  atomically replaces the target, so a crash or full disk cannot leave a
  half-written `keybinds.cfg`.
- **Scope fields are inert data.** A binding's `[wintitle]` scope is a
  WinTitle criterion, never a command; `theme.cfg` colors are validated as
  hexadecimal before use.
- **Undo.** Ctrl+Z restores prior bindings, macros and profile settings
  (10 levels), including after an accepted import.

## What is NOT protected

- **No allow-listing.** Anything your shell can run, a binding can run.
- **No privilege reduction.** Commands inherit your session's rights — on
  Windows, an elevated ZxCMC runs its actions elevated too. Prefer running
  ZxCMC unelevated.
- **Trigger content is not sandboxed.** `@` actions *are* AutoHotkey code and
  can do anything AutoHotkey can (drive the UI, read files, make network
  requests, modify the config itself).
- **Hotstrings fire on typing.** A broad hotstring trigger (e.g. a common
  word) executes its action whenever you type that text anywhere — an easy
  way to Trojan a shared config subtly.

## Practical guidance

**Before importing or enabling a third-party `keybinds.cfg`:**

1. Open it in a text editor first. It is plain text; `KEY;ACTION` lines, plus
   `hs:`/`px:`/`macro:`/`set:` lines and `[Profile:...]` sections — the full
   grammar is in [CONFIGURATION.md](CONFIGURATION.md#keybindscfg-grammar).
2. Read every action value. `&`, no-prefixed, `run:`/`rw:` = shell command;
   `@` = code. Check for encoded payloads, URL-shortener links, `curl ... | sh`-style one-liners, or actions writing into config
   files.
3. Import through the gate and answer **No** (load disabled), inspect the
   rows, enable selectively.
4. Mind pixel triggers: check that the coordinates and colors are plausible
   and the scope makes sense.

**Operating habits:**

- Keep one profile per context instead of sharing one config across machines;
  export only what you intend to share.
- `@` actions are the sharpest tool available — prefer `&` shell commands for
  anything a third party gave you.
- ZxCMC writes temporary scripts (`ZxCMC_expr_<id>.ahk` in `%TEMP%`) when
  running `@` actions. If you audit temp-file scanning tools, these are
  expected.
- Journal / audit externally if the machine is shared: ZxCMC logs its *own*
  errors to `%APPDATA%\ZxCMC\error.log`, but it does not log the commands it
  executes.

**Trusting a released build:**

- Build artifacts are produced by GitHub Actions directly from this
  repository (see `.github/workflows/build.yml`); a release asset should
  correspond to a tagged commit — check that the tag's workflow run is the
  source of the file you download.
- Verify downloads against the `SHA256SUMS` published with the release, and
  prefer installing Keysharp itself from
  [its releases](https://github.com/keysharp-org/Keysharp/releases) (all of
  which are also checksummed) rather than from any mirror.
- If you need stronger guarantees, compile the two scripts yourself from a
  checkout you have reviewed — building requires only Keysharp and the .NET
  runtime (see the README's *Building* section).

## Reporting

Found a security-relevant defect (for example, a way a config file triggers
execution *earlier* than the import gate, or a parsing bug that hides an
action)? Open an issue describing the trigger path without posting a working
malicious config; a minimal benign reproduction is enough.
