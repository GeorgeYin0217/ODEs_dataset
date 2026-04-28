# Reusable Object Index

This index groups reusable `ODEs_dataset` objects by type. Use
`docs/spec/object_registry.md` for chronological provenance and commit context.

## Registry Documents

- `docs/spec/object_registry.md`: chronological registry reconstructed from git.
- `docs/spec/reusable_object_index.md`: this quick lookup index.

Superseded registry files removed on 2026-04-28:

- `docs/spec/ODEs_dataset_spec.md`
- `docs/spec/metric_registry.md`
- `docs/spec/split_registry.md`
- `docs/spec/system_registry.md`
- `docs/spec/task_registry.md`

## Project Guides And Plans

- `docs/Project Guide/ODEs Test Dataset Code Engineering Guide.md`: main
  project engineering guide.
- `docs/Project Guide/ODEs Test Dataset System Object.md`: system-object guide.
- `docs/Notes/Code Explanation/linear_diagonal.md`
- `docs/Notes/Code Explanation/linear_rotation_contraction_2d.md`
- `docs/Notes/Code Explanation/jordan_nonnormal_linear.md`
- `docs/Notes/Code Explanation/linear_oscillator.md`
- `docs/Notes/Code Explanation/vanderpol_unforced_fullobs_v1_plan.md`
- `docs/notes/code explanation/duffing_unforced_double_well_plan.md`

## File Explanations

- `docs/Notes/File Explanation/linear_diagonal.md`
- `docs/Notes/File Explanation/linear_rotation_contraction_2d.md`
- `docs/Notes/File Explanation/jordan_nonnormal_linear.md`
- `docs/Notes/File Explanation/linear_oscillator.md`
- `docs/Notes/File Explanation/vanderpol_unforced_fullobs_v1_file_guide.md`
- `docs/notes/file explanation/duffing_unforced_double_well_smoke.md`

## Mathematical Explanations

These are background references, not default coding-task plans.

- `docs/Notes/mathematical explanation/linear_diagonal.md`
- `docs/Notes/mathematical explanation/linear_rotation_contraction_2d.md`
- `docs/Notes/mathematical explanation/jordan_nonnormal_linear.md`
- `docs/Notes/mathematical explanation/linear_oscillator.md`
- `docs/Notes/mathematical explanation/vanderpol_unforced_fullobs_v1_math.md`
- `docs/notes/mathematical explanation/duffing_unforced_double_well_math.md`

## Systems

| System | Family | Current configs | Main use |
| --- | --- | --- | --- |
| `linear_diagonal` | `unit_internal` | `configs/systems/unit_internal/linear_diagonal_small.json` | Exact diagonal linear sanity check for one-step and rollout windows. |
| `linear_rotation_contraction_2d` | `unit_internal` | `configs/systems/unit_internal/linear_rotation_contraction_2d.json` | Stable spiral, complex-pair spectrum, rotation diagnostics. |
| `jordan_nonnormal_linear` | `unit_internal` | `configs/systems/unit_internal/jordan_nonnormal_linear_smoke.json`, `configs/systems/unit_internal/jordan_nonnormal_linear_formal.json` | Nonnormal and non-diagonalizable linear stress test. |
| `linear_oscillator` | `v1_core` | `configs/systems/linear_oscillator_smoke_undamped.json`, `configs/systems/linear_oscillator_v1_core_damped.json` | Community-facing linear oscillator baseline with exact discrete propagation. |
| `vanderpol_unforced` | `v1_core` | `configs/systems/v1_core/vanderpol_unforced_smoke.json`, `configs/systems/v1_core/vanderpol_unforced_formal.json` | Nonlinear limit-cycle benchmark with initial-condition and parameter splits. |
| `duffing_unforced_double_well` | `v1_core` | `configs/systems/v1_core/duffing_unforced_double_well_smoke.json` | Damped double-well nonlinear benchmark with energy monotonicity and well-membership diagnostics. |

## Source Modules

Core data types and IO:

- `src/datasets/trajectory_types.jl`
- `src/io/jld2_io.jl`
- `src/manifests/manifest_writer.jl`

Dynamics:

- `src/dynamics/linear_diagonal.jl`
- `src/dynamics/linear_rotation_contraction_2d.jl`
- `src/dynamics/jordan_nonnormal_linear.jl`
- `src/dynamics/linear_oscillator.jl`
- `src/dynamics/vanderpol_unforced.jl`
- `src/dynamics/duffing.jl`

Generators:

- `src/generators/exact_linear_trajectory_generator.jl`
- `src/generators/linear_oscillator_dataset_generator.jl`
- `src/generators/vanderpol_dataset_generator.jl`
- `src/generators/duffing_dataset_generator.jl`

Observations, splits, and windows:

- `src/observations/full_state.jl`
- `src/splits/trajectory_split.jl`
- `src/windows/window_builders.jl`

Diagnostics:

