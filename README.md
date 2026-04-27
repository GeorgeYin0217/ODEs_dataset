# ODEs_dataset

这是一个用 Julia 构建的 ODE 测试数据集与 benchmark 工程。

它不是单纯存几份样本文件的仓库，而是把一套可复现的数据流程固定下来：

1. 选择一个 ODE 系统。
2. 按配置采样参数和初值。
3. 生成原始状态轨线。
4. 通过观测链得到算法输入数据。
5. 按轨线划分 train / val / test。
6. 从各个 split 内部生成 one-step、rollout 等窗口索引。
7. 写入 manifest、诊断结果和基础图像。

目前已经接入的第一个对象是内部测试用的 `linear_diagonal`。后续项目会继续加入旋转-收缩、Jordan / 非正规系统，以及 v1 核心 ODE benchmark 系统。

## 一句话版

如果你只想确认项目能跑，打开终端进入项目根目录，然后执行：

```powershell
julia --project=. experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

如果你想正式生成当前已经实现的 `linear_diagonal` 数据对象，执行：

```powershell
julia --project=. src/generators/generate_linear_diagonal.jl
```

如果你想跑单元测试，执行：

```powershell
julia --project=. test/unit/test_linear_diagonal.jl
```

第一次运行前，如果 Julia 提示缺依赖，先执行：

```powershell
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## 项目现在有什么

当前版本实现了一个最小闭环：`unit_internal / linear_diagonal / small`。

它会生成：

- 64 条原始状态轨线；
- 64 条全状态观测轨线；
- 一个轨线级 train / val / test split；
- one-step window 索引；
- rollout window 索引；
- manifest JSON；
- 两张基础诊断图。

这个对象只是第一个内部测试对象，不是整个数据集的终点。它的作用是先把最基础的数据协议跑通，方便后续接入更多 ODE 系统。

长期规划中，系统分三层：

- `unit_internal`：内部单元测试系统，例如线性对角、旋转-收缩、Jordan / 非正规系统。
- `v1_core`：公开 benchmark 主集合，例如 Van der Pol、Duffing、Lotka-Volterra、FitzHugh-Nagumo、Lorenz 63、Rossler、Lorenz 96。
- `v1_plus`：扩展挑战集合，例如 Robertson、摆系统、多自由度弹簧链、耦合振子网络。

## 目录怎么读

### `configs/`

这里放声明式配置。一般来说，你应该先看这里，再看代码。

- `configs/systems/`：系统配置，例如维度、参数、步长、轨线长度、轨线条数。
- `configs/observations/`：观测配置，例如全状态、部分观测、线性混合、加噪声。
- `configs/splits/`：数据切分配置，例如 train / val / test 比例和随机种子。
- `configs/windows/`：窗口配置，例如 one-step 或 rollout horizon。
- `configs/tasks/`：任务配置，例如一步预测、多步 rollout。
- `configs/benchmarks/`：把系统、观测、split、window、task 组合成一次 benchmark。
- `configs/releases/`：未来正式发布版本的配置清单。

### `src/`

这里放 Julia 源码。

- `src/dynamics/`：ODE 系统本体和轨线生成逻辑。
- `src/observations/`：观测链逻辑，把状态轨线变成算法输入。
- `src/generators/`：正式数据生成入口。
- `src/datasets/`：轨线数据对象。
- `src/splits/`：轨线级 train / val / test 切分。
- `src/windows/`：从轨线内部生成窗口索引。
- `src/diagnostics/`：基础正确性检查和统计摘要。
- `src/manifests/`：manifest 读写和校验。
- `src/io/`：数据文件读写。
- `src/tasks/`：未来任务对象构造逻辑。
- `src/registries/`：未来系统、任务、指标注册表。
- `src/utils/`：通用辅助函数。

### `data/`

这里是运行脚本后产生的数据。

- `data/raw/`：原始状态轨线，通常是 `.jld2` 文件。
- `data/processed/`：观测链处理后的轨线，通常也是 `.jld2` 文件。
- `data/manifests/`：manifest、split、window 索引等 JSON 元信息。
- `data/releases/`：未来正式发布包。

注意：`data/raw/` 和 `data/processed/` 里的大文件默认不进 git；manifest 可以保留，用来记录生成结果。

### `experiments/`

这里放实验入口和轻量检查脚本。

- `experiments/smoke_tests/`：最小 smoke test，先确认协议和生成器能跑通。
- `experiments/baseline_forecasting/`：未来一步预测、多步预测基线。
- `experiments/baseline_identification/`：未来系统辨识基线。
- `experiments/baseline_representation/`：未来表示学习基线。

### `reports/`

这里放运行后产生的报告。

- `reports/plots/`：图像，例如坐标时间序列图、log-amplitude 图。
- `reports/tables/`：未来指标表格。
- `reports/logs/`：日志文件。

### `docs/`

这里放项目说明和设计文档。

- `docs/Project Guide/`：项目设计计划书。
- `docs/spec/`：更稳定的规范文档和注册表草案。
- `docs/Notes/`：开发过程中的笔记、解释、临时计划。

### `test/`

这里放测试。

- `test/unit/`：单元测试。
- `test/integration/`：未来集成测试。
- `test/regression/`：未来回归测试。

