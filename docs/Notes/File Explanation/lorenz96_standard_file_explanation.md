# Lorenz96 Standard Dataset File Explanation

## Task Summary

This task adds the Lorenz96 `v1_core` full-state clean benchmark workflow. The implemented object is the standard 40-dimensional Lorenz96 system with fixed forcing `F = 8`, no observation noise, full-state identity observation, trajectory-level Split-I, one-step windows, rollout windows, and statistics windows.

Both smoke and standard generation were run successfully. The smoke run is the engineering gate, and the standard run is the reusable dataset-facing output for this task.

## Run Entry Points And Scripts

- `experiments/smoke_tests/run_lorenz96_smoke.jl`
  - Minimal AI-runnable gate.
  - Uses 6 trajectories, `dt = 0.01`, burn-in `2.0`, and retained length `500`.
  - Writes smoke raw, processed, split, window summary, manifest, diagnostics tables, and plots.
- `experiments/data_generation/generate_lorenz96_standard_dataset.jl`
  - Formal generation entry point.
  - Uses 48 trajectories, `dt = 0.01`, burn-in `10.0`, and retained length `4000`.
  - Writes standard raw, processed, split, window summary, manifest, diagnostics tables, and plots.

## Core Source, Configs, And Docs Changed

- `src/dynamics/lorenz96.jl`
  - Defines `Lorenz96Spec`, cyclic indexing, right-hand side evaluation, uniform-state diagnostics, and fixed-step RK4 propagation.
  - Implements the convention
    `dx_i = (x_{i+1} - x_{i-2}) * x_{i-1} - x_i + F`
    with cyclic indices and column-as-time trajectory storage.
- `src/generators/lorenz96_dataset_generator.jl`
  - Samples fixed-seed perturbations around the uniform forcing state.
  - Runs burn-in, generates retained trajectories, applies full-state observation, builds split and window summaries, and writes outputs.
- `src/diagnostics/lorenz96_diagnostics.jl`
  - Checks finite values, boundary-index consistency, uniform-state residual, full-state observation identity, RK4 self residual, state ranges, energy summaries, coordinate statistics, split counts, and window counts.
- `configs/systems/v1_core/lorenz96_smoke.json`
- `configs/systems/v1_core/lorenz96_standard.json`
- `configs/observations/lorenz96_full_state_clean.json`
- `configs/splits/v1_core/lorenz96_smoke_split_i.json`
- `configs/splits/v1_core/lorenz96_standard_split_i.json`
- `configs/windows/v1_core/lorenz96_smoke_windows.json`
- `configs/windows/v1_core/lorenz96_standard_windows.json`
- `configs/tasks/v1_core/lorenz96_smoke_tasks.json`
- `configs/tasks/v1_core/lorenz96_standard_tasks.json`
- `configs/benchmarks/v1_core/lorenz96_smoke_benchmark.json`
- `configs/benchmarks/v1_core/lorenz96_standard_benchmark.json`
- `configs/releases/lorenz96_v1_core_release.json`

## Generated Data, Artifacts, Reports, And Logs

Smoke outputs:

- `data/raw/v1_core/lorenz96/smoke/lorenz96_raw.jld2`
- `data/processed/v1_core/lorenz96/smoke/full_state/lorenz96_observed.jld2`
- `data/processed/v1_core/lorenz96/smoke/full_state/lorenz96_split_I.json`
- `data/processed/v1_core/lorenz96/smoke/full_state/lorenz96_windows_summary.json`
- `data/manifests/v1_core/lorenz96/smoke/lorenz96_manifest.json`
- `reports/tables/lorenz96/smoke/lorenz96_diagnostics.csv`
- `reports/tables/lorenz96/smoke/lorenz96_coordinate_statistics.csv`
- `reports/tables/lorenz96/smoke/lorenz96_split_window_counts.csv`
- `reports/plots/lorenz96/smoke/lorenz96_representative_coordinates.png`
- `reports/plots/lorenz96/smoke/lorenz96_space_time_heatmap.png`
- `reports/logs/lorenz96/smoke/run_lorenz96_smoke.log`

Standard outputs:

- `data/raw/v1_core/lorenz96/standard/lorenz96_raw.jld2`
- `data/processed/v1_core/lorenz96/standard/full_state/lorenz96_observed.jld2`
- `data/processed/v1_core/lorenz96/standard/full_state/lorenz96_split_I.json`
- `data/processed/v1_core/lorenz96/standard/full_state/lorenz96_windows_summary.json`
- `data/manifests/v1_core/lorenz96/standard/lorenz96_manifest.json`
- `reports/tables/lorenz96/standard/lorenz96_diagnostics.csv`
- `reports/tables/lorenz96/standard/lorenz96_coordinate_statistics.csv`
- `reports/tables/lorenz96/standard/lorenz96_split_window_counts.csv`
- `reports/plots/lorenz96/standard/lorenz96_representative_coordinates.png`
- `reports/plots/lorenz96/standard/lorenz96_space_time_heatmap.png`
- `reports/logs/lorenz96/standard/generate_lorenz96_standard.log`

The raw and processed JLD2 files are generated dataset artifacts and remain ignored by version control. The manifests, tables, plots, configs, scripts, source files, and wrap-up documents are lightweight enough to track.

## Script-To-Script Data Flow

1. The system config is parsed into `Lorenz96Spec`.
2. Initial conditions are sampled as fixed-seed perturbations around `F * ones(40)`.
3. Each initial condition is advanced through burn-in.
4. A retained state trajectory is generated with fixed-step RK4.
5. `RawTrajectory` objects are assembled with state matrices of shape `40 x (M + 1)`.
6. Full-state identity observation copies each state matrix into an observation matrix.
7. Trajectory IDs are split into train, validation, and test sets before any windows are derived.
8. One-step, rollout, and statistics windows are built inside each split.
9. Raw, processed, split, window, manifest, table, plot, and log outputs are written.

## Validation Commands And Results

Smoke validation:

```powershell
julia --project=. experiments/smoke_tests/run_lorenz96_smoke.jl
```

Result:

- `smoke_passed: true`
- `num_trajectories: 6`
- `state_matrix size for first trajectory: (40, 501)`
- Split counts: `4 / 1 / 1`
- State range: `[-8.31666, 13.9203]`
- Full-state observation error max: `0.0`
- RK4 self residual max: `0.0`

Standard validation:

```powershell
julia --project=. experiments/data_generation/generate_lorenz96_standard_dataset.jl
```

Result:

- `standard_passed: true`
- `num_trajectories: 48`
- `state_matrix size for first trajectory: (40, 4001)`
- Split counts: `34 / 7 / 7`
- State range: `[-10.1273, 14.7946]`
- Energy mean: `18.732`
- Coordinate mean range: `0.202563`
- Coordinate variance range: `1.08288`
- Active trajectory count: `48`
- Full-state observation error max: `0.0`
- RK4 self residual max: `0.0`
