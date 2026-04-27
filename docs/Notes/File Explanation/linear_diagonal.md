基于刚才那份计划，第一版 Julia 脚本的使用方式应该是：**运行一个 smoke-test 生成入口，它自动读取/构造配置，生成线性对角系统数据，写入 raw / processed / split / window / manifest，并输出诊断结果**。这正好对应工程文档中的数据链：

$$
(\mathbf f,\boldsymbol\mu,\mathbf x_0,\tau)
\Longrightarrow
\{\mathbf x_m\}
\Longrightarrow
\{\mathbf z_m\}
\Longrightarrow
\text{split}
\Longrightarrow
\text{window}
\Longrightarrow
\text{task}
\Longrightarrow
\text{metric report}.
$$


文档也强调原始状态轨线、观测后样本、切分协议、窗口协议要彼此解耦，且 `raw`、`processed`、`manifest` 要分开保存。fileciteturn4file0

## 一、脚本应该怎么用

项目根目录假设是：

```text
ODEs_dataset/
```

进入项目根目录后，第一次需要实例化 Julia 环境：

```bash
julia --project=.
```

进入 Julia REPL 后执行：

```julia
using Pkg
Pkg.instantiate()
```

之后生成线性对角系统 small 数据集时，运行：

```bash
julia --project=. experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

这个脚本会完成一条最小数据工厂流水线：

```text
读取配置
  ↓
生成线性对角 raw trajectories
  ↓
施加 full-state identity observation
  ↓
保存 processed trajectories
  ↓
按轨线生成 train / val / test split
  ↓
在各 split 内部生成 one-step 和 rollout windows
  ↓
运行解析误差、一步残差、维度、split 泄漏检查
  ↓
写 manifest、日志和 smoke-test 图像
```

注意这里的关键是：**先按轨线 split，再在各 split 内部生成窗口**。不能先把所有窗口打乱再切分，否则同一条轨线的相邻窗口会同时进入训练集和测试集，长期传播指标会虚高。你的指南里也专门强调了这一点。fileciteturn4file1

---

## 二、默认会生成什么系统

第一版默认系统是：

$$
\dot{\mathbf x}=\Lambda \mathbf x,
\qquad
\Lambda=\operatorname{diag}(-1.0,-0.3,0.1,0.5).
$$


默认参数建议为：

```text
system_id           = linear_diagonal
family              = unit_internal
difficulty_level    = small
state_dim           = 4
dt                  = 0.05
trajectory_length   = 200
num_trajectories    = 64
observation_mode    = full_state_identity
split_type          = Split-I / initial_condition
window types        = one_step, rollout_horizon20
```

每条轨线有：

$$
M+1=201
$$


个时间快照，状态矩阵按文档约定保存为：

$$
\mathbf X\in\mathbb R^{4\times 201}.
$$


全状态观测下：

$$
\mathbf Z=\mathbf X.
$$


也就是说 processed 数据暂时不会加噪声、不会归一化、不会降维。这样第一版的目标是验证协议和生成器，而不是引入观测复杂性。

---

## 三、会产生哪些数据文件

### 1. Raw trajectories

路径类似：

```text
data/raw/unit_internal/linear_diagonal/small/
```

里面会有多条 `.jld2` 文件，例如：

```text
trajectory_0001_raw.jld2
trajectory_0002_raw.jld2
...
trajectory_0064_raw.jld2
```

每个 raw 文件主要包含：

```text
trajectory_id
system_id
times
state_matrix
parameter_instance
initial_condition_instance
dt
trajectory_length
solver_name
```

其中：

```text
times        :: Vector{Float64}, length = 201
state_matrix :: Matrix{Float64}, size = (4, 201)
```

raw 数据的含义是：**动力系统本体生成的原始状态轨线**。

---

### 2. Processed / observed trajectories

路径类似：

```text
data/processed/unit_internal/linear_diagonal/full_state_identity/small/
```

文件类似：

```text
trajectory_0001_observed.jld2
trajectory_0002_observed.jld2
...
trajectory_0064_observed.jld2
```

每个 processed 文件主要包含：

```text
trajectory_id
system_id
observation_id
times
state_matrix
observation_matrix
parameter_instance
initial_condition_instance
```

其中：

```text
state_matrix       :: Matrix{Float64}, size = (4, 201)
observation_matrix :: Matrix{Float64}, size = (4, 201)
```

在第一版中：

```text
observation_matrix == state_matrix
```

这是因为使用的是最简单观测链：

$$
U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.
$$


工程文档中也把低维 ODE 的这个情形写成 $\mathbf z=\mathbf x$。fileciteturn4file0

---

### 3. Split 文件

路径类似：

```text
data/manifests/linear_diagonal/splits/
```

文件例如：

```text
split_I_70_15_15_seed1.json
```

内容大致是：

```text
split_id
split_type
grouping_unit
seed
train_trajectory_ids
val_trajectory_ids
test_trajectory_ids
```

如果默认生成 64 条轨线，并用 floor 规则做 70/15/15 切分，那么大约是：

```text
train: 44 条轨线
val:    9 条轨线
test:  11 条轨线
```

这不是按单点切，也不是按窗口切，而是按完整轨线切。

---

### 4. Window index 文件

路径类似：

```text
data/manifests/linear_diagonal/windows/
```

会保存 one-step 和 rollout 的索引文件，例如：

```text
one_step_lag1_split_I_70_15_15_seed1.json
rollout_horizon20_split_I_70_15_15_seed1.json
```

这些文件不复制大矩阵，只保存索引，例如：

```text
trajectory_id
index_m
split_name
```

或：

```text
trajectory_id
start_index
horizon
split_name
```

默认 `trajectory_length = 200` 时，每条轨线有：

```text
one-step samples per trajectory = 200
```

如果 rollout horizon 是 20，并且窗口是：

$$
(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+20}),
$$


那么每条轨线有：

```text
rollout windows per trajectory = 181
```

因为共有 201 个快照，起点最大为 $201-20=181$。

在默认 44 / 9 / 11 轨线切分下，数量大约是：

```text
one-step:
  train = 44 × 200 = 8800
  val   =  9 × 200 = 1800
  test  = 11 × 200 = 2200

