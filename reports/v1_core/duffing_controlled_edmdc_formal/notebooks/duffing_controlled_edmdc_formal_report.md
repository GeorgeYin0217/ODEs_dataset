# Controlled Duffing EDMDc Formal Dataset Report

## Task Summary

Generated the controlled Duffing EDMDc formal dataset with long trajectories,
three beta values, open-loop random ZOH inputs, clean full-state observations,
and four noisy state/input observation levels.

## Configuration

- System ID: `duffing_controlled_edmdc`
- Scope: `v1_core`
- Variant: `formal_beta_grid_fullstate_controlled`
- Dynamics: `q_dot = v`, `v_dot = -delta*v - alpha*q - beta*q^3 + input_gain*u`
- Fixed parameters: `delta=0.2`, `alpha=-1.0`, `input_gain=1.0`
- Beta values: `[0.5, 1.0, 1.5]`
- Time step: `0.02`
- Trajectory length: `4000`
- Raw trajectory count: `54`
- Input policy: random open-loop ZOH, amplitude `0.45`, hold steps `20`
- Observation levels: clean, `1e-3`, `1e-2`, `5e-2`, `15e-2` relative RMS state/input noise
- Release version: `0.2.1-dev`

## Validation Results

- Raw state tensor size: `(2, 4001, 54)`
- Raw input tensor size: `(1, 4000, 54)`
- State range q: `[-1.9792408717547385, 2.091338055799942]`
- State range v: `[-1.0998385489819744, 1.2086901716806169]`
- Input mean/std/absmax: `-0.0023672797596917916 / 0.2601524325193753 / 0.44992739595723774`
- RK4 self residual max: `0.0`
- Clean state/input relative RMS: `0.0 / 0.0`
- s1 state/input relative RMS mean: `0.001 / 0.001`
- s2 state/input relative RMS mean: `0.01 / 0.01`
- s3 state/input relative RMS mean: `0.049999999999999996 / 0.05`
- s4 state/input relative RMS mean: `0.15 / 0.15`
- Formal validation passed: `true`

## Split And Window Counts

- Split-I counts: train/val/test = `36/9/9`
- Split-P-beta counts: train/val/test = `18/18/18`
- Split-I one-step counts: train/val/test = `144000/36000/36000`
- Split-I rollout h10 counts: train/val/test = `143676/35919/35919`
- Split-I rollout h50 counts: train/val/test = `142236/35559/35559`
- Split-I rollout h100 counts: train/val/test = `140436/35109/35109`

## Generated Files

- Raw JLD2: `data/raw/v1_core/duffing_controlled_edmdc/formal/raw_controlled_trajectories.jld2`
- Processed JLD2 directory: `data/processed/v1_core/duffing_controlled_edmdc/formal/`
- High-noise processed JLD2: `data/processed/v1_core/duffing_controlled_edmdc/formal/duffing_controlled_fullstate_noise_s4/observed_controlled_trajectories.jld2`
- Split-I JSON: `data/processed/v1_core/duffing_controlled_edmdc/formal/split_i/splits.json`
- Split-P-beta JSON: `data/processed/v1_core/duffing_controlled_edmdc/formal/split_p_beta/splits.json`
- Manifest: `data/manifests/v1_core/duffing_controlled_edmdc/formal/manifest.json`
- Release index: `data/releases/v1_core/duffing_controlled_edmdc/formal/release_index.json`
- Diagnostics table: `reports/v1_core/duffing_controlled_edmdc_formal/tables/diagnostics.csv`
- Log: `reports/v1_core/duffing_controlled_edmdc_formal/logs/formal.log`

## Next Manual Step

Use the formal release manifest to connect downstream EDMDc baselines. The dataset stores
both clean and noisy `Z, U_tilde` tensors with the one-step contract
`(z_m, u_m, z_{m+1})`; downstream training should not reinterpret control as an
extra state coordinate.
