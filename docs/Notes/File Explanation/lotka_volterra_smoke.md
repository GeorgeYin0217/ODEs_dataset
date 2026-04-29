# Lotka-Volterra Smoke File Explanation

## Task summary

This task adds the first runnable smoke workflow for the `v1_core` `lotka_volterra`
system. The smoke dataset uses the standard two-dimensional predator-prey ODE,
fixed parameters, positive manual initial conditions, fixed-step RK4 propagation,
and clean full-state observation.

## Run entry points and scripts

- `experiments/smoke_tests/run_lotka_volterra_smoke.jl`: smoke entry point.
- Validation command:
  `julia --project=. experiments/smoke_tests/run_lotka_volterra_smoke.jl`

The script prints dimensions, split and window counts, state ranges, positivity,
full-state observation error, RK4 self residual, and invariant drift.

## Core source, configs, and docs changed

- `src/dynamics/lotka_volterra.jl`: system spec, parameter and positive-state
  validation, vector field, positive equilibrium, Jacobian, invariant, local
  frequency, and fixed-step RK4 propagation.
- `src/diagnostics/lotka_volterra_diagnostics.jl`: positivity, finite-value,
  state-range, vector-field scale, RK4 residual, full-state observation, and
  invariant drift diagnostics.
- `src/generators/lotka_volterra_dataset_generator.jl`: config-driven smoke
  generation, full-state observation, trajectory split, window summary, JLD2
  save, manifest write, diagnostics table, plots, and log.
- `configs/systems/v1_core/lotka_volterra_smoke.json`: smoke system config.
- `configs/observations/lotka_volterra_full_state_clean.json`: full-state clean
  observation config.
- `configs/splits/v1_core/lotka_volterra_smoke_split_i.json`: trajectory-level
  Split-I smoke split.
- `configs/windows/v1_core/lotka_volterra_smoke_windows.json`: one-step,
  rollout, and statistics window declarations.
- `configs/tasks/v1_core/lotka_volterra_smoke_tasks.json`: smoke task group.
- `configs/benchmarks/v1_core/lotka_volterra_smoke_benchmark.json`: smoke
  benchmark and output routing.

## Generated data, artifacts, reports, and logs

- `data/raw/v1_core/lotka_volterra/smoke/full_state_clean/raw_trajectories.jld2`
  stores raw state tensors with layout `state_dim_by_time_by_trajectory`.
- `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/observed_trajectories.jld2`
  stores clean full-state observed tensors.
- `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/splits.json`
  stores the trajectory-level train / val / test split.
- `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/windows_summary.json`
  stores one-step, rollout, and statistics window counts.
- `data/manifests/v1_core/lotka_volterra/smoke/full_state_clean/manifest.json`
  stores generation metadata and diagnostics.
- `reports/v1_core/lotka_volterra_smoke/tables/diagnostics.csv` stores the
  human-readable smoke diagnostics row.
- `reports/v1_core/lotka_volterra_smoke/plots/` contains time-series, phase
  portrait, and invariant-drift PNGs.
- `reports/v1_core/lotka_volterra_smoke/logs/smoke.log` records the smoke summary.

## Script-to-script data flow

The smoke script loads benchmark, system, observation, split, window, and task
configs. It builds raw trajectories through `src/dynamics/lotka_volterra.jl`,
applies `src/observations/full_state.jl`, creates trajectory-level splits and
window summaries through the shared split/window modules, then writes data,
manifest, reports, and plots through the Lotka-Volterra generator.

## Validation commands and results

Command run:

```text
julia --project=. experiments/smoke_tests/run_lotka_volterra_smoke.jl
```

Result:

- `smoke_passed: true`
- state tensor for each trajectory: `(2, 1601)`
- trajectories: `5`
- split counts: `3 / 1 / 1`
- one-step counts: train `4800`, val `1600`, test `1600`
- state range `x`: `[1.92544, 4.415]`
- state range `y`: `[0.785538, 2.55426]`
- full-state observation error max: `0.0`
- RK4 self residual max: `0.0`
- invariant max absolute drift: `8.782819e-11`
- invariant max relative drift: `1.031112e-10`