- `src/diagnostics/linear_system_checks.jl`
- `src/diagnostics/rotation_contraction_diagnostics.jl`
- `src/diagnostics/jordan_nonnormal_diagnostics.jl`
- `src/diagnostics/linear_oscillator_diagnostics.jl`
- `src/diagnostics/vanderpol_diagnostics.jl`
- `src/diagnostics/duffing_diagnostics.jl`

## Experiment Entry Points

Smoke scripts:

- `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`
- `experiments/smoke_tests/run_rotation_contraction_smoke.jl`
- `experiments/smoke_tests/run_jordan_nonnormal_smoke.jl`
- `experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl`
- `experiments/smoke_tests/run_vanderpol_smoke_generation.jl`
- `experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl`

Dataset generation scripts:

- `experiments/data_generation/generate_linear_diagonal_dataset.jl`
- `experiments/data_generation/generate_rotation_contraction_dataset.jl`
- `experiments/data_generation/generate_jordan_nonnormal_dataset.jl`
- `experiments/data_generation/generate_linear_oscillator_damped_full_state.jl`
- `experiments/data_generation/generate_vanderpol_formal_dataset.jl`

## Observation Configs

- `configs/observations/unit_internal/full_state_identity.json`
- `configs/observations/unit_internal/full_state_identity_clean.json`
- `configs/observations/unit_internal/full_state_identity_noise_1e-3.json`
- `configs/observations/full_state_2d_clean.json`
- `configs/observations/duffing_full_state_clean.json`

## Split Configs

Unit-internal:

- `configs/splits/unit_internal/split_I_70_15_15_seed1.json`
- `configs/splits/unit_internal/split_i_70_15_15_seed202604.json`
- `configs/splits/unit_internal/jordan_split_i_smoke.json`
- `configs/splits/unit_internal/jordan_split_i_formal.json`

v1-core:

- `configs/splits/linear_oscillator_smoke_split_i.json`
- `configs/splits/linear_oscillator_v1_core_split_i.json`
- `configs/splits/v1_core/vanderpol_smoke_split_i.json`
- `configs/splits/v1_core/vanderpol_formal_split_i.json`
- `configs/splits/v1_core/vanderpol_formal_split_p.json`
- `configs/splits/v1_core/duffing_smoke_split_i.json`

## Window Configs

Unit-internal:

- `configs/windows/unit_internal/one_step_lag1.json`
- `configs/windows/unit_internal/rollout_horizon20.json`
- `configs/windows/unit_internal/rollout_h10_h50_h100.json`
- `configs/windows/unit_internal/jordan_rollout_smoke.json`
- `configs/windows/unit_internal/jordan_rollout_formal.json`

v1-core:

- `configs/windows/linear_oscillator_smoke_windows.json`
- `configs/windows/linear_oscillator_v1_core_windows.json`
- `configs/windows/v1_core/vanderpol_smoke_windows.json`
- `configs/windows/v1_core/vanderpol_formal_windows.json`
- `configs/windows/v1_core/duffing_smoke_windows.json`

## Task Configs

Unit-internal:

- `configs/tasks/unit_internal/one_step_forecast.json`
- `configs/tasks/unit_internal/multi_step_rollout.json`
- `configs/tasks/unit_internal/task_rotation_contraction_one_step.json`
- `configs/tasks/unit_internal/task_rotation_contraction_rollout.json`
- `configs/tasks/unit_internal/task_rotation_contraction_spectrum.json`
- `configs/tasks/unit_internal/jordan_one_step_forecast.json`
- `configs/tasks/unit_internal/jordan_rollout_forecast.json`
- `configs/tasks/unit_internal/jordan_rollout_forecast_formal.json`

v1-core:

- `configs/tasks/linear_oscillator_forecasting_tasks.json`
- `configs/tasks/linear_oscillator_reconstruction_tasks.json`
- `configs/tasks/v1_core/vanderpol_smoke_tasks.json`
- `configs/tasks/v1_core/vanderpol_formal_tasks.json`
- `configs/tasks/v1_core/duffing_smoke_tasks.json`

## Benchmark Configs

Unit-internal:

- `configs/benchmarks/unit_internal/linear_diagonal_smoke.json`
- `configs/benchmarks/unit_internal/linear_diagonal_unit_internal.json`
- `configs/benchmarks/unit_internal/benchmark_rotation_contraction_smoke.json`
- `configs/benchmarks/unit_internal/jordan_nonnormal_smoke_benchmark.json`
- `configs/benchmarks/unit_internal/jordan_nonnormal_formal_benchmark.json`

v1-core:

- `configs/benchmarks/smoke_linear_oscillator_undamped_full_state.json`
- `configs/benchmarks/v1_core_linear_oscillator_damped_full_state.json`
- `configs/benchmarks/v1_core/vanderpol_smoke_benchmark.json`
- `configs/benchmarks/v1_core/vanderpol_formal_benchmark.json`
- `configs/benchmarks/v1_core/duffing_smoke_benchmark.json`

