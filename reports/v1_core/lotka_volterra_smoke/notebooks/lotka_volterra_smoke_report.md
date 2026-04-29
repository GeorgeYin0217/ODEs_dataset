# Lotka-Volterra Smoke Report

## What was done

Added a first runnable smoke workflow for the `v1_core` `lotka_volterra` system.
The workflow uses fixed parameters
`alpha = 1.5`, `beta = 1.0`, `gamma = 3.0`, `delta = 1.0`, five positive initial
conditions, `dt = 0.005`, and `1600` steps.

## What ran

```text
julia --project=. experiments/smoke_tests/run_lotka_volterra_smoke.jl
```

## Key results

- Smoke status: passed.
- Raw and observed matrices use `state_dim x time_index`, with first trajectory
  size `(2, 1601)`.
- Full dataset tensor layout is `state_dim_by_time_by_trajectory`.
- Split-I smoke counts are train / val / test = `3 / 1 / 1` trajectories.
- One-step sample counts are train `4800`, val `1600`, test `1600`.
- Rollout window counts are available for horizons `50` and `200`.
- Statistics windows use horizon `200`.
- All states stayed in the positive quadrant.
- Full-state observation error was exactly `0.0`.
- Maximum relative invariant drift was approximately `1.031112e-10`.

## Outputs

- Manifest:
  `data/manifests/v1_core/lotka_volterra/smoke/full_state_clean/manifest.json`
- Diagnostics table:
  `reports/v1_core/lotka_volterra_smoke/tables/diagnostics.csv`
- Plots:
  `reports/v1_core/lotka_volterra_smoke/plots/smoke_time_series.png`,
  `reports/v1_core/lotka_volterra_smoke/plots/smoke_phase_portrait.png`, and
  `reports/v1_core/lotka_volterra_smoke/plots/smoke_invariant_drift.png`

## Next manual step

Review the smoke outputs and confirm whether to proceed to the formal
orbit-family configuration and generation entry point.
