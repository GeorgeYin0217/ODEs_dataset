# Lorenz63 Standard Dataset Report

## Summary

The Lorenz '63 system was added as a `v1_core` chaotic benchmark for
full-state forecasting, rollout, and long-time statistics tasks. The workflow
now supports a smoke generation path and a standard generation path.

The standard run uses the classical Lorenz parameters:

- `sigma = 10`
- `rho = 28`
- `beta = 8/3`

Trajectories are integrated with fixed-step RK4 using `dt = 0.01`. Each
standard trajectory uses `burn_in_time = 10.0` before retaining a length-4000
trajectory on the attractor.

## What ran

Smoke command:

```powershell
julia --project=. experiments/smoke_tests/run_lorenz63_smoke.jl
```

Standard command:

```powershell
julia --project=. experiments/data_generation/generate_lorenz63_standard_dataset.jl
```

Both commands completed successfully.

## Key standard results

- Standard trajectories: 48
- Retained trajectory length: 4000 steps, 4001 saved states per trajectory
- Split-I trajectory counts: train 34, validation 7, test 7
- One-step window counts: train 136000, validation 28000, test 28000
- Rollout horizons: 50, 200, 1000
- Statistics window horizon: 2000
- State range:
  - `x in [-19.1145, 19.1145]`
  - `y in [-26.2652, 26.2652]`
  - `z in [2.40955, 46.9373]`
- Maximum state norm: `51.26928`
- Maximum velocity norm: `394.4915`
- RK4 self residual: `0.0`
- Full-state observation error: `0.0`
- Divergence: `-13.6667`
- Equilibrium count: 3
- Double-wing trajectory count: 48
- Maximum wing-switch count: 30
- `standard_passed = true`

## Outputs

Core metadata and human-readable outputs:

- `data/manifests/v1_core/lorenz63/standard/lorenz63_manifest.json`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_phase3d.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xy.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_yz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_timeseries_xyz.png`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_diagnostics.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_state_ranges.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_statistics.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_split_window_counts.csv`

Large raw and processed data outputs are generated under `data/raw/` and
`data/processed/`, which are ignored by repository policy.

## Next manual step

Use the standard manifest and processed full-state trajectories as the data
source for downstream Koopman Learning forecasting, rollout, and long-time
statistics experiments. Long-horizon pointwise trajectory mismatch should be
interpreted as a chaotic-system property; statistical preservation and
short-horizon forecast quality are the more meaningful checks.
