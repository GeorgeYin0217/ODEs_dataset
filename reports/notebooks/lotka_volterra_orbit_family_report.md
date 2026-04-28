# Lotka-Volterra Orbit-Family Report

## What was done

Added and ran the formal orbit-family dataset path for `lotka_volterra`. The
configuration uses fixed parameters
`alpha = 1.5`, `beta = 1.0`, `gamma = 3.0`, `delta = 1.0`, with 24 positive
initial conditions around the positive equilibrium `(3.0, 1.5)`.

## What ran

```text
julia --project=. -e 'include(joinpath(pwd(), "experiments", "data_generation", "generate_lotka_volterra_orbit_family_dataset.jl")); configs = load_lotka_volterra_orbit_family_configs(); spec, obs = validate_lotka_volterra_orbit_family_configs(configs); println(spec.system_id, " ", spec.variant, " trajectories=", configs["system"]["num_trajectories"], " observation=", obs.observation_id)'
julia --project=. experiments/data_generation/generate_lotka_volterra_orbit_family_dataset.jl
```

## Key results

- Formal status: passed.
- Trajectories: `24`.
- Trajectory length: `4000`, so each trajectory has `4001` saved snapshots.
- Split-I counts are train / val / test = `17 / 4 / 3` trajectories.
- One-step sample counts are train `68000`, val `16000`, test `12000`.
- Rollout horizons are `100`, `500`, and `1000`.
- All states stayed positive.
- State range was `x in [1.4849096771094876, 5.3045329748950945]` and
  `y in [0.5277293109559156, 3.258291437466377]`.
- Initial invariant values ranged from `0.6058373488128151` to
  `1.1906501749957856`.
- Maximum relative invariant drift was approximately `3.544013388196914e-10`.

## Outputs

- Manifest:
  `data/manifests/v1_core/lotka_volterra/orbit_family/full_state_clean/manifest.json`
- Diagnostics table:
  `reports/tables/v1_core/lotka_volterra/orbit_family/diagnostics.csv`
- Plots:
  `reports/plots/v1_core/lotka_volterra/orbit_family/orbit_family_time_series.png`,
  `reports/plots/v1_core/lotka_volterra/orbit_family/orbit_family_phase_portrait.png`, and
  `reports/plots/v1_core/lotka_volterra/orbit_family/orbit_family_invariant_drift.png`

## Next manual step

The orbit-family dataset is ready for downstream inspection scripts or benchmark
consumer checks.
