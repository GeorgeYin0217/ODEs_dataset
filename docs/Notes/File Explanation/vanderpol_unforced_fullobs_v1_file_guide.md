# vanderpol_unforced_fullobs_v1 file guide

## Task summary

This task adds and validates smoke and formal pipelines for the v1-core unforced Van der Pol oscillator with full-state identity observation.

The shared setting uses

- system: `vanderpol_unforced`
- dynamics: `x1_dot = x2`, `x2_dot = mu * (1 - x1^2) * x2 - x1`
- observation: `full_state_2d_clean`
- integrator: fixed-step RK4 recorded as `fixed_step_rk4`

The smoke variant fixes `mu = 1.0`. The formal variant samples `mu` on a deterministic grid over `[1.0, 3.0]`.

The RK4 choice is intentionally local to this implementation because the current project environment does not yet declare a SciML ODE solver dependency.

## Run entry points and scripts

- `experiments/smoke_tests/run_vanderpol_smoke_generation.jl`
  - Loads the smoke configs.
  - Generates raw Van der Pol trajectories.
  - Applies full-state identity observation.
  - Builds trajectory-level Split-I.
  - Builds one-step, rollout, and statistics window summaries.
  - Writes data, reports, logs, and manifest files.

- `experiments/data_generation/generate_vanderpol_formal_dataset.jl`
  - Loads the formal configs.
  - Generates a single formal trajectory collection over `mu in [1, 3]`.
  - Applies full-state identity observation.
  - Builds Split-I and Split-P.
  - Builds one-step, rollout, and statistics window summaries for each split.
  - Writes formal data, reports, logs, and manifest files.

Run command:

```powershell
julia --project=. experiments/smoke_tests/run_vanderpol_smoke_generation.jl
julia --project=. experiments/data_generation/generate_vanderpol_formal_dataset.jl
```

## Core source, configs, and docs changed

- `src/dynamics/vanderpol_unforced.jl`
  - Defines `VanDerPolUnforcedSpec`.
  - Validates the smoke system contract.
  - Implements the unforced Van der Pol vector field.
  - Generates trajectories with fixed-step RK4.

- `src/generators/vanderpol_dataset_generator.jl`
  - Samples initial conditions.
  - Samples fixed or deterministic `linspace` `mu` values.
  - Builds `RawTrajectory` and `ObservedTrajectory` objects.
  - Builds Split-I, Split-P, and window summaries.
  - Saves JLD2, JSON, CSV, plot, and log outputs.

- `src/diagnostics/vanderpol_diagnostics.jl`
  - Checks finite states, state ranges, state and velocity scale, full-state observation consistency, RK4 self-consistency, and tail oscillation activity.

- `src/windows/window_builders.jl`
  - Adds `build_statistics_windows`.
  - Extends `validate_window_indices` for statistics windows.

- `configs/systems/v1_core/vanderpol_unforced_smoke.json`
  - Smoke system declaration.

- `configs/systems/v1_core/vanderpol_unforced_formal.json`
  - Formal system declaration with `mu in [1, 3]`.

- `configs/splits/v1_core/vanderpol_smoke_split_i.json`
  - Trajectory-level initial-condition split.

- `configs/splits/v1_core/vanderpol_formal_split_i.json`
  - Formal initial-condition split.

- `configs/splits/v1_core/vanderpol_formal_split_p.json`
  - Formal parameter split with disjoint `mu` blocks.

- `configs/windows/v1_core/vanderpol_smoke_windows.json`
  - One-step, rollout, and statistics window declarations.

- `configs/windows/v1_core/vanderpol_formal_windows.json`
  - Formal one-step, rollout, and statistics window declarations.

- `configs/tasks/v1_core/vanderpol_smoke_tasks.json`
  - Smoke task declarations.

- `configs/tasks/v1_core/vanderpol_formal_tasks.json`
  - Formal task declarations.

- `configs/benchmarks/v1_core/vanderpol_smoke_benchmark.json`
  - Full smoke benchmark binding and output policy.

- `configs/benchmarks/v1_core/vanderpol_formal_benchmark.json`
  - Full formal benchmark binding and output policy.

