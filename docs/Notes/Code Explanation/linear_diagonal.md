## 1. Task understanding

我们现在要创建 **ODEs_dataset 的第一个最小系统：线性对角系统**。它应属于 `unit_internal` 内部单元测试层，用来测试最基础的点谱恢复、稳定/不稳定模态分离，以及整个数据协议是否跑通；你的指南也明确把“线性对角、旋转–收缩、Jordan”列为 Stage 0 / Phase 1 的内部测试系统。fileciteturn1file8 fileciteturn1file4

这次不做完整 v1 benchmark，只完成一个最小闭环：

$$
\dot{\mathbf x}=\Lambda \mathbf x,\qquad 
\Lambda=\operatorname{diag}(\lambda_1,\dots,\lambda_d)
$$


生成多条轨线：

$$
\mathbf X^{(q)}=
\begin{bmatrix}
\mathbf x_1^{(q)} & \cdots & \mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in \mathbb R^{d\times(M+1)}
$$


然后通过最简单的全状态观测链：

$$
U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I
$$


得到：

$$
\mathbf Z^{(q)}=\mathbf X^{(q)}
$$


这与文档中“低维 ODE 最简单情形下 $\mathbf z=\mathbf x$”的设定一致。fileciteturn2file0

最终输出应包括：

- raw 状态轨线；
- processed 全状态观测轨线；
- 轨线级 train / val / test split；
- one-step 与 rollout window 索引；
- manifest 元信息；
- smoke test 结果与基础图像。

---

## 2. Task decomposition

### 子任务 A：定义线性对角系统本体

**目的**：提供系统方程、解析离散流、参数校验。

**输入**：

- 状态维数 $d$
- 对角谱 $\lambda_1,\dots,\lambda_d$
- 初值 $\mathbf x_0$
- 采样步长 $\tau$
- 轨线长度 $M$

**输出**：

- 连续时间 RHS：$\dot{\mathbf x}=\Lambda\mathbf x$
- 精确离散传播矩阵：

$$
A_\tau=\operatorname{diag}\left(e^{\lambda_1\tau},\dots,e^{\lambda_d\tau}\right)
$$


- 状态轨线矩阵 $\mathbf X$

**依赖**：无，是最底层动力系统模块。

---

### 子任务 B：定义配置对象

**目的**：让系统不是写死在脚本里，而是通过配置进入数据工厂。

至少需要：

- `SystemSpec`
- `ObservationSpec`
- `SplitSpec`
- `WindowSpec`
- `TaskSpec`
- 一个最小 `BenchmarkSpec`

这些对象正好对应工程文档中定义的数据流水线：系统与参数生成 $\mathbf X$，观测链生成 $\mathbf Z$，然后 split、window、task、metric。fileciteturn2file0

---

### 子任务 C：生成 raw trajectories

**目的**：生成多条完整状态轨线，作为不可污染的原始数据。

**输入**：

- `SystemSpec`
- 随机种子
- 初值采样策略
- 轨线数量 $R$

**输出**：

每条轨线保存为 `RawTrajectory`：

- `trajectory_id`
- `system_id`
- `parameter_instance`
- `initial_condition_instance`
- `times`
- `state_matrix`

工程文档要求原始轨线对象的核心矩阵为：

$$
\mathbf X\in\mathbb K^{d_x\times(M+1)}
$$


即 **状态维度在行，时间快照在列**。fileciteturn1file2

---

### 子任务 D：应用全状态观测链

**目的**：把状态轨线转换成算法入口数据 $\mathbf Z$。

本阶段先只做：

$$
\mathbf z_m=\mathbf x_m
$$


不加噪声、不归一化、不降维。这样可以把后续误差全部归因到数据协议和动力系统生成器，而不是观测链复杂性。

**输出**：

每条轨线保存为 `ObservedTrajectory`：

- `trajectory_id`
- `system_id`
- `observation_id`
- `parameter_instance`
- `initial_condition_instance`
- `state_matrix`
- `observation_matrix`

其中：

$$
\mathbf Z\in\mathbb K^{d_z\times(M+1)}
$$


---

### 子任务 E：生成轨线级 split

**目的**：实现最基本的 `Split-I`，即初值泛化。

文档强调必须先按轨线切分，再在各自集合内部切窗口，不能把同一条轨线的相邻窗口分散到 train 和 test，否则长期传播指标会虚高。fileciteturn2file1

本阶段使用：

$$
70\% / 15\% / 15\%
$$


或小规模 smoke test 用：

$$
80\% / 10\% / 10\%
$$


