下面给出 **Step 1：线性对角系统的代码工程计划书**。这是实现规划，不包含 Julia 代码；数学定义、解析解、谱结构和 correctness metrics 的推导已拆分到：

```text
docs/notes/code explanation/mathematical explanation/linear_diagonal.md
```

本计划严格按 `ODEs_dataset` 的协议组织：数据集工程应被视为“协议库 + 数据工厂 + 评测基座”，固定流水线是

$$
(\mathbf f,\boldsymbol{\mu},\mathbf x_0,\tau)
\rightarrow
\{\mathbf x_m\}
\rightarrow
\{\mathbf z_m\}
\rightarrow
\text{split}
\rightarrow
\text{window}
\rightarrow
\text{task}
\rightarrow
\text{metric report}.
$$

本次只完成第一个最小闭环，不生成完整 v1 benchmark。

# 1. Confirmed Task Summary

本次任务是在 `ODEs_dataset` 中新增内部单元测试系统：

```text
system_id = linear_diagonal
family    = unit_internal
```

第一版采用全状态恒等观测：

$$
U=\mathcal I,
\qquad
S=\mathcal I,
\qquad
Z=\mathcal I.
$$

因此 processed 轨线满足：

$$
\mathbf Z^{(q)}=\mathbf X^{(q)}.
$$

最终输出应包括：

1. raw 状态轨线；
2. processed 全状态观测轨线；
3. 轨线级 train / val / test split；
4. one-step 与 rollout window 索引；
5. manifest 元信息；
6. smoke test 结果与基础图像。

# 2. Task Decomposition

## 2.1 定义线性对角系统本体

目的：提供系统方程、解析离散流、参数校验。

输入：

1. 状态维数 `d`；
2. 对角谱 `eigenvalues`；
3. 初值 `x0`；
4. 采样步长 `dt`；
5. 轨线长度 `M`。

输出：

1. 连续时间 RHS；
2. 精确离散传播矩阵 `A_tau`；
3. 状态轨线矩阵 `X`。

依赖：无，是最底层动力系统模块。

## 2.2 定义配置对象

目的：让系统不是写死在脚本里，而是通过配置进入数据工厂。

至少需要：

1. `SystemSpec`；
2. `ObservationSpec`；
3. `SplitSpec`；
4. `WindowSpec`；
5. `TaskSpec`；
6. 一个最小 `BenchmarkSpec`。

这些对象对应工程文档中的数据流水线：系统与参数生成状态轨线，观测链生成算法入口数据，然后 split、window、task、metric。

## 2.3 生成 raw trajectories

目的：生成多条完整状态轨线，作为不可污染的原始数据。

输入：

1. `SystemSpec`；
2. 随机种子；
3. 初值采样策略；
4. 轨线数量 `R`。

输出：每条轨线保存为 `RawTrajectory`，至少包括：

1. `trajectory_id`；
2. `system_id`；
3. `parameter_instance`；
4. `initial_condition_instance`；
5. `times`；
6. `state_matrix`。

核心约定：

```text
size(state_matrix) == (state_dim, trajectory_length + 1)
```

即状态维度在行，时间快照在列。

## 2.4 应用全状态观测链

目的：把状态轨线转换成算法入口数据。

本阶段只做恒等观测，不加噪声、不归一化、不降维。

输出：每条轨线保存为 `ObservedTrajectory`，至少包括：

1. `trajectory_id`；
2. `system_id`；
3. `observation_id`；
4. `parameter_instance`；
5. `initial_condition_instance`；
6. `state_matrix`；
7. `observation_matrix`。

全状态观测下：

```text
size(observation_matrix) == size(state_matrix)
```

## 2.5 生成轨线级 split

目的：实现最基本的 `Split-I`，即初值泛化。

必须先按轨线切分，再在各自集合内部切窗口，避免同一条轨线的相邻窗口同时进入 train 和 test。

默认比例：

```text
train / val / test = 70% / 15% / 15%
```

小规模 smoke test 可使用：

```text
train / val / test = 80% / 10% / 10%
```

输入：

1. 轨线 ID 列表；
2. split seed；
3. train / val / test ratio。

输出：

1. `train_trajectory_ids`；
2. `val_trajectory_ids`；
3. `test_trajectory_ids`。

## 2.6 生成窗口索引

目的：从每个 split 内部生成任务样本。

先实现两种窗口：

1. one-step sample；
2. multi-step rollout window。

窗口索引只保存协议和位置，不直接复制大矩阵。

## 2.7 写入 manifest

