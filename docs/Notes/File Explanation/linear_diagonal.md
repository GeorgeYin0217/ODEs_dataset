# linear_diagonal 文件说明

本文说明 `linear_diagonal` 内部单元测试数据集的当前文件归类。该系统属于：

```text
family = unit_internal
system_id = linear_diagonal
```

本次整理只移动文件位置并修正文档，不修改 Julia 代码内容。

## 一、入口脚本归档

### Smoke 脚本

```text
experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

作用：线性对角系统的最小端到端 smoke 入口。它对应数据链：

```text
system config
  -> raw trajectories
  -> full-state observed trajectories
  -> trajectory-level Split-I
  -> one-step / rollout windows
  -> diagnostics
  -> manifest and plots
```

### 正式数据生成脚本

```text
experiments/data_generation/generate_linear_diagonal_dataset.jl
```

作用：线性对角系统的正式数据生成入口。该文件原先位于：

```text
src/generators/generate_linear_diagonal.jl
```

现在已按项目分层移动到 `experiments/data_generation/`。`src/generators/` 保留给可复用生成器组件，不再放正式实验入口。

## 二、配置文件归档

所有 `linear_diagonal` 相关配置已归入 `unit_internal` 层。

### Benchmark 配置

```text
configs/benchmarks/unit_internal/linear_diagonal_smoke.json
configs/benchmarks/unit_internal/linear_diagonal_unit_internal.json
```

### 系统配置

```text
configs/systems/unit_internal/linear_diagonal_small.json
```

核心声明：

```text
state_dim = 4
eigenvalues = [-1.0, -0.3, 0.1, 0.5]
dt = 0.05
trajectory_length = 200
num_trajectories = 64
solver_name = exact_diagonal
difficulty_level = small
```

### 观测配置

```text
configs/observations/unit_internal/full_state_identity.json
```

含义：

```text
z_m = x_m
```

即 full-state identity observation，不加噪声、不归一化、不降维。

### Split 配置

```text
configs/splits/unit_internal/split_I_70_15_15_seed1.json
```

按完整 `trajectory_id` 做 Split-I 初值泛化切分：

```text
train / val / test = 70% / 15% / 15%
```

### Window 配置

```text
configs/windows/unit_internal/one_step_lag1.json
configs/windows/unit_internal/rollout_horizon20.json
```

其中 `one_step_lag1.json` 与旋转-收缩系统使用的 unit-internal one-step 配置完全相同，因此旧扁平副本已移除，只保留 `configs/windows/unit_internal/one_step_lag1.json` 这一份。

### Task 配置

```text
configs/tasks/unit_internal/one_step_forecast.json
configs/tasks/unit_internal/multi_step_rollout.json
```

对应任务：

```text
one_step_forecast
multi_step_rollout
```

## 三、数据文件归档

raw 与 processed 数据原本已经按 `unit_internal` 归档，无需移动：

```text
data/raw/unit_internal/linear_diagonal/small/
data/processed/unit_internal/linear_diagonal/full_state_identity/small/
```

raw 数据是一条条 JLD2 轨线文件：

```text
linear_diagonal_traj_0001.jld2
...
linear_diagonal_traj_0064.jld2
```

每条 raw trajectory 的核心对象是：

```text
times :: Vector{Float64}, length = 201
state_matrix :: Matrix{Float64}, size = (4, 201)
```

processed 数据使用 full-state identity observation，因此：

```text
observation_matrix == state_matrix
```

## 四、Manifest 与窗口索引归档

旧 manifest 目录：

```text
data/manifests/linear_diagonal/small/
```

已移动为：

```text
data/manifests/unit_internal/linear_diagonal/small/
```

当前包含：

```text
linear_diagonal_manifest.json
linear_diagonal_smoke_manifest.json
split_I_70_15_15_seed1.json
one_step_lag1.json
rollout_horizon20.json
```

其中：

```text
split_I_70_15_15_seed1.json
```

记录 train / val / test 的轨线 ID。窗口索引文件只保存索引，不复制大矩阵：

```text
one_step_lag1.json
rollout_horizon20.json
```

one-step 任务使用：

```text
(z_m, z_{m+1})
```

rollout horizon 20 使用：

```text
(z_s, z_{s+1}, ..., z_{s+20})
```

## 五、报告与图像归档

旧图像目录：

```text
reports/unit_internal/linear_diagonal/plots/
```

已移动为：

```text
reports/unit_internal/linear_diagonal/plots/
```

当前包含：

```text
reports/unit_internal/linear_diagonal/plots/smoke/coordinate_timeseries.png
reports/unit_internal/linear_diagonal/plots/smoke/log_amplitudes.png
reports/unit_internal/linear_diagonal/plots/diagnostics/coordinate_timeseries.png
reports/unit_internal/linear_diagonal/plots/diagnostics/log_amplitudes.png
```

图像用途：

```text
coordinate_timeseries.png
```

检查各状态分量是否按线性对角系统的特征值增长或衰减。

```text
log_amplitudes.png
```

检查 `log(abs(x_i(t)))` 的斜率是否接近对应连续特征值。

## 六、当前归档后的目录关系

整理后，`linear_diagonal` 与 `linear_rotation_contraction_2d` 采用同一类项目组织规则：

```text
configs/<kind>/unit_internal/
experiments/smoke_tests/
experiments/data_generation/
data/raw/unit_internal/<system_id>/
data/processed/unit_internal/<system_id>/<observation_id>/
data/manifests/unit_internal/<system_id>/
reports/unit_internal/<system_id>/plots/
```

这样后续新增 unit-internal 系统时，可以继续沿用相同分类：

```text
linear_diagonal
linear_rotation_contraction_2d
jordan_or_nonnormal_linear_system
```

## 七、脚本路径适配

文件归类后，`linear_diagonal` 的 smoke 和正式脚本已经同步改为读取 `configs/*/unit_internal/` 下的配置，并把 manifest、窗口索引和图像写入 `unit_internal` 层：

```text
data/manifests/unit_internal/linear_diagonal/small/
reports/unit_internal/linear_diagonal/plots/
```

因此当前入口可以直接运行：

```bash
julia --project=. experiments/smoke_tests/generate_linear_diagonal_smoke.jl
julia --project=. experiments/data_generation/generate_linear_diagonal_dataset.jl
```