## 运行后会生成什么

执行 smoke 脚本：

```powershell
julia --project=. experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

会生成或更新：

```text
data/raw/unit_internal/linear_diagonal/small/
data/processed/unit_internal/linear_diagonal/full_state_identity/small/
data/manifests/linear_diagonal/small/linear_diagonal_smoke_manifest.json
reports/plots/linear_diagonal/smoke/
```

执行正式生成脚本：

```powershell
julia --project=. src/generators/generate_linear_diagonal.jl
```

会生成或更新：

```text
data/raw/unit_internal/linear_diagonal/small/
data/processed/unit_internal/linear_diagonal/full_state_identity/small/
data/manifests/linear_diagonal/small/linear_diagonal_manifest.json
reports/plots/linear_diagonal/diagnostics/
```

生成过程结束时，终端会打印：

- 系统 ID；
- 状态维数；
- 轨线长度；
- 轨线条数；
- 第一条轨线矩阵大小；
- train / val / test 轨线数量；
- one-step 和 rollout window 数量；
- 解析误差；
- one-step 残差；
- raw / processed / manifest 路径。

对当前 `linear_diagonal` 对象，正常情况下你应该看到解析误差接近 `0`，one-step 残差接近机器精度。

## 数据文件怎么看

### 原始轨线

位置示例：

```text
data/raw/unit_internal/linear_diagonal/small/linear_diagonal_traj_0001.jld2
```

里面主要保存：

- `trajectory_id`
- `system_id`
- `parameter_instance`
- `initial_condition_instance`
- `times`
- `state_matrix`

### 处理后轨线

位置示例：

```text
data/processed/unit_internal/linear_diagonal/full_state_identity/small/linear_diagonal_traj_0001.jld2
```

里面主要保存：

- `trajectory_id`
- `system_id`
- `observation_id`
- `parameter_instance`
- `initial_condition_instance`
- `state_matrix`
- `observation_matrix`

当前全状态观测下，`observation_matrix` 和 `state_matrix` 数值相同。以后加入部分观测、线性传感器、噪声观测后，它们就不一定相同。

### Manifest

位置示例：

```text
data/manifests/linear_diagonal/small/linear_diagonal_manifest.json
```

manifest 是这次数据生成的总说明书。它会记录：

- 数据集版本；
- 系统 ID；
- 观测 ID；
- split ID；
- window ID；
- task ID；
- 轨线数量；
- 轨线长度；
- 随机种子；
- solver 信息；
- 生成文件路径；
- 诊断指标。

如果以后要复现实验，优先从 manifest 找信息。

## 推荐工作流

如果你只是使用当前数据集：

1. 运行 `Pkg.instantiate()` 安装依赖。
2. 运行 smoke 脚本，确认环境没问题。
3. 运行正式 generator，生成数据和 manifest。
4. 查看 `data/manifests/` 确认生成结果。
5. 查看 `reports/plots/` 确认图像是否正常。
6. 下游算法只读取 `data/processed/` 和对应 split/window JSON。

如果你要新增一个 ODE 系统：

1. 在 `configs/systems/` 新增系统配置。
2. 在 `src/dynamics/` 新增系统生成逻辑。
3. 至少接一份 `configs/observations/` 观测配置。
4. 复用或新增 split/window/task 配置。
5. 在 `src/generators/` 新增正式生成脚本。
6. 在 `experiments/smoke_tests/` 新增 smoke 脚本。
7. 在 `test/unit/` 或 `test/integration/` 新增测试。
8. 跑通后检查 manifest、plots 和测试结果。

新增系统时不要绕过配置文件把参数写死在实验脚本里。这个项目的核心约定是：系统、观测、切分、窗口、任务都要能通过配置追踪。

## 重要约定

- 先按整条轨线划分 train / val / test，再在各个 split 内部生成窗口。
- 不要先把所有窗口打乱再切分，否则同一条轨线的相邻片段可能同时进入训练集和测试集。
- 原始状态轨线放在 `data/raw/`。
- 观测后的算法输入放在 `data/processed/`。
- split、window、manifest 放在 `data/manifests/`。
- 图像和表格放在 `reports/`。
- 新系统应该新增配置和模块，而不是修改旧系统的语义。
- 正式版本只新增，不破坏旧版本可复现性。

## 当前可运行命令

安装依赖：

```powershell
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

生成 linear diagonal smoke 数据：

```powershell
julia --project=. experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

正式生成 linear diagonal 数据：

```powershell
julia --project=. src/generators/generate_linear_diagonal.jl
```

运行 linear diagonal 单元测试：

```powershell
julia --project=. test/unit/test_linear_diagonal.jl
```

## 当前状态

已实现：

- `unit_internal / linear_diagonal / small`
- 全状态 identity observation
- `Split-I` 初值泛化切分
- one-step window
- rollout window
- raw / processed JLD2 输出
- manifest JSON 输出
- smoke plots 和 diagnostics plots
- linear diagonal 单元测试

下一步建议：

- 接入 `unit_internal / rotation_contraction`
- 接入 `unit_internal / jordan_nonnormal`
- 抽象更多通用配置对象
- 实现部分观测和线性混合观测
- 实现 v1-core 的第一个非线性系统
