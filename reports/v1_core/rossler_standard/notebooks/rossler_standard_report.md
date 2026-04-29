# Rossler Standard Dataset Report

## Summary

The fixed-parameter Rössler system was added as a `v1_core` chaotic ODE dataset object with standard parameters `a = 0.2`, `b = 0.2`, and `c = 5.7`. The generated object uses full-state clean observation, fixed-step RK4 integration, burn-in before retained attractor samples, trajectory-level Split-I, and one-step, rollout, and statistics window summaries.

## Commands Run

```powershell
julia --project=. experiments/smoke_tests/run_rossler_smoke.jl
julia --project=. experiments/data_generation/generate_rossler_standard_dataset.jl
```

Both commands completed successfully.

## Standard Configuration

- System id: `rossler_standard`
- Observation id: `rossler_full_state_clean`
- Parameters: `a = 0.2`, `b = 0.2`, `c = 5.7`
- Time step: `dt = 0.02`
- Burn-in time: `50.0`
- Retained trajectory length: `4000`
- Number of trajectories: `48`
- Split-I trajectory counts: train `34`, validation `7`, test `7`
- Rollout horizons: `50`, `250`, `1000`
- Statistics horizon: `2000`

## Key Results

- `standard_passed = true`
- First state matrix size: `(3, 4001)`
- First observation matrix size: `(3, 4001)`
- State range: `x in [-9.1056, 11.4331]`, `y in [-10.7906, 7.84031]`, `z in [0.0135275, 22.8499]`
- Maximum state norm: about `23.60205`
- Maximum velocity norm: about `64.27414`
- Maximum step increment: about `1.284188`
- RK4 self-residual maximum: `0.0`
- Full-state observation error maximum: `0.0`
- Mean divergence: about `-5.34908`
- Active attractor trajectory count: `48`
- Maximum positive `y` crossing count: `14`

## Generated Outputs

- Raw trajectories: `data/raw/v1_core/rossler_standard/standard/rossler_raw.jld2`
- Observed trajectories: `data/processed/v1_core/rossler_standard/standard/full_state/rossler_observed.jld2`
- Manifest: `data/manifests/v1_core/rossler_standard/standard/rossler_manifest.json`
- Release index: `data/releases/v1_core/rossler_standard/rossler_release_index.json`
- Diagnostic tables: `reports/v1_core/rossler_standard/tables/standard/`
- Diagnostic plots: `reports/v1_core/rossler_standard/plots/standard/`
- Run log: `reports/v1_core/rossler_standard/logs/standard/generate_rossler_standard.log`

## Next Manual Step

The Rössler full-state standard object is ready for downstream benchmark use. Future extensions can add noisy, partial, or nonlinear observation variants without changing the fixed full-state object.