**输入**：

- 轨线 ID 列表
- split seed
- train / val / test ratio

**输出**：

- `train_trajectory_ids`
- `val_trajectory_ids`
- `test_trajectory_ids`

---

### 子任务 F：生成窗口索引

**目的**：从每个 split 内部生成任务样本。

先实现两种：

#### 一步样本

$$
(\mathbf z_m,\mathbf z_{m+1})
$$


#### 多步 rollout window

$$
(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L})
$$


工程文档中也把 one-step sample 和 rollout window 作为核心数据对象。fileciteturn1file2

---

### 子任务 G：写入 manifest

**目的**：保证每次生成的数据可追踪、可复现、可升级。

manifest 至少记录：

- `dataset_version`
- `system_id`
- `observation_id`
- `split_id`
- `window_id`
- `difficulty_level`
- `solver_name`
- `solver_abstol`
- `solver_reltol`
- `seed`
- `state_dim`
- `eigenvalues`
- `dt`
- `trajectory_length`
- `num_trajectories`
- 文件路径清单

指南建议从第一天就冻结 `benchmark_version`、`system_id`、`split_id`、`observation_mode`、`difficulty_level`、`solver_metadata`，这部分会直接放进 manifest。fileciteturn1file6

---

### 子任务 H：smoke test 与诊断

**目的**：确认第一个系统不是“生成了文件就算成功”，而是能做数学正确性检查。

检查内容包括：

1. 数值轨线与解析解是否一致；
2. 轨线矩阵维度是否为 $d\times(M+1)$；
3. split 是否按轨线划分；
4. window 是否没有跨越 split；
5. one-step 动力学是否满足：

$$
\mathbf x_{m+1}\approx A_\tau \mathbf x_m
$$


6. 保存文件是否能被重新读取；
7. manifest 是否能找到所有数据文件。

---

## 3. Mathematical / algorithmic description

### 3.1 连续系统

采用实对角线性系统：

$$
\dot{\mathbf x}
=
\Lambda \mathbf x,
\qquad
\Lambda
=
\operatorname{diag}(\lambda_1,\dots,\lambda_d)
$$


其中：

$$
\mathbf x(t)\in\mathbb R^d
$$


建议第一版取：

$$
d=4,\qquad
\lambda=(-1.0,-0.3,0.1,0.5)
$$


这样同时包含：

- 快衰减模态；
- 慢衰减模态；
- 慢增长模态；
- 快增长模态。

不过为了避免数据爆炸，初始 smoke test 的时间跨度不要太长。例如：

$$
\tau=0.05,\qquad M=200,\qquad T=10
$$


此时最大增长因子约为：

$$
e^{0.5T}=e^5
$$


还可控。

---

### 3.2 精确解

对每个坐标：

$$
x_i(t)=x_i(0)e^{\lambda_i t}
$$


采样时刻：

$$
t_m=(m-1)\tau,\qquad m=1,\dots,M+1
$$


所以：

$$
x_i(t_m)=x_i(0)e^{\lambda_i(m-1)\tau}
$$


---

### 3.3 离散传播

定义：

$$
A_\tau=e^{\Lambda\tau}
=
\operatorname{diag}(e^{\lambda_1\tau},\dots,e^{\lambda_d\tau})
$$


则：

$$
\mathbf x_{m+1}=A_\tau \mathbf x_m
$$


这个系统非常适合做第一个单元测试，因为真实离散谱就是：

$$
\alpha_i=e^{\lambda_i\tau}
$$


未来如果 EDMD / Koopman / HSKL 对这个系统都恢复不了谱，那么优先怀疑数据协议、字典、归一化、切分或实现错误，而不是动力系统本身。

---

### 3.4 初值采样

建议第一版采用盒采样：

$$
\mathbf x_0^{(q)}\sim \operatorname{Uniform}([-1,1]^d)
$$


为了避免某些模态初始系数过小，导致该谱方向几乎不可见，应加一个简单过滤条件：

$$
\min_i |x_{0,i}^{(q)}| \ge \epsilon_{\mathrm{ic}}
$$


例如：

$$
\epsilon_{\mathrm{ic}}=0.1
$$


这样每个模态在数据里都有可观测能量。

---

### 3.5 观测链

第一版只做全状态观测：

$$
U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I
$$


因此：

$$
\mathbf z_m=\mathbf x_m
$$


此阶段不加 noise、不 normalization，目的是建立“零复杂度观测链”的工程基线。

---

### 3.6 split

先生成完整轨线集合：

