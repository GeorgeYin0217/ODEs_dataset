# Rossler Standard Dataset File Explanation

## Task Summary

This task adds the fixed-parameter Rössler system as a `v1_core` chaotic ODE dataset object. The implemented system is

```text
x_dot = -y - z
y_dot = x + a*y
z_dot = b + z*(x - c)
```

with standard parameters `a = 0.2`, `b = 0.2`, and `c = 5.7`. The dataset uses full-state clean observation, no noise, fixed-step RK4 propagation, burn-in before retained samples, trajectory-level Split-I, and one-step, rollout, and statistics window summaries.

## Run Entry Points And Scripts

- `experiments/smoke_tests/run_rossler_smoke.jl`: minimal end-to-end smoke generation for configuration loading, burn-in integration, full-state observation, split/window summaries, manifest writing, diagnostics, and plot output.
- `experiments/data_generation/generate_rossler_standard_dataset.jl`: standard-scale generation entry point for the reusable `v1_core` Rössler object.

Both scripts include the same reusable source modules from `src/` and differ only by the selected configuration files.

## Core Source, Configs, And Docs Changed

- `src/dynamics/rossler.jl`: defines `RosslerSpec`, configuration parsing, parameter and state validation, the Rössler vector field, divergence expression, fixed-step RK4 stepping, burn-in state advancement, retained trajectory generation, and system metadata.
- `src/generators/rossler_dataset_generator.jl`: implements initial-condition loading for smoke sets and formal grids, raw and observed trajectory generation, split and window summaries, JLD2/JSON/CSV output, plot export, manifest assembly, release-index writing, and run logs.
- `src/diagnostics/rossler_diagnostics.jl`: computes finite-value checks, full-state observation error, coordinate ranges, state norms, velocity norms, RK4 self-residual, step increments, state statistics, divergence statistics, attractor activity checks, split/window count summaries, and smoke/standard pass flags.
- `configs/systems/v1_core/rossler_smoke.json`: smoke-scale system configuration with 6 manual initial conditions, `dt = 0.02`, burn-in `50.0`, and retained length `1500`.
- `configs/systems/v1_core/rossler_standard.json`: standard-scale system configuration with a `4 x 4 x 3` initial-condition grid, 48 trajectories, `dt = 0.02`, burn-in `50.0`, and retained length `4000`.
- `configs/observations/rossler_full_state_clean.json`: full-state, no-noise, no-normalization observation chain.
- `configs/splits/v1_core/rossler_smoke_split_i.json` and `configs/splits/v1_core/rossler_standard_split_i.json`: trajectory-level Split-I definitions.
- `configs/windows/v1_core/rossler_smoke_windows.json` and `configs/windows/v1_core/rossler_standard_windows.json`: one-step, rollout, and statistics window declarations.
- `configs/tasks/v1_core/rossler_smoke_tasks.json` and `configs/tasks/v1_core/rossler_standard_tasks.json`: benchmark task declarations.
- `configs/benchmarks/v1_core/rossler_smoke_benchmark.json` and `configs/benchmarks/v1_core/rossler_standard_benchmark.json`: full benchmark bundles and output policies.
- `configs/releases/rossler_v1_core_release.json`: release-level pointer for the smoke and standard Rössler full-state objects.

## Generated Data, Artifacts, Reports, And Logs

Smoke outputs:

- `data/raw/v1_core/rossler_standard/smoke/rossler_raw.jld2`
- `data/processed/v1_core/rossler_standard/smoke/full_state/rossler_observed.jld2`
- `data/processed/v1_core/rossler_standard/smoke/full_state/rossler_split_I.json`
- `data/processed/v1_core/rossler_standard/smoke/full_state/rossler_windows_summary.json`
- `data/manifests/v1_core/rossler_standard/smoke/rossler_manifest.json`
- `reports/tables/rossler_standard/smoke/`
- `reports/plots/rossler_standard/smoke/`
- `reports/logs/rossler_standard/smoke/run_rossler_smoke.log`

Standard outputs:

- `data/raw/v1_core/rossler_standard/standard/rossler_raw.jld2`
- `data/processed/v1_core/rossler_standard/standard/full_state/rossler_observed.jld2`
- `data/processed/v1_core/rossler_standard/standard/full_state/rossler_split_I.json`
- `data/processed/v1_core/rossler_standard/standard/full_state/rossler_windows_summary.json`
- `data/manifests/v1_core/rossler_standard/standard/rossler_manifest.json`
- `data/releases/v1_core/rossler_standard/rossler_release_index.json`
- `reports/tables/rossler_standard/standard/`
- `reports/plots/rossler_standard/standard/`
- `reports/logs/rossler_standard/standard/generate_rossler_standard.log`

The raw and processed trajectory arrays use the layout `state_dim_by_time_by_trajectory`.

## Script-To-Script Data Flow

1. A run script loads system, observation, split, window, task, and benchmark JSON configs.
2. `rossler_spec_from_config` builds the typed system spec and validates parameter, time, and solver consistency.
3. Initial conditions are read from a manual smoke set or formal grid.
4. Each trajectory is first advanced through burn-in, and only the post-burn-in state is used as the retained trajectory initial state.
5. The fixed-step RK4 generator writes state matrices `X` with shape `3 x (M + 1)`.
6. The full-state observation chain copies `X` into `Z`, preserving orientation and dimensions.
7. Trajectory IDs are split into train, validation, and test groups before window summaries are derived.
8. One-step, rollout, and statistics windows are counted and validated within each split.
9. Raw trajectories, observed trajectories, split JSON, window summary JSON, manifest JSON, diagnostic tables, plots, release index, and log files are written.

## Validation Commands And Results

Smoke validation:

```powershell
julia --project=. experiments/smoke_tests/run_rossler_smoke.jl
```

Result: passed with `smoke_passed = true`, 6 trajectories, retained matrix size `(3, 1501)`, Split-I counts `3 / 1 / 2`, zero full-state observation error, zero RK4 self-residual, and finite state ranges.

Standard validation:

```powershell
julia --project=. experiments/data_generation/generate_rossler_standard_dataset.jl
```

Result: passed with `standard_passed = true`, 48 trajectories, retained matrix size `(3, 4001)`, Split-I counts `34 / 7 / 7`, state ranges approximately `x in [-9.1056, 11.4331]`, `y in [-10.7906, 7.84031]`, `z in [0.0135275, 22.8499]`, mean divergence approximately `-5.34908`, zero full-state observation error, zero RK4 self-residual, and all 48 trajectories marked as active attractor trajectories.
