# linear_oscillator 文件说明

本文说明 `linear_oscillator` 作为 `v1_core` 第一个主测试系统新增的配置、源码、脚本、任务文件、生成数据与报告文件。该系统包含无阻尼 smoke 版本和欠阻尼正式版本，用于验证解析谱基线、全状态观测、轨线级 split、one-step / rollout window，以及后续 Koopman 谱恢复、预测和重构任务。

## 一、运行入口

### Smoke 脚本

```text
experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl
```

作用：最小端到端检查。它使用 `gamma = 0`、`omega0 = 1` 的无阻尼谐振子，生成 raw trajectories，施加 full-state clean observation，按轨线做 Split-I，生成 one-step 与短 rollout window summary，运行能量守恒、全状态观测一致性、rollout 和谱诊断，并写出 smoke 报告。

运行方式：

```bash
julia --project=. experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl
```

### 正式数据生成脚本

```text
experiments/data_generation/generate_linear_oscillator_damped_full_state.jl
```

作用：生成 `v1_core` 欠阻尼正式数据。它使用固定标准参数：

```text
gamma = 0.05
omega0 = 1.0
dt = 0.02
trajectory_length = 3000
num_trajectories = 256
```

运行方式：

```bash
julia --project=. experiments/data_generation/generate_linear_oscillator_damped_full_state.jl
```

## 二、核心源码

```text
src/dynamics/linear_oscillator.jl
```

定义线性振子数学对象：

```text
LinearOscillatorSpec
continuous_generator_matrix
exact_discrete_propagator
continuous_eigenvalues
discrete_eigenvalues
linear_oscillator_energy
generate_linear_oscillator_trajectory
linear_oscillator_metadata
```

核心系统：

```text
x = [q, v]
A = [0            1;
     -omega0^2   -2gamma]
dx/dt = A x
```

轨线矩阵保存为：

```text
state_matrix :: Matrix{Float64}, size = (2, trajectory_length + 1)
array_layout = state_dim_by_time_by_trajectory
```

### 生成器

```text
src/generators/linear_oscillator_dataset_generator.jl
```

作用：实现可复用的数据生成辅助流程。它负责：

```text
读取 box 初值策略并排除近零初值
使用局部 MersenneTwister seed
生成 RawTrajectory
生成 full-state ObservedTrajectory
按 trajectory_id 做 train / val / test split
生成 one-step 与 rollout window summary
保存 raw / processed / manifest / release index / reports
```

### 诊断模块

```text
src/diagnostics/linear_oscillator_diagnostics.jl
```

当前诊断包括：

```text
energy_conservation_diagnostic
full_state_observation_error
rollout_residual_diagnostic
spectrum_diagnostic
summarize_linear_oscillator_dataset
```

无阻尼 smoke 检查：

```text
E(t) 近似守恒
Z = X
rollout 与精确离散传播一致
离散谱模长接近 1
```

欠阻尼正式检查：

```text
0 < gamma < omega0
E(t) 不增长且最终能量衰减
Z = X
rollout 与精确离散传播一致
离散谱模长小于 1
```

## 三、配置文件

### 系统配置

```text
configs/systems/linear_oscillator_smoke_undamped.json
configs/systems/linear_oscillator_v1_core_damped.json
```

smoke 配置使用：

```text
family = v1_core
variant = undamped_smoke
gamma = 0.0
omega0 = 1.0
dt = 0.02
trajectory_length = 800
num_trajectories = 8
```

正式配置使用：

```text
family = v1_core
variant = damped_v1_core
gamma = 0.05
omega0 = 1.0
dt = 0.02
trajectory_length = 3000
num_trajectories = 256
```

### 观测配置

```text
configs/observations/full_state_2d_clean.json
```

含义：

```text
z_m = x_m
output_dim = 2
noise_model = none
normalization_policy = none
```

### Split 配置

```text
configs/splits/linear_oscillator_smoke_split_i.json
configs/splits/linear_oscillator_v1_core_split_i.json
```

smoke 使用：

```text
train / val / test = 80% / 10% / 10%
```

正式使用：

```text
train / val / test = 70% / 15% / 15%
```

切分单位始终是完整 `trajectory_id`，窗口只在各自 split 内部派生。

