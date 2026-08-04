# vphone Workstation (`vphone-ws`) — Design Spec

**Status:** Approved design, pre-implementation
**Date:** 2026-07-30
**Grounded on:** `vphone-cli` `main @ 966bddb` ("setup: Record iOS + cloudOS versions on restore")
**Location:** `~/dev/vphone-ws` (standalone repo; independent of `vphone-cli`)

---

## 1. Summary

`vphone-ws` ("vphone Workstation") is a native macOS GUI for managing virtual iPhones, in the spirit of UTM / VirtualBox / VMware Workstation but purpose-built for the `vphone-cli` toolchain. It is a **separate, standalone SwiftUI macOS app** that drives everything by shelling out to the existing `vphone-cli` binary. It performs no virtualization itself and therefore needs **none** of the private entitlements `vphone-cli` requires.

The product goal: a **user-friendly, non-threatening** manager for an audience (security researchers) used to a terminal-adjacent workflow — approachable on the surface, precise underneath.

### Goals
- One window to see every VM, its live status, and its details.
- Start / stop VMs; the live iPhone screen opens in `vphone-cli`'s own window.
- Create a VM end-to-end through a guided wizard over the full `vm create` pipeline.
- Edit the settings the VM config supports (CPU, memory, network).
- Clone / rename / delete / export / import VMs.
- Guide the user through host prerequisites so launches don't fail cryptically.

### Non-goals (v1) — see §12
Embedding the iPhone screen in-app; snapshots; disk resize; in-app device control (tap/type/screenshot).

---

## 2. Key constraints (why the architecture is what it is)

These are verified facts about `vphone-cli` on `main @ 966bddb`; the design follows from them.

1. **The VM, its vsock channel, and its display are owned by one process.** `vphone-cli`'s boot process creates the `VZVirtualMachine`, binds it to a `VZVirtualMachineView`, and opens the vsock control channel — all in-process (`VPhoneAppDelegate.swift:76-96`, `VPhoneWindowController.swift:27-33`). Virtualization.framework can only render a VM living in the same process. **Consequence:** `vphone-ws` cannot render the iPhone screen; it launches `vphone-cli`, which opens its own window. This is also what keeps `vphone-ws` entitlement-free.

2. **Entitlements attach to the `vphone-cli` binary and are validated per-exec.** When `vphone-ws` spawns `vphone-cli`, the child is the signed, entitled process that calls Virtualization.framework; the GUI never holds VZ handles and needs no special signing to *launch* it. Entitlements do not propagate across `exec`.

3. **The VM library is a flat directory model.** VMs live at `~/.vphone/VMs/<name>/` (override `$VPHONE_LIBRARY_ROOT`); a directory is a VM iff it contains `config.plist` (`VPhoneLibrary.swift:44-65`).

4. **`vm list --json` / `vm info --json` are the machine-readable contract.** They emit a `VPhoneBundleReport`: `name`, `cpuCount`, `memoryMB`, `diskSizeBytes`, and (as of `966bddb`) `restoreInfo` (`VPhoneBundleReport.swift:5-16`).

5. **Running/stopped state is not in the JSON.** It is derived by checking who holds the disk image open: `lsof -t -- <bundle>/Disk.img` (non-empty ⇒ running), exactly as `vm stop` does (`VPhoneVMLaunchCLI.swift:106-110`).

6. **iOS + cloudOS versions are persisted; the patch variant is not.** `restore-info.json` at the bundle root records both OS versions and survives `export`; but no field anywhere records the variant (regular/dev/jb/exp/less) — it is a transient `-V` flag only (see §5.3).

7. **Several CLI commands are long-running and/or privileged**, and some default to interactive prompts that hard-fail off a TTY (§5.4, §7). The GUI must always pass explicit names and non-interactive flags.

---

## 3. Architecture

`vphone-ws` is a thin, decoupled GUI over the `vphone-cli` **contract** (its JSON output, exit codes, and documented subcommands). It does **not** link `vphone-cli`'s Swift code (`VPhoneCore`), so a `vphone-cli` internal refactor cannot break the GUI as long as the contract holds.

```
SwiftUI views  ──bound to──▶  Observable models  ──use──▶  Services  ──exec──▶  vphone-cli
                                (VMStore, …)                (CLIClient, TaskEngine, …)
```

### Service layer

