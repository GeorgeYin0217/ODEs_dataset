# jordan_nonnormal_linear 文件说明

本文说明 `jordan_nonnormal_linear` 内部单元测试数据集本次新增的配置、源码、脚本、生成数据与报告文件。该系统用于验证二维 Jordan 非正规线性系统的不可对角化结构、重复特征值、Jordan 链、非正规瞬态放大、精确离散传播和 split/window 协议。

## 一、运行入口

### Smoke 脚本

```text
experiments/smoke_tests/run_jordan_nonnormal_smoke.jl
```

作用：最小端到端检查。它读取 smoke benchmark 配置，生成 raw trajectories，施加 full-state clean observation，按轨线做 Split-I，生成 one-step 与 rollout window summary，运行 Jordan rank、几何重数、闭合残差、rollout 残差、瞬态放大和 x2 激活诊断，并写出 smoke 报告。

运行方式：

```bash
julia --project=. experiments/smoke_tests/run_jordan_nonnormal_smoke.jl
```

### 正式数据生成脚本

```text
experiments/data_generation/generate_jordan_nonnormal_dataset.jl
```

作用：正式的数据工厂入口。它复用 smoke 已验证的同一条生成链路，但读取 formal benchmark 配置，并把报告写成 `formal_*` 文件，避免覆盖 smoke 结果。

运行方式：

```bash
julia --project=. experiments/data_generation/generate_jordan_nonnormal_dataset.jl
```

本次正式脚本已经运行通过。

## 二、核心源码

### 动力系统模块

```text
src/dynamics/jordan_nonnormal_linear.jl
```

定义系统数学对象：

```text
JordanNonnormalLinearSpec
continuous_generator_matrix
exact_discrete_propagator
jordan_closed_form_state
generate_jordan_nonnormal_linear_trajectory
jordan_rank_and_geometric_multiplicity
jordan_nonnormal_linear_metadata
```

核心约定：

```text
A = [alpha  gamma;
     0.0    alpha]

K_tau = exp(alpha * dt) * [1.0  gamma * dt;
                           0.0  1.0]

x(t) = exp(alpha * t) * [x1_0 + gamma * t * x2_0;
                         x2_0]
```

轨线矩阵保存为：

```text
state_matrix :: Matrix{Float64}, size = (2, trajectory_length + 1)
```

### 诊断模块

```text
src/diagnostics/jordan_nonnormal_diagnostics.jl
```

作用：运行系统级 sanity check，不训练模型。当前诊断包括：

```text
jordan_matrix_structure_diagnostic
jordan_max_one_step_residual
jordan_rollout_residual_diagnostic
jordan_transient_amplification_diagnostic
jordan_x2_activation_diagnostic
summarize_jordan_nonnormal_dataset
```

核心输出字段：

```text
rank_A_minus_alphaI
geom_mult
lambda_discrete
max_closed_form_error
max_one_step_residual
max_rollout_residual
max_norm_amplification
x2_activation_min_abs
x2_activation_mean_abs
smoke_passed
```

`smoke_passed` 是当前共享诊断字段名，在 formal 运行中也表示 Jordan 结构与数值一致性检查全部通过。

## 三、配置文件

### Smoke 配置

```text
configs/systems/unit_internal/jordan_nonnormal_linear_smoke.json
configs/splits/unit_internal/jordan_split_i_smoke.json
configs/windows/unit_internal/jordan_rollout_smoke.json
configs/benchmarks/unit_internal/jordan_nonnormal_smoke_benchmark.json
```

smoke 参数：

```text
alpha = -0.35
gamma = 3.0
dt = 0.05
trajectory_length = 80
num_trajectories = 12
horizons = [5, 10, 20]
```

### Formal 配置

```text
configs/systems/unit_internal/jordan_nonnormal_linear_formal.json
configs/splits/unit_internal/jordan_split_i_formal.json
configs/windows/unit_internal/jordan_rollout_formal.json
configs/benchmarks/unit_internal/jordan_nonnormal_formal_benchmark.json
```

formal 标准参数：

```text
alpha = -0.35
gamma = 3.0
dt = 0.01
tspan = [0.0, 8.0]
trajectory_length = 800
num_trajectories = 128
horizons = [10, 50, 100, 200]
```

该时间窗覆盖 `t_star ~= -1 / alpha = 2.857`，可以观察到非正规瞬态放大后的衰减。

### 观测、任务与窗口

观测配置复用：

```text
configs/observations/unit_internal/full_state_identity_clean.json
```

当前观测链是：

```text
z_m = x_m
```

任务配置：

```text
configs/tasks/unit_internal/jordan_one_step_forecast.json
configs/tasks/unit_internal/jordan_rollout_forecast.json
configs/tasks/unit_internal/jordan_rollout_forecast_formal.json
```

one-step 窗口复用：

