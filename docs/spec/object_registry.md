# Object Registry

This registry is a chronological map of reusable project objects in `ODEs_dataset`.
The task timeline is reconstructed from git history on 2026-04-28.

The project is a data-generation project. Per the current wrap-up scope, no
`reports/notebooks/` task report is required for this registry repair task.

## Status Legend

- Successful: objects that exist in the current tree or are intentionally
  superseded by a later successful object.
- Failed or blocked: attempted objects that should not be reused without
  revisiting the blocker.
- Superseded: objects that were useful historically but are no longer the
  canonical reuse target.

## 2026-04-27, Commit 3faf884, Initial

Successful objects:

- Project scaffold: `configs/`, `data/`, `docs/`, `experiments/`, `reports/`,
  `src/`, and `test/`.
- Julia project files: `Project.toml`, `Manifest.toml`, `.gitignore`.
- Initial project guide:
  `docs/Project Guide/ODEs Test Dataset Code Engineering Guide.md`.
- Initial mathematical note:
  `docs/Notes/linear_diagonal.md`, later moved to
  `docs/Notes/Code Explanation/linear_diagonal.md`.
- Initial source layout placeholders under `src/datasets`, `src/diagnostics`,
  `src/dynamics`, `src/generators`, `src/io`, `src/manifests`,
  `src/observations`, `src/registries`, `src/splits`, `src/tasks`,
  `src/utils`, and `src/windows`.

Superseded objects:

- Old split registries in `docs/spec/ODEs_dataset_spec.md`,
  `docs/spec/metric_registry.md`, `docs/spec/split_registry.md`,
  `docs/spec/system_registry.md`, and `docs/spec/task_registry.md`.
  These were removed by the 2026-04-28 registry rewrite and replaced by
  `object_registry.md` and `reusable_object_index.md`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-27, Commit 060b3e2, Linear Diagonal Dataset Workflow

Successful objects:

- Unit-internal system config:
  `configs/systems/unit_internal/linear_diagonal_small.json`.
- Unit-internal observation config:
  `configs/observations/unit_internal/full_state_identity.json`.
- Unit-internal split config:
  `configs/splits/unit_internal/split_I_70_15_15_seed1.json`.
- Unit-internal window configs:
  `configs/windows/unit_internal/one_step_lag1.json` and
  `configs/windows/unit_internal/rollout_horizon20.json`.
- Unit-internal task configs:
  `configs/tasks/unit_internal/one_step_forecast.json` and
  `configs/tasks/unit_internal/multi_step_rollout.json`.
- Unit-internal benchmark configs:
  `configs/benchmarks/unit_internal/linear_diagonal_smoke.json` and
  `configs/benchmarks/unit_internal/linear_diagonal_unit_internal.json`.
- Reusable source modules:
  `src/datasets/trajectory_types.jl`,
  `src/diagnostics/linear_system_checks.jl`,
  `src/dynamics/linear_diagonal.jl`, `src/io/jld2_io.jl`,
  `src/manifests/manifest_writer.jl`, `src/observations/full_state.jl`,
  `src/splits/trajectory_split.jl`, and `src/windows/window_builders.jl`.
- Smoke entry point:
  `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`.
- Dataset generation entry point, later moved to:
  `experiments/data_generation/generate_linear_diagonal_dataset.jl`.
- Unit test: `test/unit/test_linear_diagonal.jl`.
- Current unit-internal manifests:
  `data/manifests/unit_internal/linear_diagonal/small/linear_diagonal_manifest.json`,
  `data/manifests/unit_internal/linear_diagonal/small/linear_diagonal_smoke_manifest.json`,
  `data/manifests/unit_internal/linear_diagonal/small/one_step_lag1.json`,
  `data/manifests/unit_internal/linear_diagonal/small/rollout_horizon20.json`,
  and
  `data/manifests/unit_internal/linear_diagonal/small/split_I_70_15_15_seed1.json`.
- Current diagnostic plots under
  `reports/plots/unit_internal/linear_diagonal/`.

Superseded objects:

- Pre-organization paths under `configs/*/linear_diagonal*.json` and
  `data/manifests/linear_diagonal/small/` were superseded by the
  `unit_internal` layout in commit 3937555.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-27, Commit 2535f51, Linear Diagonal Documentation

Successful objects:

- Task plan moved to `docs/Notes/Code Explanation/linear_diagonal.md`.
- File explanation added at `docs/Notes/File Explanation/linear_diagonal.md`.
- System guide added at
  `docs/Project Guide/ODEs Test Dataset System Object.md`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit eaa89e7, Rotation-Contraction Dataset Workflow

Successful objects:

- Unit-internal system config:
  `configs/systems/unit_internal/linear_rotation_contraction_2d.json`.
- Observation configs:
  `configs/observations/unit_internal/full_state_identity_clean.json` and
  `configs/observations/unit_internal/full_state_identity_noise_1e-3.json`.
- Release config:
  `configs/releases/unit_internal_dev_rotation_contraction.json`.
- Split, task, window, and benchmark configs under the `unit_internal`
  namespace for `linear_rotation_contraction_2d`.
- Reusable dynamics module:
  `src/dynamics/linear_rotation_contraction_2d.jl`.
- Reusable exact linear trajectory generator:
  `src/generators/exact_linear_trajectory_generator.jl`.
- Reusable diagnostics module:
  `src/diagnostics/rotation_contraction_diagnostics.jl`.
- Smoke entry point:
  `experiments/smoke_tests/run_rotation_contraction_smoke.jl`.
- Dataset generation entry point, added later:
  `experiments/data_generation/generate_rotation_contraction_dataset.jl`.
- Manifest:
  `data/manifests/unit_internal/linear_rotation_contraction_2d/full_state_clean_small_manifest.json`.
- Diagnostics table:
  `reports/tables/unit_internal/rotation_contraction_smoke_diagnostics.csv`.
- Diagnostic plots under `reports/plots/unit_internal/`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit 3937555, Unit-Internal Layout Organization

Successful objects:

- Canonical `unit_internal` config namespace for linear diagonal and
  rotation-contraction objects.
- Canonical `unit_internal` manifest namespace for linear diagonal objects.
- Data generation scripts:
  `experiments/data_generation/generate_linear_diagonal_dataset.jl` and
  `experiments/data_generation/generate_rotation_contraction_dataset.jl`.
- Rotation-contraction file explanation:
  `docs/Notes/File Explanation/linear_rotation_contraction_2d.md`.
- Smoke scripts updated to use organized paths.
- Linear diagonal plots moved under
  `reports/plots/unit_internal/linear_diagonal/`.

Superseded objects:

- Older non-namespaced unit-internal config and report paths.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit f0329ce, Jordan Nonnormal Dataset Workflow

Successful objects:

- Unit-internal system configs:
  `configs/systems/unit_internal/jordan_nonnormal_linear_smoke.json` and
  `configs/systems/unit_internal/jordan_nonnormal_linear_formal.json`.
- Unit-internal split configs:
  `configs/splits/unit_internal/jordan_split_i_smoke.json` and
  `configs/splits/unit_internal/jordan_split_i_formal.json`.
- Unit-internal window configs:
  `configs/windows/unit_internal/jordan_rollout_smoke.json` and
  `configs/windows/unit_internal/jordan_rollout_formal.json`.
- Unit-internal task configs:
  `configs/tasks/unit_internal/jordan_one_step_forecast.json`,
  `configs/tasks/unit_internal/jordan_rollout_forecast.json`, and
  `configs/tasks/unit_internal/jordan_rollout_forecast_formal.json`.
- Unit-internal benchmark configs:
  `configs/benchmarks/unit_internal/jordan_nonnormal_smoke_benchmark.json`
  and
  `configs/benchmarks/unit_internal/jordan_nonnormal_formal_benchmark.json`.
- Reusable dynamics module:
  `src/dynamics/jordan_nonnormal_linear.jl`.
- Reusable diagnostics module:
  `src/diagnostics/jordan_nonnormal_diagnostics.jl`.
- Smoke entry point:
  `experiments/smoke_tests/run_jordan_nonnormal_smoke.jl`.
- Dataset generation entry point:
  `experiments/data_generation/generate_jordan_nonnormal_dataset.jl`.