$$
\left\{\mathbf Z^{(q)}\right\}_{q=1}^R
$$


然后按轨线 ID 切：

$$
\mathcal R_{\mathrm{train}},
\quad
\mathcal R_{\mathrm{val}},
\quad
\mathcal R_{\mathrm{test}}
$$


之后只在各自集合内部生成窗口。

---

### 3.7 基础 correctness metrics

#### 解析误差

$$
E_{\mathrm{exact}}
=
\max_{q,m}
\left\|
\mathbf x_m^{(q)}
-
\exp(\Lambda t_m)\mathbf x_0^{(q)}
\right\|_\infty
$$


#### 一步残差

$$
E_{\mathrm{step}}
=
\max_{q,m}
\left\|
\mathbf x_{m+1}^{(q)}-A_\tau\mathbf x_m^{(q)}
\right\|_\infty
$$


#### 维度检查

$$
\operatorname{size}(\mathbf X^{(q)})=(d,M+1)
$$


#### split 泄漏检查

$$
\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{val}}
=
\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{test}}
=
\mathcal R_{\mathrm{val}}
\cap
\mathcal R_{\mathrm{test}}
=
\varnothing
$$


---

## 4. Planned packages and documentation

### 必需包

#### `LinearAlgebra`

用于：

- 构造对角矩阵；
- 计算范数；
- 检查谱；
- 计算 $A_\tau=\exp(\Lambda\tau)$ 的对角形式。

这是 Julia 标准库，不需要额外安装。

---

#### `Random`

用于：

- 固定随机种子；
- 采样初值；
- 随机打乱轨线 ID 做 split。

这是 Julia 标准库。

---

#### `DifferentialEquations.jl` / `OrdinaryDiffEq.jl`

虽然线性对角系统可以直接用解析解生成，但我建议保留一个 SciML 积分入口，用于未来系统统一接入。

文档中 `solve(prob::ODEProblem, alg; kwargs)` 是标准求解入口；对非刚性 ODE，官方文档推荐 `Tsit5` 作为常用高效方法。citeturn655530view0

本系统计划：

- 默认数据生成使用解析解；
- smoke test 中可选地用 `ODEProblem + Tsit5()` 生成一条轨线，与解析解比较；
- 未来非线性系统统一走 SciML 积分器。

---

#### `JLD2.jl`

用于保存 `.jld2` 数据文件，包括：

- `times`
- `state_matrix`
- `observation_matrix`
- 简单 metadata dictionary

JLD2 官方文档说明它是纯 Julia 的高性能二进制格式，适合保存 Julia 数组、字典和自定义结构；基础接口支持 `save` / `load`。citeturn655530view1

为了长期兼容，我建议第一版尽量保存 **数组 + Dict + String/Number/List**，不要直接把复杂 Julia 函数或闭包序列化进去。

---

#### `JSON.jl`

用于保存 manifest、split、window 索引等可读元信息。

JSON.jl 官方文档支持 `JSON.parse` / `JSON.parsefile` 读取，以及 `JSON.json` 写入 JSON。citeturn842237search0

相比 JSON3.jl，我更建议用 JSON.jl，因为当前 JSON3.jl GitHub 页面已提示迁移到 JSON.jl v1；因此 manifest 这类长期元数据更适合用 JSON.jl。

---

#### `Plots.jl`

用于 smoke test 图像：

- 每个坐标随时间变化；
- 数值解与解析解误差；
- 模态增长/衰减曲线。

这个包不是核心生成依赖，可以只在 smoke test / report 中使用。

---

## 5. Directory & File Plan

按照你的 ODEs_dataset 工程文档，这次建议新增或修改如下文件。

### 配置层

```text
configs/systems/linear_diagonal_small.json
```

定义：

- `system_id = "linear_diagonal"`
- `family = "unit_internal"`
- `state_dim = 4`
- `eigenvalues = [-1.0, -0.3, 0.1, 0.5]`
- `dt = 0.05`
- `trajectory_length = 200`
- `num_trajectories = 64`
- `solver_name = "exact_diagonal"`
- `difficulty_level = "small"`

```text
configs/observations/full_state_identity.json
```

定义：

- `observation_id = "full_state_identity"`
- `mode = "full_state"`
- `noise_model = "none"`
- `normalization_policy = "none"`
- `output_dim = 4`

```text
configs/splits/split_I_70_15_15_seed1.json
```

定义：

- `split_type = "initial_condition"`
- `grouping_unit = "trajectory"`
- `train_ratio = 0.70`
- `val_ratio = 0.15`
- `test_ratio = 0.15`

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

