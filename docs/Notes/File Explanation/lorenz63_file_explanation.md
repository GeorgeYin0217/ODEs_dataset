# Lorenz63 Dataset Workflow File Explanation

## Task summary

This task adds the Lorenz '63 system to `ODEs_dataset` as a `v1_core`
chaotic benchmark with full-state identity observation. The implemented
workflow covers a minimal smoke run and a standard dataset generation run.

The system uses the standard parameters `sigma = 10`, `rho = 28`, and
`beta = 8/3`. All trajectories are integrated with fixed-step RK4, first
through a burn-in interval and then through the retained sampling interval.
The retained state after burn-in is the first state stored in each raw
trajectory object.

## Run entry points and scripts

- `experiments/smoke_tests/run_lorenz63_smoke.jl`
  - Generates the small smoke dataset.
  - Uses 6 pre-burn-in initial conditions, `dt = 0.01`, `burn_in_time = 5.0`,
    and `trajectory_length = 1200`.
  - Checks integration, burn-in separation, full-state observation, Split-I,
    window counts, diagnostics, plots, and manifest writing.

- `experiments/data_generation/generate_lorenz63_standard_dataset.jl`
  - Generates the standard dataset.
  - Uses a 48-point pre-burn-in initial-condition grid, `dt = 0.01`,
    `burn_in_time = 10.0`, and `trajectory_length = 4000`.
  - Produces the standard raw and observed trajectory files, Split-I indices,
    window summaries, manifest, diagnostic tables, and plots.

## Core source, configs, and docs changed

- `src/dynamics/lorenz63.jl`
  - Defines `Lorenz63Spec`, config parsing, validation, vector field,
    Jacobian, divergence, equilibria, fixed-step RK4 propagation, burn-in
    support, and metadata.

- `src/generators/lorenz63_dataset_generator.jl`
  - Builds manual smoke and standard grid initial-condition ensembles.
  - Runs burn-in and retained trajectory integration.
  - Applies full-state observation through the shared observation object.
  - Builds trajectory-level Split-I and one-step, rollout, and statistics
    window summaries.
  - Saves raw, observed, split, window, manifest, diagnostic table, plot, and
    report-table outputs.

- `src/diagnostics/lorenz63_diagnostics.jl`
  - Computes finite-value checks, state ranges, state statistics, divergence,
    equilibrium residuals, Jacobian traces and determinants, wing-switch
    diagnostics, split and window counts, and pass/fail gates.

- `configs/systems/v1_core/lorenz63_smoke.json`
- `configs/systems/v1_core/lorenz63_standard.json`
- `configs/observations/lorenz63_full_state_clean.json`
- `configs/splits/v1_core/lorenz63_smoke_split_i.json`
- `configs/splits/v1_core/lorenz63_standard_split_i.json`
- `configs/windows/v1_core/lorenz63_smoke_windows.json`
- `configs/windows/v1_core/lorenz63_standard_windows.json`
- `configs/tasks/v1_core/lorenz63_smoke_tasks.json`
- `configs/tasks/v1_core/lorenz63_standard_tasks.json`
- `configs/benchmarks/v1_core/lorenz63_smoke_benchmark.json`
- `configs/benchmarks/v1_core/lorenz63_standard_benchmark.json`
- `configs/releases/lorenz63_v1_core_release.json`

## Generated data, artifacts, reports, and logs

Smoke outputs:

- `data/raw/v1_core/lorenz63/smoke/lorenz63_raw.jld2`
- `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_observed.jld2`
- `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_split_I.json`
- `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_windows_summary.json`
- `data/manifests/v1_core/lorenz63/smoke/lorenz63_manifest.json`
- `reports/v1_core/lorenz63_standard/plots/smoke/lorenz63_phase3d.png`
- `reports/v1_core/lorenz63_standard/tables/smoke/lorenz63_diagnostics.csv`
- `reports/v1_core/lorenz63_standard/logs/smoke/run_lorenz63_smoke.log`

Standard outputs:

- `data/raw/v1_core/lorenz63/standard/lorenz63_raw.jld2`
- `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_observed.jld2`
- `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_split_I.json`
- `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_windows_summary.json`
- `data/manifests/v1_core/lorenz63/standard/lorenz63_manifest.json`
- `data/releases/v1_core/lorenz63/lorenz63_release_index.json`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_phase3d.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xy.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_yz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_timeseries_xyz.png`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_diagnostics.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_state_ranges.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_statistics.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_split_window_counts.csv`
- `reports/v1_core/lorenz63_standard/logs/standard/generate_lorenz63_standard.log`

The large raw, processed, release, and log outputs are intentionally covered by
the repository ignore policy. The manifest, plots, tables, configs, source, and
entry-point scripts are the reusable tracked outputs.

## Script-to-script data flow

Both entry points follow the same data flow:

1. Load benchmark, system, observation, split, window, and task configs.
2. Parse `Lorenz63Spec` and validate dimensions, parameters, timing, and solver
   metadata.
3. Build pre-burn-in initial conditions.
4. Integrate burn-in states with fixed-step RK4.
5. Integrate retained trajectories from the burn-in endpoints.
6. Assemble `RawTrajectory` objects with state matrices shaped
   `state_dim x time`.
7. Apply full-state identity observation to create `ObservedTrajectory`
   objects.
8. Build trajectory-level Split-I indices.
9. Build one-step, rollout, and statistics window count summaries inside each
   split.
10. Compute diagnostics and write raw, processed, split, window, manifest,
    plot, table, and log outputs.

## Validation commands and results

Smoke validation:

```powershell
julia --project=. experiments/smoke_tests/run_lorenz63_smoke.jl
```

Result: passed with `smoke_passed = true`, 6 trajectories, length 1200,
state ranges `x in [-18.0242, 17.4312]`, `y in [-24.2303, 23.1166]`,
`z in [5.57349, 44.7784]`, zero full-state observation error, and all 6
trajectories covering both wings.

Standard validation:

```powershell
julia --project=. experiments/data_generation/generate_lorenz63_standard_dataset.jl
```

Result: passed with `standard_passed = true`, 48 trajectories, length 4000,
Split-I counts `34/7/7`, state ranges `x in [-19.1145, 19.1145]`,
`y in [-26.2652, 26.2652]`, `z in [2.40955, 46.9373]`, zero full-state
observation error, and all 48 trajectories covering both wings.
