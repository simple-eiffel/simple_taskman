# Intent v3: simple_taskman

Date: 2026-10-06. Supersedes the scope of intent-v2.md. Phase 1 ("See it
move") was accepted under v2 and is not repeated here. The v2 deep review
(Q1-Q11) still holds wherever this document does not change it.

Proposal reviewed by Larry: https://claude.ai/artifact/1rtj2RUWrihGKXwu9ZA8ct
(parity table, tools, nine concept screens, roadmap, four decisions).

## What

A full replacement for the Windows Task Manager, plus tools it does not have,
plus displays that show what the machine did, is doing, and is about to do.

1. **Parity:** every tab and action of Windows Task Manager, including
   opening on Ctrl+Shift+Esc.
2. **Past:** a recorder that every view can scrub back through, with slowdowns
   bookmarked.
3. **Present:** one sentence naming the bottleneck and the culprit, with
   evidence, or an honest "can't tell" with the reason.
4. **Future:** forecasts (memory runway, disk-full date, leak suspects) that
   show how sure they are.
5. **Tools:** restraint with proof and exact undo, hang doctor, port map,
   file-lock finder, real startup cost, compare two moments, case file,
   alerts, optional local narration.

The v2 principles stay: missing is never zero, a pid is not an identity, and
the monitor must not become the problem.

## Why

Larry, 2026-10-06: "simple_taskman needs to be a full-on replacement++ for the
Windows Task Manager. That's the goal." Plus: "new tools and really amazing GUI
presentations that WOW the user", covering "past, present, predictable future".

## Decisions (Larry, 2026-10-06: "I take your recommendations")

| ID | Question | Decision |
|----|----------|----------|
| D-1 | Run as administrator? | Start without admin rights. Offer "Show everything (restart as admin)", as Process Explorer does. Without admin, the affected features stay visible and state the reason, the way the capability panel already does. |
| D-2 | Scope lifts | Allowed: command lines, full image paths, window titles, user names, and actions on processes (end, end tree, priority, affinity, efficiency mode, dump). Kept on this PC only; left out of case files and exports unless the owner includes them. Still refused: actions on protected system processes. Still out: handle and DLL browsing, except the file-lock finder (Restart Manager). |
| D-3 | Order | Recorder first ("Remember"), then everyday parity ("Daily driver"), then diagnosis, forecasts, and the remaining parity and tools. |
| D-4 | Window cost | Measured on JACKJACK, 2026-10-06, two minutes each, same counter (`\Process(*)\% Processor Time`, 1 s samples), window visible, normal update speed: Windows Task Manager **8.01% avg, 13.90% max of one logical processor, 127 MB private**; taskman lean **4.86% avg, 9.26% max, 31 MB**. Limit: taskman's whole-process cost stays at or below Task Manager's on the same PC at the same update speed. "Repaint only what changed" in simple_widgets comes before the large visuals. |

## Phases and acceptance criteria

### Phase 1: See it move (accepted 2026-10-06)
Evidence: evidence/phase1-spike-o2.txt.

### Phase 2: Remember
- [ ] Recorder writes frames to SQLite in the owner's profile (`TM_PATHS.trace_folder`), schema of spec 04 "Recorder Design".
- [ ] One writer per user (named mutex); a second instance opens the file read-only and says so.
- [ ] Retention tiers (1 s for 1 h, 10 s for 24 h, 60 s for 30 days), size cap, pinned frames never merged or deleted.
- [ ] Replay of a recorded window reproduces the recorded frames (codec round trip through the store).
- [ ] After the stress tool exits, the scrubber shows its load and its process.
- [ ] DVR: a scrub control moves every view (grid, heatmap, tiles) to a recorded moment and back to live.
- [ ] Soak: database at or under 250 MB and writes at or under 20 MB per hour, measured.
- [ ] Window cost within D-4 while recording.
- [ ] (SHOULD) `taskman_recorder` records with no window open; the window views its file.
- [ ] (SHOULD) Process lifelines view over the recorded hour.

### Phase 3: Daily driver (parity I)
- [ ] Processes: grouped as apps, background, Windows; family roll-up; CPU, memory, disk, GPU columns; search.
- [ ] Process actions: end task, end tree, efficiency mode, priority, affinity, open file location, properties, create dump, each with a reason when refused.
- [ ] Details page with the Task Manager columns that need no admin; the rest state "needs admin".
- [ ] Performance pages: CPU (graphs, kernel time, speed, topology, uptime), memory (composition, pools), disk (active and response time, throughput), network adapters, GPU engines and memory.
- [ ] Settings: update speed (high, normal, low, paused), always on top, start page, theme; stored with simple_toml.
- [ ] Admin mode: "restart as admin" works; Ctrl+Shift+Esc switch is opt-in, reversible, and admin-only.
- [ ] Gate: Larry uses taskman instead of Task Manager for a week.

### Phase 4: Diagnose
As v2 Phase 3 (rules, verdict banner, evidence; three scenarios three of three, live and scrubbed back), plus the cockpit rings, memory map, and disk flow views.

### Phase 5: Look ahead
- [ ] Memory runway and disk-full forecasts with a stated confidence; leak suspects by private-bytes slope.
- [ ] Normal band per hour of week from the recorder; week heat map; alerts through a tray notification.
- [ ] Each forecast is replayed against recorded history and its error is measured and shown.

### Phase 6: Parity II and tools
Services, Startup apps with measured impact, Users, App history from the
recorder; restraint with proof and exact undo (v2 P4); hang doctor; port
map; file-lock finder; compare two moments; case file; optional local
narration.

## Out of scope (revised)

- Kernel drivers, and therefore CPU temperature on this machine
- A Windows service (the headless recorder is a per-user process)
- macOS and Linux
- Malware detection; handle and DLL browsing (except the file-lock finder); stack inspection
- Benchmark suite and score
- Fan control, overclocking, RGB
- Actions on protected system processes
- Restraint without the owner asking
- Sending any data off the PC (NFR-008)

## Privacy (D-2)

Command lines, paths, window titles, and user names are recorded only when the
owner turns on "record details" (default off for the recorder, on for the live
view). Exports and case files leave them out unless the owner includes them
for that export. Nothing leaves the PC.

## New and changed NFRs

| ID | Requirement | Measure | Target |
|----|-------------|---------|--------|
| NFR-010 | Window cost | Whole-process CPU, % of one logical processor, normal speed | At or below Windows Task Manager on the same PC (8.01% on JACKJACK, 2026-10-06) |
| NFR-011 | Window memory | Private bytes, live view | At or below Windows Task Manager (127 MB on JACKJACK) |
| NFR-007 | Privilege (unchanged) | Rights for MUST features | Standard user; admin-only features say so |

## Upstream work this plan depends on

| Library | Item |
|---------|------|
| simple_widgets | Repaint only what changed (dirty regions), before the large visuals (D-4) |
| simple_widgets | Stacked area chart; forecast band on the line chart; gaps in sparklines (W-1) |
| simple_logger | Close the file handle (W-7) |
| simple_mml | Bulk creator for known-unique lists (W-11) |

## Dependencies (additions)

simple_sql (Phase 2); simple_toml, simple_registry (Phases 3 and 6);
simple_statistics (Phase 5); simple_ai_client (Phase 6, optional).