| Service | Responsibility |
|---|---|
| `VPhoneCLIClient` | Locate and invoke the `vphone-cli` binary. One typed async method per subcommand. Decodes `--json`. Always passes explicit names + non-interactive flags. |
| `VMStore` (`@Observable`) | The library: VM list from `vm list --json`, enriched with live running-state (batched `lsof`) and variant (app sidecar). Polls on a timer. |
| `TaskEngine` / `TaskConsole` | Runs long/privileged commands as tracked child `Process`es. Streams output, parses stage banners, supports cancel, reports success/failure from exit code. |
| `HostReadiness` | Runs prerequisite checks; maps failures to friendly fix cards. |
| `LaunchCoordinator` | Start/stop/show-window lifecycle; keeps UI state in sync with `lsof` truth. |
| `VariantStore` | App-owned sidecar recording the variant a VM was created/patched with (since the CLI doesn't persist it). |

Each service has one job and a clean seam. `VPhoneCLIClient` and `TaskEngine` are the extensibility points: new CLI verbs become new typed methods or new task types without touching the views.

---

## 4. Binary discovery & invocation

- **Locate** `vphone-cli` via, in order: a user-set path (Preferences), `which vphone-cli` / `$PATH` (Homebrew symlink), then a bundle chosen by the user (`…/vphone-cli.app/Contents/MacOS/vphone-cli`).
- **Invoke in place.** Never copy the bare binary out of its bundle — it self-locates its bundled `Contents/Resources/scripts`, `vphoned.signed`, and tools from its own executable path (`VPhoneResources.swift:19-48`). A copied binary loses those.
- **Not found / wrong version** → a friendly setup card (part of Host Readiness, §6.5), not a crash.
- All invocations pass `--library-root` explicitly when the user has chosen a non-default library, and always pass explicit VM **names** (never rely on the interactive picker, which throws off a TTY — `VPhoneVMSelection.swift`).

---

## 5. Data model

### 5.1 VM record (from `vm list --json` → `VPhoneBundleReport`)
```
name: String
cpuCount: Int
memoryMB: Int
diskSizeBytes: Int64
restoreInfo: { ios: {version, build}, cloudOS: {version, build} }?   // may be null
```

### 5.2 Running state (computed, not from JSON)
Batched `lsof -t -- <bundle>/Disk.img` across all VMs on a ~2s timer while the window is active; a VM is **Running** iff its disk image has an open holder. Correct even for VMs started outside the app.

### 5.3 Versions vs. variant
- **iOS + cloudOS**: read directly from `restoreInfo`. No plist parsing in `vphone-ws` — the CLI already reads `restore-info.json` (or back-derives from the restore plists) and the file survives `export`. This replaces any reliance on the `*_Restore/` folder.
- **Variant**: not persisted by the CLI. `VariantStore` records the variant when the **wizard** creates/patches a VM, in an app-owned sidecar (e.g. `~/.vphone/VMs/<name>/.vphone-ws.json`, or an app-scoped store keyed by VM identity). VMs created outside `vphone-ws` display variant **"Unknown."** If upstream later adds `variant` to `restore-info.json`, `VMStore` should prefer that and the sidecar becomes redundant.

### 5.4 Non-interactive invocation rules (contract compliance)
- Always pass explicit `<name>` (picker throws off a TTY).
- `vm delete` → `--force` (else it prompts on stdout).
- `vm rename` / `vm clone` → pass **both** names.
- Prefer `--json` on `list`/`info`.
- Long/streamed commands: capture stdout+stderr; success/failure from the child **exit code** (propagated via `ExitCode`), not log scraping.

---

## 6. UI specification

Five surfaces. Visual mockup accompanies this spec (screen gallery). Design language in §10.

### 6.1 Main window — the library
- **Sidebar:** searchable VM list. Each row: iPhone glyph, name, a status dot (green running / gray stopped), and a mono subtitle `iOS <v> · cloudOS <v>`. Footer "New VM…".
- **Detail pane:** selected VM's name + status pill + bundle path; a primary action (**Start** when stopped / **Stop** when running) plus **Show screen**, **Settings**, **Clone**, and an overflow (Rename, Export, Show in Finder, Delete).
- A one-line callout explains that the iPhone screen opens in its own window (sets expectations; prevents hunting for an embedded display).
- A single **Overview** box: iOS, cloudOS, Variant, CPU, Memory, Disk, Network, Device, UDID.
- **Toolbar:** New VM; Start/Stop; a **Host status pill** ("Host ready" / "N items need attention") opening Host Readiness (§6.5).

### 6.2 VM settings (sheet)
- **Editable:** CPU cores, Memory, Network mode (NAT / Bridged / Host-only / None).
- **Read-only ("Fixed at build time"):** Disk size, Display (native panel resolution), Device model.
- Editable only while the VM is **stopped**; changes take effect on next boot (the VZ config is assembled fresh each launch). Save writes via `vphone-cli vm config` — the app never edits `config.plist` directly.
- **Graceful degradation:** if the installed `vphone-cli` lacks `vm config --network` (§9), the Network control is shown disabled with a tooltip ("requires a newer vphone-cli"), while CPU/memory remain editable.

### 6.3 Create-VM wizard (sheet)
Four steps: **Name → iOS & variant → Resources → Review & create**.
- **Name:** validated (non-empty, no `/`, no leading `.` — `VPhoneBundleOps.requireValidName`); rejects an existing bundle name up front.
- **iOS & variant:** variant cards (less/regular/dev/jb/exp) with plain-language descriptions and a security-level meter; two source fields — **iOS (userland)** → `--iphone-source`, **cloudOS (kernel)** → `--cloudos-source` — each offering "download version X" or "choose an .ipsw".
- **Resources:** CPU / memory / disk size (create-only; `vm new` defaults 8 / 8192 / 64).
- **Review:** states plainly that it downloads multi-GB IPSWs, will ask for **authentication once** (native dialog, §8), and takes several minutes. Blocks early on a nested-VM host (`kern.hv_vmm_present == 1`), matching the CLI's own guard.
- **Create** hands off to the Task console running `vphone-cli vm create <name> -V <variant> --iphone-source … --cloudos-source … --elevate gui` and records the chosen variant in `VariantStore`.

### 6.4 Task console
- One panel for all long/privileged operations (create, restore, cfw install, fw prepare, export, import).
- Per task: title, status pill, elapsed time, **stage chips** parsed from the CLI's `=== … ===` banners (`VPhoneCreateOrchestrator.swift`), a live terminal log (raw stream, `[*]/[+]/[-]/[!]` markers colorized), and **Cancel** (forwards `SIGINT` to the child; the CLI already handles it).
- Success/failure from the child's exit code.
- Recently-finished tasks collapse to a one-line summary.

### 6.5 Host readiness (sheet)
Front-runs the prerequisites that otherwise cause a cryptic `zsh: killed`. Checks, each with a plain-English explanation and a one-click action or exact command:
- Apple Silicon + macOS 15+.
- Not running inside a VM (`sysctl kern.hv_vmm_present == 0`).
- SIP relaxed for research guests (`csrutil` / `allow-research-guests`).
- AMFI relaxed **and amfidont running** — with the explicit note that amfidont is a daemon that must **stay running** (never kill it).
- `vphone-cli` found (+ version).

Checks reuse the CLI's own `boot_host_preflight.sh` where possible, plus direct `sysctl`/`csrutil` reads, so app and CLI never disagree about bootability.

---

## 7. Interaction flows

- **Launch (handoff):** Start → spawn `vphone-cli vm launch <name>` as a tracked child. `vphone-cli` runs its preflight gate, then opens the iPhone in its own window. The `lsof` poll flips the VM to Running. **Show screen** brings that window forward.
- **Stop:** `vphone-cli vm stop <name>` (SIGINT → wait `--timeout` → SIGKILL). Poll flips to Stopped. Quitting the VM window directly is detected by the same poll.
- **Create / Restore / CFW / Prepare / Export / Import:** run through the Task console (§6.4). `create` and `cfw install` are privileged (§8).
- **Clone / Rename / Delete:** map 1:1 to CLI subcommands with explicit names; Delete confirms in-GUI then calls `--force`.

---

## 8. Privilege / elevation model (native authentication)

The one privileged step is the CFW host-mount (`mount_apfs` + `chown 0:0`) inside `cfw_install_host.sh`, reached by `vm create` and `cfw install`.

**Requirement:** authenticate through **macOS's native authentication dialog** (the standard "wants to make changes" system prompt, Touch ID where available). The password must never be typed into `vphone-ws`, placed on any command line, or written to a log.

**Why this is not the existing `--sudo-password`:** that value sits in `vphone-cli`'s argv, readable by any user via `ps`. The current askpass path (`sudo -A` + `SUDO_ASKPASS` + `SUDO_PASSWORD` env — `VPhoneCreateOrchestrator.swift:174-286`) keeps it off *sudo's* argv but still requires the app to hold the password. The native dialog avoids a password entirely.

**Mechanism:** the native dialog is driven by macOS **Authorization Services**, which runs the privileged command **as root itself** and returns no password — so it **replaces** sudo for that step rather than feeding it. `vphone-ws` invokes `vphone-cli … --elevate gui` (§9) and never handles a credential.

- **Live output** is preserved by redirecting the elevated step to a log file that `vphone-ws` tails into the Task console (Authorization Services / `osascript` returns output only on completion; the exit status still propagates).
- **Ownership restore:** with no `sudo`, there is no `SUDO_USER`; the elevated step must be told the invoking user another way so `cfw_install_host.sh:96-99` can `chown -R` artifacts back (§9).

Heavier alternative (documented, not chosen): an **SMAppService** privileged XPC helper — canonical, streams over XPC, but needs Developer-ID signing/notarization of app + helper. Overkill for v1 in a SIP-relaxed research context; possible v2 upgrade.

---

## 9. Required `vphone-cli` changes (interface contract)

These are **prerequisites in the `vphone-cli` repo**, to be implemented in a **separate session** (this session stays on `vphone-ws`). Documented here as the contract `vphone-ws` codes against; `vphone-ws` degrades gracefully when they are absent.

### 9.1 `--elevate gui` on `vm create` and `cfw install`
- When set, the CFW host-mount step is elevated via macOS Authorization Services (e.g. `osascript -e 'do shell script "…" with administrator privileges'`) instead of `sudo -A`; shows the native auth dialog; runs the script as root.
- Mutually exclusive with `--sudo-password`; needs no password.
- Because there is no `SUDO_USER`, pass the invoking user to the elevated script (env var e.g. `VPHONE_OWNER`, or an arg) so its ownership-restore (`cfw_install_host.sh:96-99`) still runs.
- Redirect the elevated step's stdout/stderr to a caller-readable log file (the caller tails it); propagate the real exit status.

### 9.2 `vm config --network <nat|bridged|hostOnly|none>` — IMPLEMENTED
- Updates `networkConfig.mode` in `config.plist` via `VPhoneBundleOps.updateConfig`.
- A companion `--mac <addr>` was attempted but **removed**: setting a custom MAC broke VM networking. **`--mac` does not currently exist** and is deferred until a fix is found — so vphone-ws Settings edits network *mode* only, never the MAC.
- The mode persists but has **no runtime effect at boot** until the bridged-networking VZ backend (branch `pr388-rework`, not yet merged to `main`) lands — `main` still hardcodes NAT.

Graceful degradation: both `--root-popup` (§9.1) and `vm config --network` are implemented in `vphone-cli`; if a user has an older build lacking either, vphone-ws surfaces a clear message and disables the dependent control ("requires a newer vphone-cli").

---

## 10. Design language

Inherits the vphone toolchain's flat, precise, dark-neutral identity (per `vphone-cli` `CLAUDE.md` Design System), softened for approachability.

- **Color:** cool near-black ground (`#101216`) biased toward the accent; flat surfaces, 1px borders. One accent — systemBlue (`#5b9bff` dark / `#2f6fe0` light). Semantic status kept **separate** from the accent: green (running/ready), amber (attention), red (critical). Full light + dark themes.
- **Type:** SF Pro (`-apple-system`) for UI and copy — friendly, native; SF Mono reserved for logs, paths, and technical values — the research-instrument texture. The pairing is the thesis: friendly face, technical soul.
- **Voice:** plain-English status before technical detail; every privileged/destructive/slow step is explained, never silent; errors say what went wrong and how to fix it.

---

## 11. Error handling & edge cases
- **Nested-VM host:** block create/launch with an explanation (mirrors CLI's `kern.hv_vmm_present` guard).
- **Name collision:** wizard validates before running `vm create`.
- **amfidont not running / killed mid-session:** Host Readiness surfaces it; never offer to kill it.
- **`vphone-cli` missing / too old:** setup card; disable dependent controls with tooltips.
- **Malformed bundle:** the CLI reports skipped bundles on stderr (`vm list`); surface these as a non-blocking notice rather than dropping them silently.
- **Interactive prompt hazards:** avoided by the §5.4 rules; if a command unexpectedly blocks on stdin, the task times out with a clear message.

---

## 12. Out of scope (v1) & roadmap
- **Embedding the iPhone screen** — impossible without major `vphone-cli` changes (in-process VZ binding). The `vphone.sock` control channel (`~/.vphone/VMs/<name>/vphone.sock`; tap/type/screenshot) is the future door if in-app control is ever wanted; `vphone-mcp` already covers that use case.
- **Snapshots** — no CLI support.
- **Disk resize** — create-only; not `vm config`-editable.
- **In-app device control** (location sim, file browser, IPA install, battery, keys) — these live in `vphone-cli`'s own VM window today.

---

## 13. Testing strategy
- **Service unit tests:** JSON decoding of `vm list/info --json` (incl. null `restoreInfo`), `lsof` output parsing, stage-banner parsing, variant-sidecar round-trip — all with fixtures, no live VMs.
- **CLIClient contract tests:** assert exact argv assembled per action (explicit names, `--force`, `--json`, `--elevate gui`), using a fake runner.
- **Manual / device-verified:** launch handoff, create pipeline end-to-end, native auth dialog, Settings write-through, Host Readiness against a mis-configured host.

---

## 14. Open questions
None blocking. To revisit during implementation: exact `VariantStore` location (per-bundle sidecar vs. app-scoped store); whether Host Readiness offers a one-click "Start amfidont" (needs the bundled helper path) vs. copy-command only.
