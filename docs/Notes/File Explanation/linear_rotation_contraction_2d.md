# linear_rotation_contraction_2d 文件说明

本文说明 `linear_rotation_contraction_2d` 内部单元测试数据集本次新增的配置、源码、脚本、生成数据与报告文件。该系统用于验证二维实状态中的复共轭谱、单步旋转角、半径收缩率，以及后续 DMD / EDMD / Koopman 谱恢复流程。

## 一、运行入口

### Smoke 脚本

```text
experiments/smoke_tests/run_rotation_contraction_smoke.jl
```

作用：最小端到端检查。它读取 unit-internal 配置，生成 raw trajectories，施加 full-state clean observation，按轨线做 Split-I，生成 one-step 与 rollout window summary，运行半径、角度、rollout 和谱诊断，并写出 smoke 报告。

运行方式：

```bash
julia --project=. experiments/smoke_tests/run_rotation_contraction_smoke.jl
```

### 正式数据生成脚本

```text
experiments/data_generation/generate_rotation_contraction_dataset.jl
```

作用：正式的数据工厂入口。它复用 smoke 已验证的同一条生成链路，但报告文件使用 `rotation_contraction_generation` 前缀，适合作为后续手动生成该数据集的稳定入口。

运行方式：

```bash
julia --project=. experiments/data_generation/generate_rotation_contraction_dataset.jl
```

当前正式脚本仍使用 small / unit_internal 配置，因为该系统的定位是内部协议测试与谱结构检查，而不是公开 leaderboard 主系统。

## 二、核心源码

```text
src/dynamics/linear_rotation_contraction_2d.jl
```

定义系统数学对象：

```text
LinearRotationContraction2DSpec
continuous_generator_matrix
exact_discrete_propagator
continuous_eigenvalues
discrete_eigenvalues
generate_linear_rotation_contraction_2d_trajectory
linear_rotation_contraction_2d_metadata
```

核心约定：

```text
A = [-gamma  -omega;
      omega  -gamma]

F^tau = exp(-gamma * dt) * [cos(omega * dt)  -sin(omega * dt);
                            sin(omega * dt)   cos(omega * dt)]
```

轨线矩阵保存为：

```text
state_matrix :: Matrix{Float64}, size = (2, trajectory_length + 1)
```

### 解析线性生成器

```text
src/generators/exact_linear_trajectory_generator.jl
```

作用：提供通用的解析线性系统轨线生成辅助函数。对本系统，它负责：

```text
读取 polar_annulus 初值策略
使用局部 MersenneTwister seed
采样 x0 = r [cos(theta), sin(theta)]
调用 exact discrete propagator 生成 RawTrajectory
检查 state_dim × time 的矩阵方向
```

### 诊断模块

```text
src/diagnostics/rotation_contraction_diagnostics.jl
```

作用：运行系统级 sanity check，不训练模型。当前诊断包括：

```text
radius_contraction_diagnostic
angle_increment_diagnostic
spectrum_abs_error_max
rollout_residual_diagnostic
summarize_rotation_contraction_dataset
```

核心输出字段：

```text
rho_true
rho_empirical_mean
rho_empirical_max_abs_error
theta_step_true
theta_step_empirical_mean
theta_step_max_abs_error
rollout_residual_max
spectrum_abs_error_max
smoke_passed
```

## 三、配置文件

### 系统配置

```text
configs/systems/unit_internal/linear_rotation_contraction_2d.json
```

声明：

```text
system_id = linear_rotation_contraction_2d
family = unit_internal
state_dim = 2
gamma = 0.15
omega = 2pi
dt = 0.01
trajectory_length = 500
num_trajectories = 64
solver_name = exact_discrete_linear
generation_seed = 202604
```

初值策略是极坐标环带：

```text
r0 ~ Uniform(0.5, 2.0)
theta0 ~ Uniform(0, 2pi)
```

### 观测配置

```text
configs/observations/unit_internal/full_state_identity_clean.json
configs/observations/unit_internal/full_state_identity_noise_1e-3.json
```

当前生成链路默认使用 clean full-state：

```text
z_m = x_m
```

低噪声观测配置已经声明，但当前 full-state observation 实现只支持 `noise_model = none`，噪声版本留给下一步扩展观测链。

