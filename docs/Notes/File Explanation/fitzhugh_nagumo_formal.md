# FitzHugh-Nagumo Formal Dataset File Explanation

## Task Summary

This task adds the formal fixed-parameter FitzHugh-Nagumo full-state dataset
workflow for the `v1_core` system layer. The system is the autonomous
two-dimensional FitzHugh-Nagumo model

```text
v_dot = v - v^3 / 3 - w + I
w_dot = epsilon * (v + a - b*w)
```

with fixed excitable-regime parameters `a = 0.7`, `b = 0.8`,
`epsilon = 0.08`, and `I = 0.3`. The observation chain is clean full-state
identity, so the observation matrix is identical to the state matrix.

The formal version uses a deterministic `8 x 6` initial-condition grid with
48 trajectories. It keeps the first FHN release focused on initial-condition
generalization under Split-I and does not introduce parameter or observation
generalization.

## Run Entry Points And Scripts

Smoke precheck:

```powershell
julia --project=. experiments/smoke_tests/run_fitzhugh_nagumo_smoke.jl
```

Formal generation:

```powershell
julia --project=. experiments/data_generation/generate_fitzhugh_nagumo_formal_dataset.jl
```

The formal script is the task-completion entry point for this file explanation.

## Core Source, Configs, And Docs Changed

- `src/dynamics/fitzhugh_nagumo.jl`
  defines `FitzHughNagumoSpec`, parameter validation, the vector field,
  nullclines, equilibrium search, Jacobian evaluation, fixed-step RK4
  propagation, and metadata.
- `src/generators/fitzhugh_nagumo_dataset_generator.jl`
  builds raw trajectories, applies full-state observation, creates Split-I,
  constructs window summaries, and writes JLD2, JSON, CSV, plot, and log
  outputs.
- `src/diagnostics/fitzhugh_nagumo_diagnostics.jl`
  checks finite states, full-state observation consistency, equilibrium
  residuals, state and velocity ranges, RK4 self consistency, threshold
  crossings, and formal pass criteria.
- `configs/systems/v1_core/fitzhugh_nagumo_formal.json`
  declares the 48-trajectory formal fixed-grid dataset.
- `configs/splits/v1_core/fitzhugh_nagumo_formal_split_i.json`
  declares trajectory-level Split-I with `70/15/15` ratios.
- `configs/windows/v1_core/fitzhugh_nagumo_formal_windows.json`
  declares lag-1 one-step windows, rollout horizons `100`, `500`, and `1000`,
  and statistics horizon `1000`.
- `configs/tasks/v1_core/fitzhugh_nagumo_formal_tasks.json`
  declares one-step forecast, multi-step rollout, and long-time statistics
  tasks.
- `configs/benchmarks/v1_core/fitzhugh_nagumo_formal_benchmark.json`
  binds the formal system, observation, split, windows, tasks, and output paths.
- `experiments/data_generation/generate_fitzhugh_nagumo_formal_dataset.jl`
  runs the formal generation workflow.

The smoke support files remain as preliminary validation assets, but smoke
validation is not recorded as task wrap-up under the updated workflow.

## Generated Data, Artifacts, Reports, And Logs

The formal command generated:

- `data/raw/v1_core/fitzhugh_nagumo/formal/full_state_clean/raw_trajectories.jld2`
- `data/processed/v1_core/fitzhugh_nagumo/formal/full_state_clean/observed_trajectories.jld2`
- `data/processed/v1_core/fitzhugh_nagumo/formal/full_state_clean/splits.json`
- `data/processed/v1_core/fitzhugh_nagumo/formal/full_state_clean/windows_summary.json`
- `data/manifests/v1_core/fitzhugh_nagumo/formal/full_state_clean/manifest.json`
- `data/releases/v1_core/fitzhugh_nagumo/formal/full_state_clean/release_index.json`
- `reports/tables/v1_core/fitzhugh_nagumo/formal/diagnostics.csv`
- `reports/plots/v1_core/fitzhugh_nagumo/formal/formal_time_series.png`
- `reports/plots/v1_core/fitzhugh_nagumo/formal/formal_phase_portrait_nullclines.png`
- `reports/logs/v1_core/fitzhugh_nagumo/formal.log`

The raw trajectories, processed trajectories, release index, and logs are
generated outputs ignored by the repository policy unless explicitly promoted.

## Script-To-Script Data Flow

The formal workflow executes:

```text
formal SystemSpec + 48 initial conditions
-> RawTrajectory vector
-> full-state ObservedTrajectory vector
-> trajectory-level Split-I
-> one-step / rollout / statistics window summaries
-> diagnostics and formal pass check
-> JLD2 data, JSON manifest, CSV diagnostics, plots, and log
```

Splitting is performed before window construction, so train, validation, and
test windows do not share trajectories.

## Validation Commands And Results

Formal command:

```powershell
julia --project=. experiments/data_generation/generate_fitzhugh_nagumo_formal_dataset.jl
```

Result:

- `formal_passed: true`
- trajectory count: `48`
- trajectory length: `6000`
- state matrix size per trajectory: `(2, 6001)`
- split counts: `train / val / test = 34 / 7 / 7`
- one-step window counts: train `204000`, val `42000`, test `42000`
- rollout horizon `100` counts: train `200634`, val `41307`, test `41307`
- rollout horizon `500` counts: train `187034`, val `38507`, test `38507`
- rollout horizon `1000` counts: train `170034`, val `35007`, test `35007`
- statistics horizon `1000` counts: train `170068`, val `35014`, test `35014`
- state range: `v in [-1.99199, 1.94367]`, `w in [-0.526831, 1.22999]`
- equilibrium count: `1`
- maximum equilibrium residual: `0.0`
- excursion trajectory count: `17`
- maximum threshold crossings per trajectory: `1`