## Release Configs

- `configs/releases/unit_internal_dev_rotation_contraction.json`
- `configs/releases/linear_oscillator_v1_core_release_preview.json`
- `configs/releases/vanderpol_unforced_fullobs_v1_release.json`

## Dataset Manifests

| Dataset object | Manifest | Notes |
| --- | --- | --- |
| `linear_diagonal` small unit-internal | `data/manifests/unit_internal/linear_diagonal/small/linear_diagonal_manifest.json` | 64 trajectories, length 200, `dt = 0.05`, full-state identity observation. |
| `linear_diagonal` small smoke | `data/manifests/unit_internal/linear_diagonal/small/linear_diagonal_smoke_manifest.json` | Smoke benchmark manifest for the same small diagonal dataset. |
| `linear_rotation_contraction_2d` small | `data/manifests/unit_internal/linear_rotation_contraction_2d/full_state_clean_small_manifest.json` | 64 trajectories, length 500, `dt = 0.01`, full-state clean observation. |
| `jordan_nonnormal_linear` smoke | `data/manifests/unit_internal/jordan_nonnormal_linear/smoke/manifest.json` | 12 trajectories, length 80, one-step and short rollout windows. |
| `jordan_nonnormal_linear` formal | `data/manifests/unit_internal/jordan_nonnormal_linear/formal/manifest.json` | 128 trajectories, length 800, one-step and formal rollout windows. |
| `linear_oscillator` smoke undamped | `data/manifests/v1_core/linear_oscillator/smoke_undamped_full_state/manifest.json` | 8 trajectories, length 800, exact discrete linear solver. |
| `linear_oscillator` damped full-state | `data/manifests/v1_core/linear_oscillator/damped_full_state/manifest.json` | 256 trajectories, length 3000, release preview. |
| `vanderpol_unforced` smoke | `data/manifests/v1_core/vanderpol_unforced/smoke/manifest.json` | 8 trajectories, length 1000, fixed-step RK4, full-state observation. |
| `vanderpol_unforced` formal | `data/manifests/v1_core/vanderpol_unforced/formal/manifest.json` | 48 trajectories, length 2000, Split-I and Split-P. |
| `duffing_unforced_double_well` smoke | `data/manifests/v1_core/duffing_unforced_double_well/smoke/manifest.json` | 8 trajectories, length 800, fixed-step RK4, full-state observation, energy monotonicity checks. |

Auxiliary linear diagonal window/split manifests:

- `data/manifests/unit_internal/linear_diagonal/small/one_step_lag1.json`
- `data/manifests/unit_internal/linear_diagonal/small/rollout_horizon20.json`
- `data/manifests/unit_internal/linear_diagonal/small/split_I_70_15_15_seed1.json`

## Diagnostics And Human-Readable Outputs

Diagnostics tables:

- `reports/tables/unit_internal/rotation_contraction_smoke_diagnostics.csv`
- `reports/tables/unit_internal/jordan_nonnormal_linear/smoke_diagnostics.csv`
- `reports/tables/unit_internal/jordan_nonnormal_linear/formal_diagnostics.csv`
- `reports/tables/v1_core/linear_oscillator/smoke_undamped_full_state/diagnostics.csv`
- `reports/tables/v1_core/linear_oscillator/damped_full_state/diagnostics.csv`
- `reports/tables/v1_core/vanderpol/smoke/diagnostics.csv`
- `reports/tables/v1_core/vanderpol/formal/diagnostics.csv`
- `reports/tables/v1_core/duffing/smoke/diagnostics.csv`

Plot directories:

- `reports/plots/unit_internal/linear_diagonal/`
- `reports/plots/unit_internal/`
- `reports/plots/unit_internal/jordan_nonnormal_linear/`
- `reports/plots/v1_core/linear_oscillator/`
- `reports/plots/v1_core/vanderpol/`
- `reports/plots/v1_core/duffing/`

## Tests

- `test/unit/test_linear_diagonal.jl`: unit checks for the linear diagonal
  workflow.

## Superseded Or Avoid-By-Default Objects

- Old spec files listed under "Registry Documents" were stale and removed.
- Older non-namespaced unit-internal config paths were superseded by
  `configs/*/unit_internal/`.
- Older `data/manifests/linear_diagonal/small/` paths were superseded by
  `data/manifests/unit_internal/linear_diagonal/small/`.
- Older `reports/plots/linear_diagonal/` paths were superseded by
  `reports/plots/unit_internal/linear_diagonal/`.
- Former nested mathematical explanation path
  `docs/Notes/Code Explanation/mathematical explanation/` was superseded by
  `docs/Notes/mathematical explanation/`.

## Failed Or Blocked Reuse Notes

- No failed or blocked reusable objects are recorded in current git history.
