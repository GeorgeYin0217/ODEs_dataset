# Duffing Unforced Double-Well Smoke Report

## What Ran

The smoke entry point
`experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl` was run
with the project environment:

```powershell
julia --project=. experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl
```

## Key Result

The smoke run passed. It generated eight trajectories for the damped
double-well Duffing oscillator with full-state clean observation.

Important diagnostics:

- State matrix size: `(2, 801)` for each trajectory.
- Train / val / test trajectory counts: `6 / 1 / 1`.
- One-step window counts: train `4800`, val `800`, test `800`.
- Rollout windows:
  - horizon 25: train `4656`, val `776`, test `776`.
  - horizon 100: train `4206`, val `701`, test `701`.
- Statistics window counts: train `4212`, val `702`, test `702`.
- Full-state observation error max: `0.0`.
- RK4 self residual max: `0.0`.
- Max positive energy jump: `0.0`.
- Final well counts left / right / near-barrier: `4 / 4 / 0`.

## Outputs

The smoke command wrote a manifest and human-readable reports at:

- `data/manifests/v1_core/duffing_unforced_double_well/smoke/manifest.json`
- `reports/tables/v1_core/duffing/smoke/diagnostics.csv`
- `reports/plots/v1_core/duffing/smoke/`

Raw and processed trajectory files were also generated under `data/raw/` and
`data/processed/`, but those directories are ignored by version control.

## Next Manual Step

Review the smoke diagnostics and plots. If the smoke stage is accepted, the
next workflow step is to add the formal or small Duffing data-generation
scripts from the task plan.
