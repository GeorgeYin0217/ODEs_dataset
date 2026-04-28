# Lotka-Volterra Orbit-Family File Explanation

## Task summary

This task adds the formal orbit-family generation path for the `v1_core`
`lotka_volterra` system. It keeps the same fixed predator-prey parameters as the
smoke run and expands the initial-condition set to 24 positive states covering
multiple invariant levels around the positive equilibrium.

## Run entry points and scripts

- `experiments/data_generation/generate_lotka_volterra_orbit_family_dataset.jl`:
  formal orbit-family generation entry point.
- Non-generating config validation command:
  `julia --project=. -e 'include(joinpath(pwd(), "experiments", "data_generation", "generate_lotka_volterra_orbit_family_dataset.jl")); configs = load_lotka_volterra_orbit_family_configs(); validate_lotka_volterra_orbit_family_configs(configs)'`
- Formal generation command:
  `julia --project=. experiments/data_generation/generate_lotka_volterra_orbit_family_dataset.jl`

## Core source, configs, and docs changed

- `src/generators/lotka_volterra_dataset_generator.jl`: accepts both
  `manual_smoke_set` and `manual_orbit_family` positive initial-condition
  policies.
- `configs/systems/v1_core/lotka_volterra_orbit_family.json`: fixed-parameter
  orbit-family configuration with 24 positive initial conditions.
- `configs/splits/v1_core/lotka_volterra_orbit_family_split_i.json`:
  trajectory-level Split-I for orbit-family data.
- `configs/windows/v1_core/lotka_volterra_orbit_family_windows.json`:
  one-step, rollout, and statistics window declarations.
- `configs/tasks/v1_core/lotka_volterra_orbit_family_tasks.json`:
  one-step, rollout, and long-time statistics task declarations.
- `configs/benchmarks/v1_core/lotka_volterra_orbit_family_benchmark.json`:
  benchmark and output routing for orbit-family generation.
- `configs/releases/lotka_volterra_v1_core_release_candidate.json`:
  release-candidate declaration for smoke and orbit-family objects.

## Generated data, artifacts, reports, and logs

- `data/raw/v1_core/lotka_volterra/orbit_family/full_state_clean/raw_trajectories.jld2`
  stores raw state tensors.
- `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/observed_trajectories.jld2`
  stores clean full-state observed tensors.
- `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/splits.json`
  stores the trajectory-level split.
- `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/windows_summary.json`
  stores one-step, rollout, and statistics window counts.
- `data/manifests/v1_core/lotka_volterra/orbit_family/full_state_clean/manifest.json`
  stores generation metadata and diagnostics.
- `reports/tables/v1_core/lotka_volterra/orbit_family/diagnostics.csv`
  stores the human-readable diagnostics row.
- `reports/plots/v1_core/lotka_volterra/orbit_family/` contains time-series,
  phase-portrait, and invariant-drift PNGs.
- `reports/logs/v1_core/lotka_volterra/orbit_family.log` records the formal run
  summary.

## Script-to-script data flow

The formal script loads the orbit-family benchmark, system, observation, split,
window, task, and release-candidate configs. It validates the configuration
without generating data, then reuses the Lotka-Volterra dynamics, generator,
full-state observation, trajectory split, window summary, manifest, and
diagnostic modules introduced by the smoke task.

## Validation commands and results

Commands run:

```text
julia --project=. -e 'include(joinpath(pwd(), "experiments", "data_generation", "generate_lotka_volterra_orbit_family_dataset.jl")); configs = load_lotka_volterra_orbit_family_configs(); spec, obs = validate_lotka_volterra_orbit_family_configs(configs); println(spec.system_id, " ", spec.variant, " trajectories=", configs["system"]["num_trajectories"], " observation=", obs.observation_id)'
julia --project=. experiments/data_generation/generate_lotka_volterra_orbit_family_dataset.jl
```

Results:

- `formal_passed: true`
- trajectories: `24`
- trajectory length: `4000`
- first trajectory state matrix: `(2, 4001)`
- split counts: train `17`, val `4`, test `3`
- one-step counts: train `68000`, val `16000`, test `12000`
- rollout horizons: `100`, `500`, `1000`
- state range `x`: `[1.4849096771094876, 5.3045329748950945]`
- state range `y`: `[0.5277293109559156, 3.258291437466377]`
- full-state observation error max: `0.0`
- RK4 self residual max: `0.0`
- invariant max absolute drift: `4.2196801608440637e-10`
- invariant max relative drift: `3.544013388196914e-10`
