# Phillips Machine (MONIAC) — Godot simulation

Hydraulic model of the economy (Bill Phillips, 1949): water = money, the pump lifts national income Y,
tanks for Treasury, idle balances (savings), foreign balances and the expenditure sump.

## Stack
- Godot 4.7, GDScript only, statically typed (`:=`, typed params/returns).
- Viewport 1920×1080, stretch `canvas_items` + aspect `keep` (Steam Deck 1280×800 scales down), `gl_compatibility` renderer.
- Look and layout follow lukyanov_integrator / curt_calculator: fonts `FS_SMALL`/`FS`/`FS_BIG` = 20/24/30, status line
  (FS_BIG, y 44), version on the right, one row of flat menu buttons at `MENU_Y` 62, footer hints + yellow "F1" line,
  right panel at `PANEL_RECT` behind a divider, yellow headers.
- Indentation: tabs (Godot default).
- Code comments are in Russian; keep it that way.
- UI is bilingual (ru/en) via `i18n.gd` (`class_name I18n`): write UI strings in Russian wrapped in
  `I18n.t("…")` and add the English to `I18n.EN` (missing keys fall back to Russian). Language:
  `-- --lang=en|ru` launch arg > `user://settings.cfg` > system locale; toggled by L / Select / the language button.
  A test scans the sources for `I18n.t("…")` (plus `SLIDERS`, `PRESET_BUTTONS`, `MENU`, `TANK_NAMES`) and fails on missing EN keys.
  After adding a new `class_name`, run `godot --headless --path . --import` to refresh the class cache.

## Structure
- `main.tscn` — a single `Control` with `phillips_machine.gd`; the whole UI is built in code.
- `phillips_machine.gd` (`class_name PhillipsMachine`) — layout, menu (`MENU`, `_press_menu(id)`), sliders, presets,
  pause, input actions, sampling for the chart; draws the status line, divider and footer in `_draw()`.
- `help_overlay.gd` (`class_name HelpOverlay`) — F1 / Y manual: shows `docs/pages/<lang>/page_N.png`; while open,
  `PhillipsMachine._input` sends it all non-mouse input (←/→, LB/RB, PgUp/PgDn flip, Home, O opens the PDF, Esc/B/F1/Y close).
- `economy.gd` (`class_name Economy`) — the model only, no rendering; tested headless.
- `machine_view.gd` (`class_name MachineView`) — `_draw()` of tanks, pipes with moving dots, valves, labels,
  in design coordinates `DESIGN` (1160×760) scaled to the control (≈1.09); its font sizes are in design units. Series colours `COL_*` are shared with the chart.
- `chart.gd` (`class_name FlowChart`) — Y, C, I, G over the last `MAX_POINTS` samples.
- `docs/screen_<lang>.png` — README and manual title screenshots:
  `godot --path . --write-movie x.png --fixed-fps 10 --quit-after 200 -- --lang=en`, take the last frame.
- `docs/build_instruction.py` → `docs/instruction_{ru,en}.pdf` (A4 landscape) + `docs/pages/<lang>/page_N.png` (1054 px high).
  Every text is an `L(ru, en)` pair, `f()` formats numbers per language, `FONT_K` = 1.4. Scenario numbers come from
  `class Economy` there — a Python copy of `economy.gd`; keep the two in sync. Section 7 = problems (`problems()`,
  one page each via `problem()`: task, table Quantity / Calculation / On the machine, solution with numbers from
  `trace(changes)` = snapshots after `warmed_up()`); each must fit on one page — check the PNGs after edits. After changing the model, presets or the
  screen, retake the screenshots, rerun `python docs/build_instruction.py` (`pip install reportlab pypdfium2`), then
  `godot --headless --path . --import`. CI does not regenerate them (needs Windows fonts).

## Model
- Stocks: `sump`, `treasury`, `idle`, `foreign`; total `TOTAL_WATER` (1000) is conserved exactly — every
  flow is debited from one tank and credited to another. Keep it that way; a test checks it.
- `Y = PUMP_K · sump`; `T = t·Y`, `Yd = Y − T`, `S = s·Yd`, `M = m·Yd`, `C = Yd − S − M` (if s + m > 1, Yd is split
  between S and M). Outflows: `G = g`, `I = INV_MAX·exp(−INV_R_SENS·r)`, `X = x`, each × `_choke(level)` and
  capped by what is in the tank.
- Explicit Euler, sub-stepped to `MAX_DT` (0.1 s).
- Sanity check: with full tanks, Y → `(G + I + X) / (1 − (1 − t)(1 − s − m))` (`equilibrium_y()`).

## Controls
Focus navigation (D-pad / left stick / arrows / Tab), ←/→ on a slider = 1/40 of its range, A/Enter presses.
Actions created in `_setup_input()`: `toggle_pause` (X, Space — handled in `_input` before the GUI), `toggle_help` (Y, F1),
`toggle_pump` (Start, P), `toggle_lang` (Select, L), `speed_down`/`speed_up` (LB/RB, [ ]), `reset_sim` (R), `open_pdf` (O).

## Tests
- `tests/run_tests.gd` — headless suite (model, presets, sliders, menu, pause, manual pages/PDFs, language, translations):
  `godot --headless --path . --import` then `godot --headless --path . -s tests/run_tests.gd` (exit 0 = pass).
  Add a check there for every new feature; keep it render-free so it runs in CI.

## CI and releases (GitHub Actions)
- `.github/workflows/ci.yml` — on every PR and push to `main`: Godot 4.7.1 (Linux) + Windows export templates,
  then `.github/scripts/test_and_build.sh`: import → tests → `--export-release "Windows Desktop"`.
- `.github/workflows/release.yml` — when a PR is **merged into `main`**: bumps the version from the latest
  `vX.Y.Z` tag, writes it into `application/config/version`, re-runs tests + export, zips
  `PhillipsMachine.exe` + both PDFs + README, creates tag `vX.Y.Z` and a GitHub Release. First release is `v0.1.0`.

### Release rules for Claude
- Never create tags or releases by hand and never edit `config/version` in `project.godot` — it stays `"dev"`.
- Work on a branch and open a PR into `main`; pick the bump with a PR label:
  `release:major` (incompatible change), `release:minor` (new feature), no label (patch), `release:none` (no release).
  Say in the PR description which bump was chosen and why.
- Run the tests locally before opening a PR.