目的：保证每次生成的数据可追踪、可复现、可升级。

manifest 至少记录：

1. `dataset_version`；
2. `system_id`；
3. `observation_id`；
4. `split_id`；
5. `window_id`；
6. `difficulty_level`；
7. `solver_name`；
8. `solver_abstol`；
9. `solver_reltol`；
10. `seed`；
11. `state_dim`；
12. `eigenvalues`；
13. `dt`；
14. `trajectory_length`；
15. `num_trajectories`；
16. 文件路径清单。

## 2.8 smoke test 与诊断

目的：确认第一个系统不是“生成了文件就算成功”，而是能做数学正确性检查。

检查内容包括：

1. 数值轨线与解析解是否一致；
2. 轨线矩阵维度是否为 `d x (M + 1)`；
3. split 是否按轨线划分；
4. window 是否没有跨越 split；
5. one-step 动力学是否满足 `x[:, m + 1] ≈ A_tau * x[:, m]`；
6. 保存文件是否能被重新读取；
7. manifest 是否能找到所有数据文件。

# 3. Planned Packages

## 3.1 `LinearAlgebra`

用于：

1. 构造对角矩阵；
2. 计算范数；
3. 检查谱；
4. 构造或验证离散传播矩阵。

这是 Julia 标准库，不需要额外安装。

## 3.2 `Random`

用于：

1. 固定随机种子；
2. 采样初值；
3. 随机打乱轨线 ID 做 split。

这是 Julia 标准库。

## 3.3 `DifferentialEquations.jl` / `OrdinaryDiffEq.jl`

线性对角系统默认使用解析解生成，避免把积分误差混入第一个单元测试。

保留 SciML 积分入口的目的：

1. 为未来非线性系统统一接入；
2. 在 smoke test 中可选地用 `ODEProblem + Tsit5()` 生成一条轨线，与解析解比较；
3. 验证 RHS 参数顺序、`saveat` 和时间索引语义。

## 3.4 `JLD2.jl`

用于保存 `.jld2` 数据文件，包括：

1. `times`；
2. `state_matrix`；
3. `observation_matrix`；
4. 简单 metadata dictionary。

为了长期兼容，第一版尽量保存数组、字典、字符串、数值和列表，不直接序列化复杂 Julia 函数或闭包。

## 3.5 `JSON.jl`

用于保存 manifest、split、window 索引等可读元信息。

manifest 这类长期元数据使用 JSON 更便于检查、版本升级和跨语言读取。

## 3.6 `Plots.jl`

用于 smoke test 图像：

1. 每个坐标随时间变化；
2. 数值解与解析解误差；
3. 模态增长 / 衰减曲线。

这个包不是核心生成依赖，可以只在 smoke test / report 中使用。

# 4. Directory And File Plan

## 4.1 配置层

```text
configs/systems/linear_diagonal_small.json
```

定义：

1. `system_id = "linear_diagonal"`；
2. `family = "unit_internal"`；
3. `state_dim = 4`；
4. `eigenvalues = [-1.0, -0.3, 0.1, 0.5]`；
5. `dt = 0.05`；
6. `trajectory_length = 200`；
7. `num_trajectories = 64`；
8. `solver_name = "exact_diagonal"`；
9. `difficulty_level = "small"`。

```text
configs/observations/full_state_identity.json
```

定义：

1. `observation_id = "full_state_identity"`；
2. `mode = "full_state"`；
3. `noise_model = "none"`；
4. `normalization_policy = "none"`；
5. `output_dim = 4`。

```text
configs/splits/split_I_70_15_15_seed1.json
```

定义：

1. `split_type = "initial_condition"`；
2. `grouping_unit = "trajectory"`；
3. `train_ratio = 0.70`；
4. `val_ratio = 0.15`；
5. `test_ratio = 0.15`。

```text
configs/windows/one_step_lag1.json
configs/windows/rollout_horizon20.json
```

定义 one-step 与 rollout window。

```text
configs/tasks/one_step_forecast.json
configs/tasks/multi_step_rollout.json
```

定义最小任务协议。

```text
configs/benchmarks/linear_diagonal_smoke.json
```

把 system、observation、split、window、task 组合成一次 smoke benchmark。

## 4.2 源码层

```text
src/dynamics/linear_diagonal.jl
```

职责：

1. 定义线性对角系统参数；
2. 提供 RHS；
3. 提供解析传播；
4. 提供单条轨线生成函数；
5. 提供谱和维度校验。

```text
src/observations/full_state.jl
```

