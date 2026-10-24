# Phillips Machine (MONIAC) — Godot simulation

Hydraulic model of the economy (Bill Phillips, 1949): water = money, the pump lifts national income Y,
tanks for Treasury, idle balances (savings), foreign balances and the expenditure sump.

## Stack
- Godot 4.7, GDScript only, statically typed (`:=`, typed params/returns).
- Viewport 1280×800 (Steam Deck), stretch `canvas_items` + aspect `keep`, `gl_compatibility` renderer.
- Indentation: tabs (Godot default).
- Code comments are in Russian; keep it that way.
- UI is bilingual (ru/en) via `i18n.gd` (`class_name I18n`): write UI strings in Russian wrapped in
  `I18n.t("…")` and add the English to `I18n.EN` (missing keys fall back to Russian). Language:
  `-- --lang=en|ru` launch arg > `user://settings.cfg` > system locale; toggled by L / Select / the language button.
  After adding a new `class_name`, run `godot --headless --path . --import` to refresh the class cache.

## Structure
- `main.tscn` — a single `Control` with `phillips_machine.gd`; the whole UI is built in code.
- `phillips_machine.gd` (`class_name PhillipsMachine`) — layout, sliders, presets, input actions, sampling for the chart.
- `economy.gd` (`class_name Economy`) — the model only, no rendering; tested headless.
- `machine_view.gd` (`class_name MachineView`) — `_draw()` of tanks, pipes with moving dots, valves, labels,
  in design coordinates `DESIGN` (760×760) scaled to the control. Series colours `COL_*` are shared with the chart.
- `chart.gd` (`class_name FlowChart`) — Y, C, I, G over the last `MAX_POINTS` samples.
- `docs/screen_<lang>.png` — README screenshots:
  `godot --path . --write-movie x.png --fixed-fps 10 --quit-after 200 -- --lang=en`, take the last frame.

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
Actions created in `_setup_input()`: `toggle_pump` (Start, P), `toggle_lang` (Select, L),
`speed_down`/`speed_up` (LB/RB, [ ]), `reset_sim` (R).

## Tests
- `tests/run_tests.gd` — headless suite (model, presets, sliders, language, input actions):
  `godot --headless --path . --import` then `godot --headless --path . -s tests/run_tests.gd` (exit 0 = pass).
  Add a check there for every new feature; keep it render-free so it runs in CI.

## CI and releases (GitHub Actions)
- `.github/workflows/ci.yml` — on every PR and push to `main`: Godot 4.7.1 (Linux) + Windows export templates,
  then `.github/scripts/test_and_build.sh`: import → tests → `--export-release "Windows Desktop"`.
- `.github/workflows/release.yml` — when a PR is **merged into `main`**: bumps the version from the latest
  `vX.Y.Z` tag, writes it into `application/config/version`, re-runs tests + export, zips
  `PhillipsMachine.exe` + README, creates tag `vX.Y.Z` and a GitHub Release. First release is `v0.1.0`.

### Release rules for Claude
- Never create tags or releases by hand and never edit `config/version` in `project.godot` — it stays `"dev"`.
- Work on a branch and open a PR into `main`; pick the bump with a PR label:
  `release:major` (incompatible change), `release:minor` (new feature), no label (patch), `release:none` (no release).
  Say in the PR description which bump was chosen and why.
- Run the tests locally before opening a PR.