- Manifests:
  `data/manifests/unit_internal/jordan_nonnormal_linear/smoke/manifest.json`
  and
  `data/manifests/unit_internal/jordan_nonnormal_linear/formal/manifest.json`.
- Diagnostics tables:
  `reports/tables/unit_internal/jordan_nonnormal_linear/smoke_diagnostics.csv`
  and
  `reports/tables/unit_internal/jordan_nonnormal_linear/formal_diagnostics.csv`.
- Diagnostic plots under
  `reports/plots/unit_internal/jordan_nonnormal_linear/`.
- Task and explanatory docs:
  `docs/Notes/Code Explanation/jordan_nonnormal_linear.md`,
  `docs/Notes/File Explanation/jordan_nonnormal_linear.md`, and
  `docs/Notes/mathematical explanation/jordan_nonnormal_linear.md`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit 5558410, Linear Oscillator v1_core Generation

Successful objects:

- v1-core system configs:
  `configs/systems/linear_oscillator_smoke_undamped.json` and
  `configs/systems/linear_oscillator_v1_core_damped.json`.
- v1-core observation config:
  `configs/observations/full_state_2d_clean.json`.
- v1-core split configs:
  `configs/splits/linear_oscillator_smoke_split_i.json` and
  `configs/splits/linear_oscillator_v1_core_split_i.json`.
- v1-core window configs:
  `configs/windows/linear_oscillator_smoke_windows.json` and
  `configs/windows/linear_oscillator_v1_core_windows.json`.
- v1-core task configs:
  `configs/tasks/linear_oscillator_forecasting_tasks.json` and
  `configs/tasks/linear_oscillator_reconstruction_tasks.json`.
- v1-core benchmark configs:
  `configs/benchmarks/smoke_linear_oscillator_undamped_full_state.json`
  and
  `configs/benchmarks/v1_core_linear_oscillator_damped_full_state.json`.
- Release preview:
  `configs/releases/linear_oscillator_v1_core_release_preview.json`.
- Reusable dynamics module:
  `src/dynamics/linear_oscillator.jl`.
- Reusable generator:
  `src/generators/linear_oscillator_dataset_generator.jl`.
- Reusable diagnostics module:
  `src/diagnostics/linear_oscillator_diagnostics.jl`.
- Smoke entry point:
  `experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl`.
- Dataset generation entry point:
  `experiments/data_generation/generate_linear_oscillator_damped_full_state.jl`.
- Manifests:
  `data/manifests/v1_core/linear_oscillator/smoke_undamped_full_state/manifest.json`
  and
  `data/manifests/v1_core/linear_oscillator/damped_full_state/manifest.json`.
- Diagnostics tables under `reports/tables/v1_core/linear_oscillator/`.
- Diagnostic plots under `reports/plots/v1_core/linear_oscillator/`.
- Task and explanatory docs:
  `docs/Notes/Code Explanation/linear_oscillator.md`,
  `docs/Notes/File Explanation/linear_oscillator.md`, and
  `docs/Notes/mathematical explanation/linear_oscillator.md`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit 71fbbde, Van der Pol Full-State Pipelines

Successful objects:

- v1-core system configs:
  `configs/systems/v1_core/vanderpol_unforced_smoke.json` and
  `configs/systems/v1_core/vanderpol_unforced_formal.json`.
- v1-core split configs:
  `configs/splits/v1_core/vanderpol_smoke_split_i.json`,
  `configs/splits/v1_core/vanderpol_formal_split_i.json`, and
  `configs/splits/v1_core/vanderpol_formal_split_p.json`.
- v1-core window configs:
  `configs/windows/v1_core/vanderpol_smoke_windows.json` and
  `configs/windows/v1_core/vanderpol_formal_windows.json`.
- v1-core task configs:
  `configs/tasks/v1_core/vanderpol_smoke_tasks.json` and
  `configs/tasks/v1_core/vanderpol_formal_tasks.json`.
- v1-core benchmark configs:
  `configs/benchmarks/v1_core/vanderpol_smoke_benchmark.json` and
  `configs/benchmarks/v1_core/vanderpol_formal_benchmark.json`.