```text
configs/windows/unit_internal/one_step_lag1.json
```

窗口只在各自 split 内生成，不跨轨线、不跨 split。

## 四、生成数据与报告

### Smoke 输出

```text
data/raw/unit_internal/jordan_nonnormal_linear/smoke/raw_trajectories.jld2
data/processed/unit_internal/jordan_nonnormal_linear/smoke/observed_trajectories.jld2
data/processed/unit_internal/jordan_nonnormal_linear/smoke/splits.json
data/processed/unit_internal/jordan_nonnormal_linear/smoke/windows_summary.json
data/manifests/unit_internal/jordan_nonnormal_linear/smoke/manifest.json
reports/tables/unit_internal/jordan_nonnormal_linear/smoke_diagnostics.csv
reports/logs/unit_internal/jordan_nonnormal_linear/smoke_generation.log
reports/plots/unit_internal/jordan_nonnormal_linear/smoke_time_series.png
reports/plots/unit_internal/jordan_nonnormal_linear/smoke_phase_portrait.png
reports/plots/unit_internal/jordan_nonnormal_linear/smoke_norm_amplification.png
```

### Formal 输出

```text
data/raw/unit_internal/jordan_nonnormal_linear/formal/raw_trajectories.jld2
data/processed/unit_internal/jordan_nonnormal_linear/formal/observed_trajectories.jld2
data/processed/unit_internal/jordan_nonnormal_linear/formal/splits.json
data/processed/unit_internal/jordan_nonnormal_linear/formal/windows_summary.json
data/manifests/unit_internal/jordan_nonnormal_linear/formal/manifest.json
reports/tables/unit_internal/jordan_nonnormal_linear/formal_diagnostics.csv
reports/logs/unit_internal/jordan_nonnormal_linear/formal_generation.log
reports/plots/unit_internal/jordan_nonnormal_linear/formal_time_series.png
reports/plots/unit_internal/jordan_nonnormal_linear/formal_phase_portrait.png
reports/plots/unit_internal/jordan_nonnormal_linear/formal_norm_amplification.png
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

## 五、数据流

本系统的数据链是：

```text
system config
  -> JordanNonnormalLinearSpec
  -> exact Jordan closed-form trajectory
  -> raw state trajectories X
  -> full-state observations Z
  -> trajectory-level Split-I
  -> one-step / rollout window summaries
  -> diagnostics
  -> manifest, tables, plots, and logs
```

数学上：

```text
x_{m+1} = K_tau x_m
z_m = x_m
```

formal 数据维度：

```text
X_all, Z_all :: Array{Float64,3}
size = (2, 801, 128)
array_layout = state_dim_by_time_by_trajectory
```

formal Split-I 数量：

```text
train = 90
val = 19
test = 19
```

formal one-step 样本数：

```text
train = 72000
val = 15200
test = 15200
```

formal rollout 窗口数：

```text
h10:  train = 71190, val = 15029, test = 15029
h50:  train = 67590, val = 14269, test = 14269
h100: train = 63090, val = 13319, test = 13319
h200: train = 54090, val = 11419, test = 11419
```

## 六、当前验证结果

Smoke 已运行通过：

```text
rank_A_minus_alphaI       = 1
geom_mult                 = 1
max_closed_form_error     = 0.0
max_one_step_residual     = 1.7798229048217483e-15
max_rollout_residual      = 4.47545209131181e-15
max_norm_amplification    = 3.162209559888641
x2_activation_min_abs     = 0.8168673456576132
smoke_passed              = true
```

Formal 已运行通过：

```text
rank_A_minus_alphaI       = 1
geom_mult                 = 1
max_closed_form_error     = 0.0
max_one_step_residual     = 2.6697343572326224e-15
max_rollout_residual      = 2.7662159678238816e-14
max_norm_amplification    = 3.196678137417844
x2_activation_min_abs     = 0.5239738549851016
x2_activation_mean_abs    = 0.9876163985905435
smoke_passed              = true
```

这说明当前实现满足：

```text
A - alpha I 的 rank 为 1
几何重数为 1
离散传播矩阵具有重复特征值 exp(alpha * dt)
闭式解、单步传播和多步 rollout 与解析公式一致
x2 初值方向被激活
存在明显非正规瞬态放大
```

## 七、后续建议

下一步可以补自动化测试：

```text
test/unit/test_jordan_nonnormal_dynamics.jl
test/unit/test_jordan_nonnormal_diagnostics.jl
test/integration/test_jordan_nonnormal_generation_pipeline.jl
test/regression/test_jordan_nonnormal_smoke_regression.jl
```

随后可以更新：

```text
docs/spec/system_registry.md
docs/spec/task_registry.md
docs/spec/metric_registry.md
```

把 `jordan_nonnormal_linear` 正式纳入 unit_internal 注册说明。