---

### 源码层

```text
src/dynamics/linear_diagonal.jl
```

职责：

- 定义线性对角系统参数；
- 提供 RHS；
- 提供解析传播；
- 提供单条轨线生成函数；
- 提供谱和维度校验。

```text
src/observations/full_state.jl
```

职责：

- 实现 $U=S=Z=I$；
- 返回 `observation_matrix = state_matrix` 的安全拷贝或视图；
- 检查输出维度。

```text
src/datasets/trajectory_types.jl
```

职责：

- 定义轻量数据对象；
- 至少包括 `RawTrajectory` 与 `ObservedTrajectory`；
- 第一版可以用 `NamedTuple` 或简单 `struct`，但保存时转为基础字典。

```text
src/splits/trajectory_split.jl
```

职责：

- 输入轨线 ID；
- 按 seed 洗牌；
- 输出 train / val / test 轨线 ID；
- 检查无交集、全覆盖。

```text
src/windows/window_builders.jl
```

职责：

- 从 split 内轨线构造 one-step index；
- 从 split 内轨线构造 rollout index；
- 不直接复制大矩阵，只保存索引协议。

```text
src/io/jld2_io.jl
```

职责：

- 保存 raw / processed `.jld2`；
- 读取 `.jld2`；
- 检查文件是否存在。

```text
src/manifests/manifest_writer.jl
```

职责：

- 写入 manifest JSON；
- 记录配置、数据路径、seed、solver metadata；
- 提供 manifest 校验函数。

```text
src/diagnostics/linear_system_checks.jl
```

职责：

- 解析解误差；
- one-step 残差；
- split 泄漏检查；
- window 合法性检查；
- 基本统计量。

---

### 生成入口与 smoke test

```text
experiments/smoke_tests/generate_linear_diagonal_smoke.jl
```

职责：

- 加载配置；
- 生成 raw trajectories；
- 生成 processed trajectories；
- 生成 split；
- 生成 windows；
- 写 manifest；
- 打印诊断信息；
- 保存基础图像。

```text
test/unit/test_linear_diagonal.jl
```

职责：

- 小规模自动测试；
- 只生成极少轨线；
- 检查解析误差、维度、split、window、文件读写。

---

### 数据输出

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
reports/plots/linear_diagonal/smoke/
```

保存 smoke test 图像。

```text
reports/logs/linear_diagonal/
```

保存生成日志。

---

## 6. Proposed code structure

后续真正写代码时，每个文件会使用明确的 `##` 分节。计划如下。

### `src/dynamics/linear_diagonal.jl`

```text
## 1. Define parameter container for diagonal linear systems
## 2. Validate eigenvalues, dimension, time step, and trajectory length
## 3. Construct exact discrete propagator A_tau
## 4. Define continuous-time RHS for SciML compatibility
## 5. Generate one trajectory by exact formula
## 6. Generate one trajectory by SciML solver for cross-checking
## 7. Compute analytic solution error and one-step residual
```

---

### `src/observations/full_state.jl`

```text
## 1. Define full-state observation spec assumptions
## 2. Apply identity observation chain U = S = Z = I
## 3. Validate observation dimension and matrix orientation
```

---

### `src/splits/trajectory_split.jl`

```text
## 1. Validate split ratios and trajectory IDs
## 2. Shuffle trajectory IDs with fixed seed
## 3. Assign train / val / test groups
## 4. Check disjointness and full coverage
## 5. Save split dictionary
```

---

### `src/windows/window_builders.jl`

```text
## 1. Define one-step window index format
## 2. Build one-step windows inside each split
## 3. Define rollout window index format
## 4. Build rollout windows inside each split
## 5. Check horizon bounds and split isolation
```

---

### `src/manifests/manifest_writer.jl`

```text
## 1. Collect dataset-level metadata
## 2. Collect system, observation, split, and window metadata
## 3. Collect generated file paths and checksums if available
## 4. Write manifest JSON
## 5. Read back and validate manifest completeness
```

---

### `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`

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

---

## 7. Debugging and output plan

### 7.1 必须打印的信息

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

---

### 7.2 关键维度检查

对每条轨线：

$$
\operatorname{size}(\mathbf X)=(d,M+1)
$$


$$
\operatorname{length}(\mathbf t)=M+1
$$


全状态观测下：

$$
\operatorname{size}(\mathbf Z)=\operatorname{size}(\mathbf X)
$$


---

### 7.3 解析误差预期