- Release config:
  `configs/releases/vanderpol_unforced_fullobs_v1_release.json`.
- Reusable dynamics module:
  `src/dynamics/vanderpol_unforced.jl`.
- Reusable generator:
  `src/generators/vanderpol_dataset_generator.jl`.
- Reusable diagnostics module:
  `src/diagnostics/vanderpol_diagnostics.jl`.
- Shared window builder updates in `src/windows/window_builders.jl`.
- Smoke entry point:
  `experiments/smoke_tests/run_vanderpol_smoke_generation.jl`.
- Dataset generation entry point:
  `experiments/data_generation/generate_vanderpol_formal_dataset.jl`.
- Manifests:
  `data/manifests/v1_core/vanderpol_unforced/smoke/manifest.json` and
  `data/manifests/v1_core/vanderpol_unforced/formal/manifest.json`.
- Diagnostics tables under `reports/tables/v1_core/vanderpol/`.
- Diagnostic plots under `reports/plots/v1_core/vanderpol/`.
- File explanation:
  `docs/Notes/File Explanation/vanderpol_unforced_fullobs_v1_file_guide.md`.

Superseded objects:

- The old per-type spec registries were partially updated for Van der Pol in
  this commit, but they are no longer the current registration format.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Commit 2355972, Documentation Cleanup

Successful objects:

- Van der Pol task plan:
  `docs/Notes/Code Explanation/vanderpol_unforced_fullobs_v1_plan.md`.
- Mathematical explanations moved to the canonical directory:
  `docs/Notes/mathematical explanation/`.
- Van der Pol mathematical explanation:
  `docs/Notes/mathematical explanation/vanderpol_unforced_fullobs_v1_math.md`.
- Project guide updates in
  `docs/Project Guide/ODEs Test Dataset Code Engineering Guide.md`.

Superseded objects:

- Former nested path
  `docs/Notes/Code Explanation/mathematical explanation/`.

Failed or blocked objects:

- None recorded in git history.

## 2026-04-28, Registry Rewrite Task

Successful objects:

- Removed old, stale spec files:
  `docs/spec/ODEs_dataset_spec.md`,
  `docs/spec/metric_registry.md`,
  `docs/spec/split_registry.md`,
  `docs/spec/system_registry.md`, and
  `docs/spec/task_registry.md`.
- Added chronological registry:
  `docs/spec/object_registry.md`.
- Added reusable object index:
  `docs/spec/reusable_object_index.md`.

Failed or blocked objects:

- None.

## 2026-04-28, Duffing Unforced Double-Well Smoke Workflow

Successful objects:

- v1-core smoke system config:
  `configs/systems/v1_core/duffing_unforced_double_well_smoke.json`.
- v1-core observation config:
  `configs/observations/duffing_full_state_clean.json`.
- v1-core split config:
  `configs/splits/v1_core/duffing_smoke_split_i.json`.
- v1-core window config:
  `configs/windows/v1_core/duffing_smoke_windows.json`.
- v1-core task config:
  `configs/tasks/v1_core/duffing_smoke_tasks.json`.
- v1-core benchmark config:
  `configs/benchmarks/v1_core/duffing_smoke_benchmark.json`.
- Reusable dynamics module:
  `src/dynamics/duffing.jl`.
- Reusable generator:
  `src/generators/duffing_dataset_generator.jl`.
- Reusable diagnostics module:
  `src/diagnostics/duffing_diagnostics.jl`.
- Smoke entry point:
  `experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl`.
- Smoke manifest:
  `data/manifests/v1_core/duffing_unforced_double_well/smoke/manifest.json`.
- Diagnostics table:
  `reports/tables/v1_core/duffing/smoke/diagnostics.csv`.
- Diagnostic plots under:
  `reports/plots/v1_core/duffing/smoke/`.
- File explanation:
  `docs/notes/file explanation/duffing_unforced_double_well_smoke.md`.
- Task report:
  `reports/notebooks/duffing_unforced_double_well_smoke_report.md`.

Failed or blocked objects:

- None. The smoke command passed with zero positive energy jumps and balanced
  final left/right well counts.
