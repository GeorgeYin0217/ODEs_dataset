# FitzHugh-Nagumo Formal Dataset Report

## What Was Done

Implemented and ran the formal fixed-parameter FitzHugh-Nagumo full-state
dataset workflow for the `v1_core` benchmark layer. The formal dataset uses a
deterministic grid of 48 initial conditions and keeps the first FHN version
focused on initial-condition generalization under clean full-state observation.

Smoke validation was used only as a preliminary engineering gate. The final
task wrap-up is attached to the formal run.

## Run

```powershell
julia --project=. experiments/data_generation/generate_fitzhugh_nagumo_formal_dataset.jl
```

## Key Configuration

- System: `fitzhugh_nagumo`
- Variant: `fixed_excitable_formal_full_state`
- Parameters: `a = 0.7`, `b = 0.8`, `epsilon = 0.08`, `I = 0.3`
- Time step: `dt = 0.02`
- Trajectory length: `6000`
- Number of trajectories: `48`
- Initial-condition grid: 8 `v` values by 6 `w` values
- Observation: clean full-state identity
- Split-I counts: train `34`, validation `7`, test `7`
- Rollout horizons: `100`, `500`, `1000`
- Statistics horizon: `1000`

## Validation Result

The formal command passed.

Important diagnostics:

- state matrix size per trajectory: `(2, 6001)`
- observation matrix size per trajectory: `(2, 6001)`
- state range: `v in [-1.99199, 1.94367]`, `w in [-0.526831, 1.22999]`
- maximum state norm: `2.216351`
- maximum velocity norm: `1.552123`
- RK4 self residual maximum: `0.0`
- full-state observation error maximum: `0.0`
- equilibrium count: `1`
- equilibrium residual maximum: `0.0`
- excursion trajectory count: `17`
- maximum threshold crossings per trajectory: `1`
- `formal_passed: true`

## Outputs

- Raw trajectories:
  `data/raw/v1_core/fitzhugh_nagumo/formal/full_state_clean/raw_trajectories.jld2`
- Observed trajectories:
  `data/processed/v1_core/fitzhugh_nagumo/formal/full_state_clean/observed_trajectories.jld2`
- Manifest:
  `data/manifests/v1_core/fitzhugh_nagumo/formal/full_state_clean/manifest.json`
- Diagnostics table:
  `reports/tables/v1_core/fitzhugh_nagumo/formal/diagnostics.csv`
- Log:
  `reports/logs/v1_core/fitzhugh_nagumo/formal.log`
- Plots:
  `reports/plots/v1_core/fitzhugh_nagumo/formal/formal_time_series.png`
  and
  `reports/plots/v1_core/fitzhugh_nagumo/formal/formal_phase_portrait_nullclines.png`

## Next Manual Step

Use this formal object as the fixed-parameter FHN baseline. Later extensions can
add a parameter-generalization FHN variant or partial/noisy observations without
changing the current fixed full-state dataset definition.