rollout horizon 20:
  train = 44 × 181 = 7964
  val   =  9 × 181 = 1629
  test  = 11 × 181 = 1991
```

---

### 5. Manifest 文件

路径类似：

```text
data/manifests/linear_diagonal/
```

文件例如：

```text
linear_diagonal_full_state_identity_small_manifest.json
```

它是本次数据生成的总索引，记录：

```text
dataset_version
benchmark_id
system_id
family
difficulty_level
state_dim
eigenvalues
dt
trajectory_length
num_trajectories
observation_id
observation_mode
noise_model
normalization_policy
split_id
window_ids
task_ids
solver_name
solver_abstol
solver_reltol
seed
raw_data_dir
processed_data_dir
split_file
window_files
diagnostic_report
plot_dir
```

它的作用是：以后算法脚本不需要手动猜数据在哪里，只要读 manifest，就能知道应该加载哪些轨线、哪些 split、哪些窗口和哪些任务。

你的指南也建议每个系统保存 `raw`、`processed`、`splits`、`metadata`，并从第一天冻结 `benchmark_version`、`system_id`、`split_id`、`observation_mode`、`difficulty_level`、`solver_metadata` 等信息。fileciteturn3file5

---

### 6. Diagnostic report / log

路径类似：

```text
reports/logs/linear_diagonal/
```

文件例如：

```text
linear_diagonal_smoke_log.txt
linear_diagonal_diagnostics.json
```

主要记录：

```text
max_analytic_error
max_one_step_residual
max_abs_state_value
state_matrix_size_check
observation_matrix_size_check
split_disjoint_check
window_index_check
file_readback_check
```

期望结果是：

```text
max_analytic_error      ≈ 1e-14 到 1e-12
max_one_step_residual   ≈ 1e-14 到 1e-12
state_matrix size       = (4, 201)
observation_matrix size = (4, 201)
split disjoint          = true
window valid            = true
```

如果这些检查不过，说明还不能进入后续算法 benchmark。

---

### 7. Smoke-test figures

路径类似：

```text
reports/plots/linear_diagonal/smoke/
```

会产生几张基础图，例如：

```text
trajectory_coordinates.png
analytic_error.png
log_amplitude_slopes.png
```

它们的用途分别是：

```text
trajectory_coordinates.png
```

检查四个坐标是否按照各自特征值衰减或增长。

```text
analytic_error.png
```

检查解析公式与生成轨线是否一致。

```text
log_amplitude_slopes.png
```

检查 $\log |x_i(t)|$ 的斜率是否接近 $\lambda_i$。对线性对角系统，这是最直接的谱正确性检查。

---

## 四、后续算法应该怎么读取这些数据

后续算法不应该直接随机扫 `data/processed/` 文件夹，而应该从 manifest 开始：

```text
1. 读取 manifest
2. 从 manifest 找到 processed_data_dir
3. 读取 split_file
4. 根据 train_trajectory_ids / val_trajectory_ids / test_trajectory_ids 读取轨线
5. 读取对应 window index
6. 构造 one-step 或 rollout batch
```

对于 one-step 任务：

$$
\text{input}=\mathbf z_m,
\qquad
\text{target}=\mathbf z_{m+1}.
$$


对于 rollout 任务：

$$
\text{input}=\mathbf z_s,
\qquad
\text{target}=(\mathbf z_{s+1},\dots,\mathbf z_{s+L}).
$$


这样做的好处是数据层和算法层完全解耦：以后你换成 EDMD、SINDy、Neural ODE、Koopman autoencoder、HSKL，都不需要重新生成或重新切分数据。

---

## 五、这次不会产生什么

第一版线性对角系统不会产生：

```text
噪声观测数据
部分观测数据
线性混合观测数据
非线性传感器数据
参数泛化 Split-P
观测泛化 Split-O
长期统计窗口
正式 release 文件
leaderboard 结果
```

这些是后续阶段再加的内容。当前目标只是把 **unit_internal / linear_diagonal / full_state / Split-I / one-step + rollout** 这条最小链路跑通。

确认这个使用方式和输出布局后，我就可以开始写第一版 Julia 代码。