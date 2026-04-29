# Lorenz96 Standard Dataset Report

## Summary

Lorenz96 has been added as a `v1_core` high-dimensional chaotic benchmark. The first version uses the standard 40-dimensional system with forcing `F = 8`, full-state clean observation, fixed-step RK4 propagation, trajectory-level Split-I, one-step windows, multi-step rollout windows, and long-time statistics windows.

## Configuration

- System: `lorenz96`
- Variant: `k40_f8_standard_full_state`
- Family: `v1_core`
- State dimension: `40`
- Forcing: `F = 8.0`
- Observation: `lorenz96_full_state_clean`
- Noise model: `none`
- Time step: `0.01`
- Burn-in: `10.0`
- Retained trajectory length: `4000`
- Number of trajectories: `48`
- Split: trajectory-level Split-I with counts `34 / 7 / 7`
- Rollout horizons: `100`, `500`, `1000`
- Statistics horizon: `2000`

## Validation

Smoke command:

```powershell
julia --project=. experiments/smoke_tests/run_lorenz96_smoke.jl
```

Smoke result: passed.

Standard command:

```powershell
julia --project=. experiments/data_generation/generate_lorenz96_standard_dataset.jl
```

Standard result: passed.

Key standard diagnostics:

- State matrix shape for the first trajectory: `(40, 4001)`
- Full-state observation error max: `0.0`
- RK4 self residual max: `0.0`
- Uniform state residual: `0.0`
- State range: `[-10.1273, 14.7946]`
- State norm max: `32.1148`
- Velocity norm max: `212.294`
- Energy mean: `18.732`
- Coordinate mean range: `0.202563`
- Coordinate variance range: `1.08288`
- Active trajectory count: `48`

## Outputs

Main standard outputs:

- `data/raw/v1_core/lorenz96/standard/lorenz96_raw.jld2`
- `data/processed/v1_core/lorenz96/standard/full_state/lorenz96_observed.jld2`
- `data/manifests/v1_core/lorenz96/standard/lorenz96_manifest.json`
- `reports/v1_core/lorenz96_standard/tables/standard/lorenz96_diagnostics.csv`
- `reports/v1_core/lorenz96_standard/tables/standard/lorenz96_coordinate_statistics.csv`
- `reports/v1_core/lorenz96_standard/tables/standard/lorenz96_split_window_counts.csv`
- `reports/v1_core/lorenz96_standard/plots/standard/lorenz96_representative_coordinates.png`
- `reports/v1_core/lorenz96_standard/plots/standard/lorenz96_space_time_heatmap.png`

## Notes

The current Lorenz96 object is fixed-parameter and full-state only. Future variants can add forcing-parameter generalization, partial observation, nonlinear observation, and noisy observation without changing the base data protocol.