职责：

1. 实现 `U = S = Z = I`；
2. 返回 `observation_matrix = state_matrix` 的安全拷贝或视图；
3. 检查输出维度。

```text
src/datasets/trajectory_types.jl
```

职责：

1. 定义轻量数据对象；
2. 至少包括 `RawTrajectory` 与 `ObservedTrajectory`；
3. 第一版可以用 `NamedTuple` 或简单 `struct`，但保存时转为基础字典。

```text
src/splits/trajectory_split.jl
```

职责：

1. 输入轨线 ID；
2. 按 seed 洗牌；
3. 输出 train / val / test 轨线 ID；
4. 检查无交集、全覆盖。

```text
src/windows/window_builders.jl
```

职责：

1. 从 split 内轨线构造 one-step index；
2. 从 split 内轨线构造 rollout index；
3. 不直接复制大矩阵，只保存索引协议。

```text
src/io/jld2_io.jl
```

职责：

1. 保存 raw / processed `.jld2`；
2. 读取 `.jld2`；
3. 检查文件是否存在。

```text
src/manifests/manifest_writer.jl
```

职责：

1. 写入 manifest JSON；
2. 记录配置、数据路径、seed、solver metadata；
3. 提供 manifest 校验函数。

```text
src/diagnostics/linear_system_checks.jl
```

职责：

1. 解析解误差；
2. one-step 残差；
3. split 泄漏检查；
4. window 合法性检查；
5. 基本统计量。

## 4.3 生成入口与 smoke test