### Split 配置

```text
configs/splits/unit_internal/split_i_70_15_15_seed202604.json
```

按完整 `trajectory_id` 切分：

```text
train / val / test = 70% / 15% / 15%
```

64 条轨线对应当前实际数量：

```text
train = 45
val = 10
test = 9
```

### Window 配置

```text
configs/windows/unit_internal/one_step_lag1.json
configs/windows/unit_internal/rollout_h10_h50_h100.json
```

one-step 样本：

```text
(z_m, z_{m+1})
```

rollout 窗口：

```text
(z_s, z_{s+1}, ..., z_{s+L}), L in {10, 50, 100}
```

窗口只在各自 split 内生成，不跨轨线、不跨 split。

### Task 和 benchmark 配置

```text
configs/tasks/unit_internal/task_rotation_contraction_one_step.json
configs/tasks/unit_internal/task_rotation_contraction_rollout.json
configs/tasks/unit_internal/task_rotation_contraction_spectrum.json
configs/benchmarks/unit_internal/benchmark_rotation_contraction_smoke.json
configs/releases/unit_internal_dev_rotation_contraction.json
```

三个任务分别对应：

```text
one_step_forecast
multi_step_rollout
spectrum_recovery_diagnostic
```

benchmark 配置同时声明 raw、processed、split、window summary、manifest 和 release index 的输出路径。

## 四、生成数据与报告

运行生成脚本后，会产生或更新：

```text
data/raw/unit_internal/linear_rotation_contraction_2d/small/raw_trajectories.jld2
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/observed_trajectories.jld2
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/splits.json
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/windows_summary.json
data/manifests/unit_internal/linear_rotation_contraction_2d/full_state_clean_small_manifest.json
data/releases/unit_internal/dev_rotation_contraction_index.json
```

raw JLD2 的主要字段：

```text
trajectory_ids
system_id
parameter_instances
initial_conditions
times
state_tensor
array_layout = state_dim_by_time_by_trajectory
```

processed JLD2 的主要字段：

```text
trajectory_ids
system_id
observation_id
parameter_instances
initial_conditions
state_tensor
observation_tensor
array_layout = state_dim_by_time_by_trajectory
```

报告文件：

```text
reports/tables/unit_internal/rotation_contraction_smoke_diagnostics.csv
reports/tables/unit_internal/rotation_contraction_generation_diagnostics.csv
reports/logs/unit_internal/rotation_contraction_smoke.log
reports/logs/unit_internal/rotation_contraction_generation.log
reports/plots/unit_internal/rotation_contraction_phase_portrait.png
reports/plots/unit_internal/rotation_contraction_radius_decay.png
reports/plots/unit_internal/rotation_contraction_angle_increment.png
reports/plots/unit_internal/rotation_contraction_discrete_spectrum.png
```

注意：正式脚本和 smoke 脚本共享图像文件名，因为图像表示同一个系统配置下的系统级诊断。

## 五、数据流

本系统的数据链是：

```text
system config
  -> LinearRotationContraction2DSpec
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
```

其中：

```text
X_all, Z_all :: Array{Float64,3}
size = (2, 501, 64)
```

维度顺序已经写入 JLD2 和 manifest：

```text
state_dim_by_time_by_trajectory
```

## 六、当前验证结果

smoke 脚本已运行通过，核心诊断为机器精度量级：

```text
rho max abs error      = 4.440892e-16
theta max abs error    = 3.913536e-15
rollout residual max   = 2.895107e-15
spectrum abs error max = 0.0
smoke_passed           = true
```

这说明当前实现满足：

```text
半径收缩率约等于 exp(-gamma * dt)
角度增量约等于 omega * dt
离散谱约等于 exp((-gamma ± i omega) * dt)
rollout 与解析矩阵幂一致
```

## 七、下一步建议

下一步可以补自动化测试：

```text
test/unit/test_linear_rotation_contraction_2d.jl
test/integration/test_rotation_contraction_generation_pipeline.jl
test/regression/test_rotation_contraction_reference_outputs.jl
```

随后再扩展 noisy full-state observation，使 `full_state_identity_noise_1e-3.json` 从声明文件变成可运行观测链。
