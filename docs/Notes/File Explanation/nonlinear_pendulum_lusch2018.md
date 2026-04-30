# Nonlinear Pendulum Lusch2018 File Explanation

## Task Summary

This task added the Lusch-aligned undamped nonlinear pendulum dataset object:

```text
x1_dot = x2
x2_dot = -sin(x1)
H(x1, x2) = 0.5*x2^2 - cos(x1)
```

The first release candidate uses full-state clean observations, snapshot count `T = 51`, time step `dt = 0.02`, and initial conditions sampled from `x1 in [-3.1, 3.1]`, `x2 in [-2, 2]` with `H(x0) < 0.99`.

## Run Entry Points And Scripts

- `experiments/smoke_tests/smoke_nonlinear_pendulum_lusch2018.jl` runs the small smoke dataset with 64 trajectories.
- `experiments/baseline_forecasting/build_nonlinear_pendulum_lusch2018_release.jl` runs the medium release-candidate dataset with 512 trajectories.

## Core Source, Configs, And Docs Changed

- `src/dynamics/nonlinear_pendulum_lusch2018.jl` defines the system spec, Hamiltonian, admissibility rule, fixed-step RK4 step, and trajectory generator.
- `src/generators/nonlinear_pendulum_lusch2018_generator.jl` handles rejection sampling, raw and observed trajectory assembly, split/window summaries, JLD2/JSON/CSV outputs, plots, animation, and the Markdown report.
- `src/diagnostics/pendulum_family_diagnostics.jl` computes finite-state checks, full-state observation identity error, energy drift, energy-band coverage, separatrix checks, and smoke/medium pass flags.
- `configs/systems/v1_plus/nonlinear_pendulum_lusch2018_small.json` and `configs/systems/v1_plus/nonlinear_pendulum_lusch2018_medium.json` define the small and medium system configurations.
- `configs/observations/pendulum_fullstate_identity_clean.json` defines the clean full-state identity observation.
- `configs/splits/v1_plus/pendulum_split_i_small.json` and `configs/splits/v1_plus/pendulum_split_i_default.json` define trajectory-level Split-I variants.
- `configs/windows/v1_plus/pendulum_lusch2018_small_windows.json` and `configs/windows/v1_plus/pendulum_lusch2018_default_windows.json` define lag-1 one-step, horizon-10 rollout, horizon-25 rollout, and full-trajectory statistics windows.
- `configs/tasks/v1_plus/pendulum_lusch2018_small_tasks.json` and `configs/tasks/v1_plus/pendulum_lusch2018_default_tasks.json` bind the windows to forecasting and representation-evaluation tasks.
- `configs/benchmarks/v1_plus/nonlinear_pendulum_lusch2018_small_benchmark.json` and `configs/benchmarks/v1_plus/nonlinear_pendulum_lusch2018_medium_benchmark.json` bind the system, observation, split, windows, tasks, and output policy.
- `configs/releases/odes_dataset_v1_plus_pendulum_lusch2018_release.json` records the release-candidate manifest location.

## Generated Data, Artifacts, Reports, And Logs

Smoke outputs were generated under:

- `data/raw/v1_plus/nonlinear_pendulum_lusch2018/smoke/`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/smoke/`
- `data/manifests/v1_plus/nonlinear_pendulum_lusch2018/smoke/`
- `reports/v1_plus/nonlinear_pendulum_lusch2018_smoke/`

Medium release-candidate outputs were generated under:

- `data/raw/v1_plus/nonlinear_pendulum_lusch2018/medium/raw_trajectories.jld2`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/medium/full_state_clean/observed_trajectories.jld2`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/medium/full_state_clean/splits.json`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/medium/full_state_clean/windows_summary.json`
- `data/manifests/v1_plus/nonlinear_pendulum_lusch2018/medium/manifest.json`
- `data/releases/v1_plus/nonlinear_pendulum_lusch2018/medium/release_index.json`
- `reports/v1_plus/nonlinear_pendulum_lusch2018_medium/notebooks/nonlinear_pendulum_lusch2018_medium_report.md`
- `reports/v1_plus/nonlinear_pendulum_lusch2018_medium/plots/pendulum_physical_animation_medium.gif`
- `reports/v1_plus/nonlinear_pendulum_lusch2018_medium/tables/diagnostics.csv`
- `reports/v1_plus/nonlinear_pendulum_lusch2018_medium/logs/medium.log`

## Script-To-Script Data Flow

The smoke and medium scripts follow the same data flow:

```text
JSON configs
-> NonlinearPendulumLusch2018Spec
-> rejection-sampled initial conditions with H(x0) < 0.99
-> fixed-step RK4 raw trajectories X in R^(2 x 51)
-> full-state observed trajectories Z = X
-> trajectory-level Split-I
-> one-step, rollout, and statistics window summaries
-> diagnostics, manifest, report tables, plots, and animation
```

All windows are derived after trajectory-level splitting, so windows from the same trajectory cannot cross train, validation, and test subsets.

## Validation Commands And Results

Smoke command:

```powershell
julia --project=. .\experiments\smoke_tests\smoke_nonlinear_pendulum_lusch2018.jl
```

Smoke result: passed with 64 trajectories, state matrix size `(2, 51)`, acceptance rate `0.615385`, maximum energy drift `2.232641e-9`, and zero separatrix violations.

Medium release command:

```powershell
julia --project=. .\experiments\baseline_forecasting\build_nonlinear_pendulum_lusch2018_release.jl
```

Medium result: passed with 512 trajectories, state matrix size `(2, 51)`, Split-I counts `358/77/77`, acceptance rate `0.628221`, initial energy range `[-0.985363, 0.989147]`, maximum energy drift `3.113918e-9`, 31 near-separatrix initial conditions, and zero separatrix violations. The report animation was generated at `reports/v1_plus/nonlinear_pendulum_lusch2018_medium/plots/pendulum_physical_animation_medium.gif`.
