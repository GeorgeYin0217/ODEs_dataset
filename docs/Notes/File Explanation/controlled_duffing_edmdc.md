# Controlled Duffing EDMDc Dataset Files

## Task Summary

Implemented and generated the controlled Duffing EDMDc dataset workflow. The system uses
the controlled Duffing equations with open-loop zero-order-held random inputs, full-state
observations, and separate state/input observation noise. The dataset layer exports raw,
processed, split, window, manifest, and release-index objects for downstream EDMDc use;
it does not implement EDMDc training.

## Run Entry Points And Scripts

- `experiments/smoke_tests/run_duffing_controlled_edmdc_smoke.jl` generates the smoke-scale dataset.
- `experiments/data_generation/generate_duffing_controlled_edmdc_formal_dataset.jl` generates the formal long-trajectory dataset.

Both scripts load local JSON configs, include the controlled Duffing source modules, build
raw trajectories, derive clean/noisy processed observations, build trajectory-level splits,
build one-step and rollout windows, write manifests, and print validation diagnostics.

## Core Source, Configs, And Docs Changed

- `src/dynamics/duffing_controlled.jl`: controlled Duffing parameters, RHS, ZOH input convention, and fixed-step RK4 integrator.
- `src/datasets/controlled_trajectory_types.jl`: raw/observed controlled trajectory objects and controlled sample contracts.
- `src/observations/controlled_noise_models.jl`: full-state clean/noisy observations with separate state and input noise matrices.
- `src/generators/generate_controlled_duffing.jl`: smoke/formal raw generation, beta-grid expansion, Split-I and Split-P-beta support, save logic, manifest writing, and plots.
- `src/diagnostics/controlled_duffing_diagnostics.jl`: dimension, input excitation, noise, split/window, and pass/fail diagnostics.
- `configs/systems/v1_core/duffing_controlled_edmdc_smoke.json`: smoke single-beta configuration.
- `configs/systems/v1_core/duffing_controlled_edmdc_formal.json`: formal three-beta long-trajectory configuration.
- `configs/observations/duffing_controlled_fullstate_clean.json`: clean full-state controlled observation.
- `configs/observations/duffing_controlled_fullstate_noise_s1.json`: relative RMS `1e-3` state/input noise.
- `configs/observations/duffing_controlled_fullstate_noise_s2.json`: relative RMS `1e-2` state/input noise.
- `configs/observations/duffing_controlled_fullstate_noise_s3.json`: relative RMS `5e-2` state/input noise.
- `configs/splits/v1_core/duffing_controlled_*`: Split-I and Split-P-beta declarations.
- `configs/windows/v1_core/duffing_controlled_*`: one-step and rollout controlled window declarations.
- `configs/tasks/v1_core/duffing_controlled_edmdc_*`: downstream EDMDc task declarations.
- `configs/benchmarks/v1_core/duffing_controlled_edmdc_*`: smoke and formal benchmark output policies.
- `configs/releases/ODEs_dataset_controlled_duffing_edmdc_v1_*`: release metadata stubs.

## Generated Data, Artifacts, Reports, And Logs

Smoke outputs:

- `data/raw/v1_core/duffing_controlled_edmdc/smoke/raw_controlled_trajectories.jld2`
- `data/processed/v1_core/duffing_controlled_edmdc/smoke/duffing_controlled_fullstate_clean/observed_controlled_trajectories.jld2`
- `data/processed/v1_core/duffing_controlled_edmdc/smoke/duffing_controlled_fullstate_noise_s1/observed_controlled_trajectories.jld2`
- `data/manifests/v1_core/duffing_controlled_edmdc/smoke/manifest.json`
- `reports/v1_core/duffing_controlled_edmdc_smoke/`

Formal outputs:

- `data/raw/v1_core/duffing_controlled_edmdc/formal/raw_controlled_trajectories.jld2`
- `data/processed/v1_core/duffing_controlled_edmdc/formal/<observation_id>/observed_controlled_trajectories.jld2`
- `data/processed/v1_core/duffing_controlled_edmdc/formal/split_i/splits.json`
- `data/processed/v1_core/duffing_controlled_edmdc/formal/split_i/windows_summary.json`
- `data/processed/v1_core/duffing_controlled_edmdc/formal/split_p_beta/splits.json`
- `data/processed/v1_core/duffing_controlled_edmdc/formal/split_p_beta/windows_summary.json`
- `data/manifests/v1_core/duffing_controlled_edmdc/formal/manifest.json`
- `data/releases/v1_core/duffing_controlled_edmdc/formal/release_index.json`
- `reports/v1_core/duffing_controlled_edmdc_formal/`

Generated data and report media are intentionally ignored by the repository default
ignore policy unless explicitly force-added.

## Script-To-Script Data Flow

The controlled Duffing workflow is:

1. Load benchmark, system, observation, split, window, and task configs.
2. Expand beta values and initial conditions into raw trajectory IDs.
3. Sample open-loop ZOH inputs with reproducible per-trajectory seeds.
4. Integrate clean states with fixed-step RK4.
5. Build clean and noisy full-state controlled observations:
   `(X, U) -> (Z, U_tilde)`.
6. Build trajectory-level Split-I and, for formal, Split-P-beta.
7. Build controlled one-step and rollout window summaries.
8. Save raw/processed JLD2 tensors, JSON split/window objects, manifests, diagnostics tables, logs, and plots.

The stored EDMDc one-step contract is:

```text
(observation_tensor[:, m, r], observed_input_tensor[:, m, r], observation_tensor[:, m + 1, r])
```

with `observed_input_tensor[:, m, r]` held on `[t_m, t_{m+1})`.

## Validation Commands And Results

Smoke command:

```powershell
julia --project=. experiments\smoke_tests\run_duffing_controlled_edmdc_smoke.jl
```

Smoke result:

- Raw state tensor shape: `(2, 121, 4)`
- Raw input tensor shape: `(1, 120, 4)`
- Split-I counts: train/val/test = `2/1/1`
- Noise levels: clean + `1e-3`
- `smoke_passed: true`

Formal command:

```powershell
julia --project=. experiments\data_generation\generate_duffing_controlled_edmdc_formal_dataset.jl
```

Formal result:

- Beta values: `[0.5, 1.0, 1.5]`
- Raw trajectory count: `54`
- Trajectory length: `4000`
- Raw state tensor shape: `(2, 4001, 54)`
- Raw input tensor shape: `(1, 4000, 54)`
- Split-I counts: train/val/test = `36/9/9`
- Split-P-beta counts: train/val/test = `18/18/18`
- Noise levels: clean, `1e-3`, `1e-2`, `5e-2`
- RK4 self residual max: `0.0`
- `formal_passed: true`