- `configs/releases/vanderpol_unforced_fullobs_v1_release.json`
  - Release-level index for smoke and formal configs.

## Generated data, artifacts, reports, and logs

- Raw trajectories:
  - `data/raw/v1_core/vanderpol_unforced/smoke/raw_trajectories.jld2`
  - `data/raw/v1_core/vanderpol_unforced/formal/raw_trajectories.jld2`

- Processed full-state observations:
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/smoke/observed_trajectories.jld2`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/formal/observed_trajectories.jld2`

- Split and window summaries:
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/smoke/splits.json`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/smoke/windows_summary.json`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/formal/split_i.json`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/formal/split_p.json`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/formal/windows_split_i_summary.json`
  - `data/processed/v1_core/vanderpol_unforced/full_state_2d_clean/formal/windows_split_p_summary.json`

- Manifest and release index:
  - `data/manifests/v1_core/vanderpol_unforced/smoke/manifest.json`
  - `data/releases/v1_core/vanderpol_unforced/smoke/release_index.json`
  - `data/manifests/v1_core/vanderpol_unforced/formal/manifest.json`
  - `data/releases/v1_core/vanderpol_unforced/formal/release_index.json`

- Human-readable reports:
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/tables/smoke/diagnostics.csv`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/smoke/vanderpol_time_series.png`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/smoke/vanderpol_phase_portrait.png`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/logs/smoke.log`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/tables/formal/diagnostics.csv`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/formal/vanderpol_time_series.png`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/formal/vanderpol_phase_portrait.png`
  - `reports/v1_core/vanderpol_unforced_fullobs_v1/logs/formal.log`

## Script-to-script data flow

1. The smoke or formal entry script loads benchmark, system, observation, split, window, and task JSON configs.
2. `vanderpol_unforced.jl` constructs and validates the system spec, then generates state matrices `X` with shape `2 x (M + 1)`.
3. `trajectory_types.jl` wraps each generated trajectory as `RawTrajectory`.
4. `full_state.jl` maps each raw state matrix to an identical observation matrix `Z = X`.
5. `trajectory_split.jl` splits complete trajectory IDs for Split-I; `vanderpol_dataset_generator.jl` builds Split-P as disjoint sorted `mu` blocks.
6. `window_builders.jl` derives one-step, rollout, and statistics window indices inside each split.
7. `vanderpol_diagnostics.jl` computes smoke and formal diagnostics.
8. `vanderpol_dataset_generator.jl` writes the data files, manifest, release index, diagnostics table, plots, and log.

## Validation commands and results

Command:

```powershell
julia --project=. experiments/smoke_tests/run_vanderpol_smoke_generation.jl
julia --project=. experiments/data_generation/generate_vanderpol_formal_dataset.jl
```

Smoke result:

- `smoke_passed: true`
- trajectory count: `8`
- trajectory length: `1000`
- first state matrix size: `(2, 1001)`
- split counts: train / val / test = `6 / 1 / 1`
- one-step window counts: train / val / test = `6000 / 1000 / 1000`
- rollout horizon 25 counts: train / val / test = `5856 / 976 / 976`
- rollout horizon 100 counts: train / val / test = `5406 / 901 / 901`
- statistics horizon 100 counts: train / val / test = `5412 / 902 / 902`
- max state norm: `4.008412`
- max velocity norm: `8.589986`
- RK4 self residual max: `0.0`
- full-state observation error max: `0.0`
- tail `x1` sign-change minimum: `3`

Formal result:

- `formal_passed: true`
- trajectory count: `48`
- trajectory length: `2000`
- first state matrix size: `(2, 2001)`
- `mu` range: `[1.0, 3.0]`
- Split-I counts: train / val / test = `34 / 7 / 7`
- Split-P counts: train / val / test = `34 / 7 / 7`
- Split-P `mu` ranges:
  - train: `[1.0, 2.404255319148936]`
  - val: `[2.4468085106382977, 2.702127659574468]`
  - test: `[2.74468085106383, 3.0]`
- max state norm: `5.959547`
- max velocity norm: `47.44435`
- RK4 self residual max: `0.0`
- full-state observation error max: `0.0`
- tail `x1` sign-change minimum: `4`