```text
experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

职责：

1. 加载配置；
2. 生成 raw trajectories；
3. 生成 processed trajectories；
4. 生成 split；
5. 生成 windows；
6. 写 manifest；
7. 打印诊断信息；
8. 保存基础图像。

```text
test/unit/test_linear_diagonal.jl
```

职责：

1. 小规模自动测试；
2. 只生成极少轨线；
3. 检查解析误差、维度、split、window、文件读写。

## 4.4 数据输出

```text
data/raw/unit_internal/linear_diagonal/small/
```

保存 raw `.jld2`。

```text
data/processed/unit_internal/linear_diagonal/full_state_identity/small/
```

保存 processed `.jld2`。

```text
data/manifests/linear_diagonal/
```

保存 manifest JSON。

```text
reports/unit_internal/linear_diagonal/plots/smoke/
```

保存 smoke test 图像。

```text
reports/unit_internal/linear_diagonal/logs/
```

保存生成日志。

# 5. Proposed Code Structure

## 5.1 `src/dynamics/linear_diagonal.jl`

```text
## 1. Define parameter container for diagonal linear systems
## 2. Validate eigenvalues, dimension, time step, and trajectory length
## 3. Construct exact discrete propagator A_tau
## 4. Define continuous-time RHS for SciML compatibility
## 5. Generate one trajectory by exact formula
## 6. Generate one trajectory by SciML solver for cross-checking
## 7. Compute analytic solution error and one-step residual
```

## 5.2 `src/observations/full_state.jl`

```text
## 1. Define full-state observation spec assumptions
## 2. Apply identity observation chain U = S = Z = I
## 3. Validate observation dimension and matrix orientation
```

## 5.3 `src/splits/trajectory_split.jl`

```text
## 1. Validate split ratios and trajectory IDs
## 2. Shuffle trajectory IDs with fixed seed
## 3. Assign train / val / test groups
## 4. Check disjointness and full coverage
## 5. Save split dictionary
```

## 5.4 `src/windows/window_builders.jl`

```text
## 1. Define one-step window index format
## 2. Build one-step windows inside each split
## 3. Define rollout window index format
## 4. Build rollout windows inside each split
## 5. Check horizon bounds and split isolation
```

## 5.5 `src/manifests/manifest_writer.jl`

```text
## 1. Collect dataset-level metadata
## 2. Collect system, observation, split, and window metadata
## 3. Collect generated file paths and checksums if available
## 4. Write manifest JSON
## 5. Read back and validate manifest completeness
```

## 5.6 `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`

```text
## 1. Load packages and project source files
## 2. Define or load smoke-test configuration
## 3. Generate raw diagonal-system trajectories
## 4. Apply full-state identity observation
## 5. Save raw and processed data
## 6. Generate trajectory-level split
## 7. Generate one-step and rollout windows
## 8. Run analytic and protocol diagnostics
## 9. Save manifest, logs, and smoke-test plots
## 10. Print final summary
```

# 6. Debugging And Output Plan

## 6.1 必须打印的信息

每次生成时打印：

```text
system_id
state_dim
eigenvalues
dt
trajectory_length
num_trajectories
times size
state_matrix size for first trajectory
observation_matrix size for first trajectory
train / val / test trajectory counts
one-step window counts
rollout window counts
max analytic error
max one-step residual
raw output directory
processed output directory
manifest path
```

## 6.2 关键维度检查

对每条轨线检查：

```text
size(X) == (d, M + 1)
length(times) == M + 1
size(Z) == size(X)
```

窗口读取统一使用：

```text
X[:, m]
Z[:, m]
```

## 6.3 解析误差预期

使用 exact generator 时，`max analytic error` 应接近浮点误差，通常约 `1e-14` 到 `1e-12`。

如果用 `ODEProblem + Tsit5()` cross-check，误差应接近积分容差量级。若明显偏大，需要检查：

1. RHS 参数顺序；
2. `saveat` 是否正确；
3. 初值是否按列 / 行混淆；
4. 时间索引是否从 `m = 1` 对应 `t = 0`。

## 6.4 one-step 残差预期

exact generator 下，`max one-step residual` 应接近机器精度。

如果残差大，优先检查：

1. `A_tau` 构造是否错误；
2. 是否把 `state_matrix[:, m]` 写成了 `state_matrix[m, :]`；
3. 是否混淆 `M` 与 `M + 1`；
4. 保存 / 读取后矩阵是否被转置。

## 6.5 split 检查

必须输出：

```text
train intersect val = empty
train intersect test = empty
val intersect test = empty
train union val union test = all trajectory IDs
```

如果失败，说明 split 逻辑不能进入后续 benchmark。

## 6.6 window 检查

对 one-step：

```text
1 <= m <= M
```

对 rollout horizon `L`：

```text
1 <= s <= M + 1 - L
```

并且每个 window 的 `trajectory_id` 必须属于对应 split 的轨线集合。

## 6.7 图像检查

建议保存三类图：

1. 坐标时间序列图：检查稳定模态是否衰减、不稳定模态是否增长；
2. 解析误差图：检查误差是否在容差附近，而不是随时间系统性漂移；
3. log-amplitude 图：检查每个坐标的 `log(abs(x_i(t)))` 斜率是否接近对应特征值。

# 7. Potential Risks And Debugging Strategies

## 7.1 不稳定模态导致数值爆炸

如果正特征值和时间跨度同时较大，数据会快速增长。

策略：

1. small 难度先限制 `T <= 10`；
2. 初始值范围使用 `[-1, 1]`；
3. manifest 中记录最大绝对值；
4. 超过阈值时打印 warning。

## 7.2 矩阵方向混淆

项目协议要求状态矩阵为：

```text
state_dim x (trajectory_length + 1)
```

策略：

1. 所有诊断打印 `size(X)`；
2. 所有窗口读取统一使用 `X[:, m]`；
3. 单元测试强制检查第一维等于 `state_dim`。

## 7.3 split 泄漏

如果先生成窗口再随机切，会造成训练 / 测试共享同一条轨线的相邻片段。

策略：

1. split 函数只接受 trajectory IDs；
2. window builder 必须接受 split 后的 trajectory ID 集合；
3. 测试中检查每个 window 的 trajectory ID 归属。

## 7.4 JLD2 保存复杂 Julia struct 的长期兼容性

JLD2 可以保存 Julia 对象，但长期 benchmark 更稳妥的做法是保存基础数组和简单字典。

策略：

1. `.jld2` 中保存数组、字符串、数值、向量和简单字典；
2. manifest 用 JSON 保存；
3. 不把函数、闭包、solver 对象直接写入数据文件。

## 7.5 exact generator 与 SciML generator 的语义不一致

如果两套生成器并存，可能出现时间点、容差、初值顺序不一致。

策略：

1. exact generator 作为主数据生成器；
2. SciML generator 只作为 cross-check；
3. 两者都使用同一个 `times = 0:dt:T` 语义；
4. 对第一条轨线打印两者最大误差。

# 8. Stop And Wait For Confirmation

以上是 **线性对角系统最小闭环编码计划**。确认后，优先实现：

1. `src/dynamics/linear_diagonal.jl`
2. `src/observations/full_state.jl`
3. `src/splits/trajectory_split.jl`
4. `src/windows/window_builders.jl`
5. `src/io/jld2_io.jl`
6. `src/manifests/manifest_writer.jl`
7. `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`
8. `test/unit/test_linear_diagonal.jl`