如果使用 exact generator：

$$
E_{\mathrm{exact}}\approx 0
$$


通常只会有浮点误差，约 $10^{-14}$ 到 $10^{-12}$。

如果用 `ODEProblem + Tsit5()` cross-check：

$$
E_{\mathrm{exact}}
$$


应接近积分容差量级。如果误差明显大于 `abstol/reltol` 对应尺度，需要检查：

- RHS 参数顺序；
- `saveat` 是否正确；
- 初值是否按列/行混淆；
- 时间索引是否从 $m=1$ 对应 $t=0$。

---

### 7.4 one-step 残差预期

exact generator 下：

$$
E_{\mathrm{step}}
=
\max_{q,m}
\|\mathbf x_{m+1}^{(q)}-A_\tau\mathbf x_m^{(q)}\|_\infty
$$


应接近机器精度。

如果残差大：

- 可能是 $A_\tau$ 构造错误；
- 可能是 `state_matrix[:, m]` 与 `state_matrix[m, :]` 搞反；
- 可能是时间点数量 $M$ 与 $M+1$ 混淆；
- 可能是保存/读取后矩阵被转置。

---

### 7.5 split 检查

必须输出：

```text
train ∩ val = empty
train ∩ test = empty
val ∩ test = empty
train ∪ val ∪ test = all trajectory IDs
```

如果失败，说明 split 逻辑不能进入后续 benchmark。

---

### 7.6 window 检查

对 one-step：

$$
1\le m\le M
$$


对 rollout horizon $L$：

$$
1\le s\le M+1-L
$$


并且每个 window 的 `trajectory_id` 必须属于对应 split 的轨线集合。

---

### 7.7 图像检查

建议保存三类图：

1. **坐标时间序列图**  
   检查稳定模态是否衰减、不稳定模态是否增长。

2. **解析误差图**  
   检查误差是否在容差附近，而不是随时间系统性漂移。

3. **log-amplitude 图**  
   对每个坐标画：

$$
\log |x_i(t)|
$$


   理想情况下斜率应接近 $\lambda_i$。这是线性对角系统最直观的谱诊断。

---

## 8. Potential risks and debugging strategies

### 风险 1：不稳定模态导致数值爆炸

如果 $\lambda_i>0$ 且 $T$ 太长，数据会快速增长。

策略：

- small 难度先限制 $T\le 10$；
- 初始值范围用 $[-1,1]$；
- manifest 中记录最大绝对值；
- 如果超过阈值，打印 warning。

---

### 风险 2：矩阵方向混淆

项目协议要求：

$$
\mathbf X\in\mathbb R^{d\times(M+1)}
$$


Julia 中很多人容易写成 `(M+1, d)`。

策略：

- 所有诊断打印 `size(X)`；
- 所有窗口读取统一使用 `X[:, m]`；
- 单元测试强制检查第一维等于 `state_dim`。

---

### 风险 3：split 泄漏

如果先生成窗口再随机切，会造成训练/测试共享同一条轨线的相邻片段。

策略：

- split 函数只接受 trajectory IDs；
- window builder 必须接受 split 后的 trajectory ID 集合；
- 测试中检查每个 window 的 trajectory ID 归属。

---

### 风险 4：JLD2 保存复杂 Julia struct 的长期兼容性

JLD2 可以保存 Julia 对象，但长期 benchmark 更稳妥的做法是保存基础数组和简单字典。

策略：

- `.jld2` 中保存数组、字符串、数值、向量；
- manifest 用 JSON 保存；
- 不把函数、闭包、solver 对象直接写入数据文件。

---

### 风险 5：exact generator 与 SciML generator 的语义不一致

如果两套生成器并存，可能出现时间点、容差、初值顺序不一致。

策略：

- exact generator 作为主数据生成器；
- SciML generator 只作为 cross-check；
- 两者都使用同一个 `times = 0:dt:T`；
- 对第一条轨线打印两者最大误差。

---

## 9. Stop and wait for confirmation

以上是我建议的 **线性对角系统最小闭环编码计划**。确认后，我会按这个计划开始写 Julia 代码，并优先给出这些文件：

1. `src/dynamics/linear_diagonal.jl`
2. `src/observations/full_state.jl`
3. `src/splits/trajectory_split.jl`
4. `src/windows/window_builders.jl`
5. `src/io/jld2_io.jl`
6. `src/manifests/manifest_writer.jl`
7. `experiments/smoke_tests/generate_linear_diagonal_smoke.jl`
8. `test/unit/test_linear_diagonal.jl`