### Window 配置

```text
configs/windows/linear_oscillator_smoke_windows.json
configs/windows/linear_oscillator_v1_core_windows.json
```

smoke rollout horizons：

```text
L in {10, 50}
```

正式 rollout horizons：

```text
L in {25, 100, 500}
```

正式 window 配置还声明了 full-trajectory statistics window，当前脚本先保存其配置语义；窗口 materialization 仍只生成 one-step 与 rollout summary。

## 四、任务文件

```text
configs/tasks/linear_oscillator_forecasting_tasks.json
configs/tasks/linear_oscillator_reconstruction_tasks.json
```

预测任务文件声明：

```text
linear_oscillator_one_step_forecast
linear_oscillator_rollout_short
linear_oscillator_spectrum_diagnostic
```

重构任务文件声明：

```text
linear_oscillator_state_reconstruction_full_state
linear_oscillator_observation_reconstruction_full_state
```

正式 benchmark 组合文件引用上述任务：

```text
configs/benchmarks/v1_core_linear_oscillator_damped_full_state.json
```

smoke benchmark 组合文件：

```text
configs/benchmarks/smoke_linear_oscillator_undamped_full_state.json
```

release preview 文件：

```text
configs/releases/linear_oscillator_v1_core_release_preview.json
```

## 五、生成数据与报告

smoke 输出：

```text
data/raw/v1_core/linear_oscillator/smoke_undamped_full_state/raw_trajectories.jld2
data/processed/v1_core/linear_oscillator/smoke_undamped_full_state/observed_trajectories.jld2
data/processed/v1_core/linear_oscillator/smoke_undamped_full_state/splits.json
data/processed/v1_core/linear_oscillator/smoke_undamped_full_state/windows_summary.json
data/manifests/v1_core/linear_oscillator/smoke_undamped_full_state/manifest.json
reports/tables/v1_core/linear_oscillator/smoke_undamped_full_state/diagnostics.csv
reports/plots/v1_core/linear_oscillator/smoke_undamped_full_state/
```

正式输出：

```text
data/raw/v1_core/linear_oscillator/damped_full_state/raw_trajectories.jld2
data/processed/v1_core/linear_oscillator/damped_full_state/observed_trajectories.jld2
data/processed/v1_core/linear_oscillator/damped_full_state/splits.json
data/processed/v1_core/linear_oscillator/damped_full_state/windows_summary.json
data/manifests/v1_core/linear_oscillator/damped_full_state/manifest.json
data/releases/v1_core/linear_oscillator/damped_full_state/release_index.json
reports/tables/v1_core/linear_oscillator/damped_full_state/diagnostics.csv
reports/plots/v1_core/linear_oscillator/damped_full_state/
reports/logs/v1_core/linear_oscillator/damped_full_state.log
```

raw 和 processed JLD2 的主要字段：

```text
trajectory_ids
system_id
parameter_instances
initial_conditions
times
state_tensor
observation_tensor
array_layout = state_dim_by_time_by_trajectory
```

## 六、数据流

本系统的数据链是：

```text
system config
  -> LinearOscillatorSpec
  -> exact discrete propagator F^tau
  -> raw state trajectories X
  -> full-state observations Z
  -> trajectory-level Split-I
  -> one-step / rollout window summaries
  -> diagnostics
  -> manifest and release index
```

数学上：

```text
x_{m+1} = F^tau x_m
z_m = x_m
E(t) = 0.5 v(t)^2 + 0.5 omega0^2 q(t)^2
```

## 七、当前验证结果

smoke 已运行通过：

```text
energy relative drift max                  = 4.070372e-14
full-state observation error max           = 0.0
rollout residual max                       = 3.454203e-15
discrete spectrum abs error max            = 3.469447e-18
discrete spectrum modulus error from one   = 0.0
smoke_passed                               = true
```

正式脚本已运行通过：

```text
energy step increase max        = -2.226844e-11
energy final ratio max          = 2.537142e-03
full-state observation error    = 0.0
rollout residual max            = 6.853098e-15
discrete spectrum abs error max = 2.247388e-16
discrete spectrum modulus max   = 9.990005e-01
formal_passed                   = true
```
