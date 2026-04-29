下面给出 **Step 2：FitzHugh–Nagumo 详细代码工程计划书**。本计划严格按 ODEs_dataset 的协议思路来组织：新增系统应接入统一的 `SystemSpec / ObservationSpec / SplitSpec / WindowSpec / TaskSpec / BenchmarkSpec` 流水线，原始轨线与处理后轨线分离保存，且必须先按整条轨线切分，再在各 split 内部派生窗口。FitzHugh–Nagumo 本身属于你当前 `v1_core` 主集合中承担“快慢结构、激发阈值、尖峰–恢复动力学”角色的系统。fileciteturn5file1 fileciteturn5file0

## 1. Confirmed task summary

确认后的对象是：

- 二维自治标准 FitzHugh–Nagumo；
- 全状态观测；
- 固定参数；
- 第一版不做参数泛化、不做部分观测、不做噪声版；
- 先完成可复现的数据生成、诊断、切分、窗口与 manifest 记录。

我建议把 **正式版本** 的固定参数放在 **excitable / threshold-driven** 风格，而不是持续极限环主导版本。这样它和 Van der Pol 的任务分工更清楚：Van der Pol 偏平滑极限环，FHN 偏快慢阈值触发与 spike–recovery。若后续需要 oscillatory 版，只替换 `SystemSpec.default_parameters` 与初值域，不改协议层。fileciteturn5file0

---

## 2. Task decomposition

整体拆成 10 个子任务：

1. 明确系统规格与参数实例  
2. 实现 FHN 动力系统右端与平衡点相关诊断  
3. 设计初值域与采样策略  
4. 生成原始状态轨线 `RawTrajectory`  
5. 施加恒等观测链生成 `ObservedTrajectory`  
6. 生成轨线级 split  
7. 生成 one-step / rollout / statistics 三类窗口  
8. 计算系统专属数据质量诊断  
9. 写入 manifest、registry 与 benchmark 配置  
10. 建立 smoke test、integration test、regression test

---

## 3. Sub-task specification

### 子任务 A：系统规格确认

**Purpose**  
把 FHN 纳入统一配置对象，固定其数学定义、参数实例、时间步长、轨线长度、求解器容差和随机种子策略。

**Input**  
系统方程
$$

\dot v = v-\frac{v^3}{3}-w+I,\qquad
\dot w = \varepsilon(v+a-bw),

$$
以及固定参数
$$

\mu=(a,b,\varepsilon,I).

$$

**Output**  
一个 `SystemSpec` 配置对象。

**Dependency**  
无。

**Relevant expression**  
状态
$$

\mathbf x(t)=\begin{bmatrix}v(t)\\ w(t)\end{bmatrix}\in\mathbb R^2.

$$

**Diagnostic checks**  
- `state_dim == 2`
- `parameter_names == [a,b,ε,I]`
- `trajectory_length`、`dt`、`tspan` 一致
- 固定参数实例被正确写入 manifest

---

### 子任务 B：动力系统模块与平衡点诊断

**Purpose**  
实现 FHN 右端函数与辅助诊断函数，不直接生成数据，只提供系统本体。

**Input**  
$(v,w)$、$(a,b,\varepsilon,I)$。

**Output**  
- 连续时间右端 $\mathbf f(\mathbf x;\mu)$
- 平衡点求解辅助量
- Jacobian 辅助量
- nullcline 辅助量

**Dependency**  
子任务 A。

**Relevant expression**  
平衡点满足
$$

w_\ast=\frac{v_\ast+a}{b},\qquad
v_\ast-\frac{v_\ast^3}{3}-\frac{v_\ast+a}{b}+I=0.

$$
Jacobian
$$

J(v,w)=
\begin{bmatrix}
1-v^2 & -1\\
\varepsilon & -\varepsilon b
\end{bmatrix}.

$$

**Diagnostic checks**  
- 平衡点方程残差足够小
- Jacobian 元素数值有限
- nullcline 计算无 NaN / Inf

---

### 子任务 C：初值域设计

**Purpose**  
构造适合 FHN 的轨线族，而不是只在一点附近做微扰。

**Input**  
固定参数、平衡点位置、目标动力学风格。

**Output**  
`initial_condition_domain` 与采样策略。

**Dependency**  
子任务 B。

**Relevant expression**  
初值
$$

\mathbf x_0^{(q)}\in\Omega_{\mathrm{ic}}\subset\mathbb R^2,\qquad q=1,\dots,Q.

$$

**Diagnostic checks**  
- 初值域覆盖平衡点附近与阈值附近
- 轨线中既有小扰动响应，也有明显 excursion
- 若正式版为 excitable，则不应全部退化成近线性小振动

---

### 子任务 D：原始轨线生成

**Purpose**  
数值积分得到状态轨线，并保存为 `RawTrajectory`。

**Input**  
`SystemSpec`、参数实例、初值实例、积分设置。

**Output**  
- `times ∈ R^{M+1}`
- `state_matrix X^{(q)} ∈ R^{2×(M+1)}`

**Dependency**  
子任务 A、B、C。

**Relevant expression**  
$$

\mathbf x_{m+1}=\mathbf F^\tau(\mathbf x_m),\qquad
\mathbf X^{(q)}=
[\mathbf x_1^{(q)},\dots,\mathbf x_{M+1}^{(q)}].

$$

**Diagnostic checks**  
- 列数为 $M+1$
- 行数为 2
- 时间网格严格递增
- 轨线数值全为有限实数
- 求解器返回成功状态
- 轨线不存在异常截断

---

### 子任务 E：观测链处理

**Purpose**  
把状态轨线映射成算法统一输入对象。

**Input**  
`RawTrajectory` 与 `ObservationSpec`。

**Output**  
`ObservedTrajectory`，其中
$$

\mathbf z_m=\mathbf x_m,\qquad
\mathbf Z^{(q)}=\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

**Dependency**  
子任务 D。

**Relevant expression**  
本版本取
$$

U=S=Z=\mathcal I.

$$

**Diagnostic checks**  
- `output_dim == 2`
- `observation_matrix == state_matrix`
- 观测链 metadata 正确记录为 full_state_identity

---

### 子任务 F：split 生成

**Purpose**  
按轨线而不是按窗口切分 train / val / test。

**Input**  
全部 `ObservedTrajectory` 集合。

**Output**  
轨线级 `SplitSpec` 与 split 索引文件。

**Dependency**  
子任务 E。

**Relevant expression**  
默认采用 `Split-I`：
- 参数固定；
- 训练、验证、测试只在初值上区分。

推荐比例：
$$

70\% / 15\% / 15\%.

$$

**Diagnostic checks**  
- 同一 `trajectory_id` 只属于一个 split
- split 前后轨线总数守恒
- 每个 split 至少含有足够多的 excursion 轨线
- 不允许先切窗口再切 split。这个顺序是协议硬约束。fileciteturn5file1

---

### 子任务 G：窗口派生

**Purpose**  
从各 split 内部派生标准任务对象。

**Input**  
每个 split 的 `ObservedTrajectory`。

**Output**  
- `OneStepSample`
- `RolloutWindowSample`
- `StatisticsWindowSample`

**Dependency**  
子任务 F。

**Relevant expression**  
一步样本：
$$

(\mathbf z_m,\mathbf z_{m+1}).

$$
rollout 窗口：
$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$
statistics 窗口：
$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1}).

$$

**Diagnostic checks**  
- 所有窗口都不跨轨线边界
- horizon 合法
- `start_index + horizon ≤ M+1`
- 不同窗口类型的样本数与理论值一致

---

### 子任务 H：系统专属诊断

**Purpose**  
为 FHN 增加比通用 ODE 更有针对性的质量检查。

**Input**  
原始轨线、观测轨线、平衡点与 nullcline 信息。

**Output**  
诊断表与诊断图。

**Dependency**  
子任务 D、E、G。

**Relevant expression**  
建议至少计算：
- 平衡点残差；
- 峰值统计 `max(v)`；
- 恢复变量范围 `min/max(w)`；
- 轨线是否越过激发阈值；
- 若有多 spike，则统计 ISI；
- 相图中轨线与两条 nullcline 的相对位置。

**Diagnostic checks**  
- 至少部分轨线出现明显快跃迁
- 轨线不会全部塌缩成平衡点附近的短小摆动
- 相图覆盖符合 FHN 预期几何

---

### 子任务 I：manifest 与 benchmark 注册

**Purpose**  
保证系统进入可复现发布链。

**Input**  
系统配置、观测配置、split 配置、窗口配置、任务配置、版本信息。

**Output**  
- `ReleaseManifest`
- `system_registry`
- `benchmark_config`

**Dependency**  
A–H。

**Relevant expression**  
固定流水线：
$$

(\mathbf f,\mu,\mathbf x_0,\tau)\Longrightarrow
\mathbf X\Longrightarrow
\mathbf Z\Longrightarrow
\text{splits}\Longrightarrow
\text{windows}\Longrightarrow
\text{tasks}\Longrightarrow
\text{metrics}.

$$

**Diagnostic checks**  
- manifest 中 system_id / observation_id / split_id / window_id / task_id 一致
- generator commit hash、seed policy、solver metadata 已记录
- release 文件能唯一复现实验

---

### 子任务 J：测试体系

**Purpose**  
保证后续修改不会破坏 FHN 数据生成链。

**Input**  
小规模 smoke 配置与固定 reference 输出。

**Output**  
- smoke 脚本
- unit / integration / regression 测试

**Dependency**  
A–I。

**Relevant expression**  
小规模 smoke 只验证协议正确性，不追求统计充分性；正式版依赖 release 配置生成。

**Diagnostic checks**  
- 轨线数量、样本数量、split 大小固定
- 若 reference manifest 未变，核心统计量偏移不得超阈值
- 任何协议层修改都必须先过 smoke / integration / regression 三层测试。fileciteturn5file1

---

## 4. Directory and file plan

下面给出建议新增或修改的目标路径。

### 文档层

- `docs/notes/mathematical explanation/fitzhugh_nagumo.md`  
  保存本次数学说明书。

- `docs/notes/code explanation/fitzhugh_nagumo_plan.md`  
  保存本次任务计划书。

- `docs/spec/object_registry.md`  
  追加一条 FHN 对象注册记录：系统定位、参数版本、观测模式、split、发布时间。

- `docs/spec/project_task_list.md`  
  追加本次任务完成状态与后续扩展任务。

### 配置层

- `configs/systems/fitzhugh_nagumo_fixed_excitable_v1.json`  
  FHN 的固定参数系统配置；包含 `state_dim=2`、参数实例、初值域、`dt`、`tspan`、`trajectory_length`、solver 与 seed policy。

- `configs/observations/fullstate_identity_2d.json`  
  若项目中尚无通用全状态观测配置，则新增；若已有，直接复用，不再创建新文件。

- `configs/splits/split_i_trajectory_70_15_15.json`  
  若已有通用 `Split-I` 则复用；若没有则新增。

- `configs/windows/one_step_default.json`  
  一步样本窗口；优先复用。

- `configs/windows/rollout_short.json`  
  短期 rollout 配置。

- `configs/windows/rollout_medium.json`  
  中期 rollout 配置。

- `configs/windows/statistics_fhn_default.json`  
  为 FHN 统计窗口设定合适 horizon。

- `configs/tasks/one_step_forecast.json`  
  若已有则复用。

- `configs/tasks/multi_step_rollout.json`  
  若已有则复用。

- `configs/tasks/long_time_statistics.json`  
  若已有则复用。

- `configs/benchmarks/fitzhugh_nagumo_fixed_fullstate_splitI.json`  
  把系统、观测、split、windows、tasks 组合成一次标准 benchmark。

- `configs/releases/odes_dataset_fitzhugh_nagumo_v1.json`  
  冻结本次正式版发布对象。

### 源码层

- `src/dynamics/fitzhugh_nagumo.jl`  
  系统右端、平衡点辅助、Jacobian、nullcline 辅助。

- `src/generators/generate_fitzhugh_nagumo.jl`  
  调用通用生成流水线的系统级包装器；如果项目已有统一 generator 入口，则此文件可以只保留系统专属参数校验与调用桥接。

- `src/diagnostics/fitzhugh_nagumo_diagnostics.jl`  
  FHN 专属数据质量检查与图表统计。

- `src/registries/system_registry.jl`  
  追加 FHN 条目到 `v1_core`。

- `src/registries/benchmark_registry.jl`  
  追加本系统 benchmark 条目。

- `src/manifests/release_manifest_builders.jl`  
  若已有通用 manifest builder，仅做注册，不新增文件；若没有则把 FHN 接入此层。

### 实验入口

- `experiments/smoke_tests/generate_fitzhugh_nagumo_smoke.jl`  
  小规模生成与协议检查入口。

正式版生成我更建议通过 **通用生成入口 + `configs/benchmarks/...` + `configs/releases/...`** 触发，而不是再为正式版单独写一份一次性脚本。这样更符合“协议先于系统”的工程原则。fileciteturn5file1

### 数据输出层

- `data/raw/fitzhugh_nagumo/fixed_excitable_v1/...`
- `data/processed/fitzhugh_nagumo/fixed_excitable_v1/...`
- `data/manifests/fitzhugh_nagumo/fixed_excitable_v1/...`
- `data/releases/odes_dataset_fitzhugh_nagumo_v1/...`

### 报告输出层

- `reports/v1_core/fitzhugh_nagumo_formal/plots/...`
- `reports/v1_core/fitzhugh_nagumo_formal/tables/...`
- `reports/v1_core/fitzhugh_nagumo_formal/logs/...`

### 测试层

- `test/unit/test_fitzhugh_nagumo_dynamics.jl`
- `test/integration/test_fitzhugh_nagumo_pipeline.jl`
- `test/regression/test_fitzhugh_nagumo_smoke_regression.jl`

---

## 5. Module / component responsibilities

- `src/dynamics/`  
  只负责系统方程与系统几何辅助量，不负责文件写入。

- `src/observations/`  
  负责 $U,S,Z$ 观测链；本任务仅用恒等观测。

- `src/generators/`  
  负责从配置出发生成轨线对象，调度求解器与保存流程。

- `src/datasets/`  
  定义 `RawTrajectory`、`ObservedTrajectory`、各类窗口样本对象。

- `src/splits/`  
  负责轨线级划分，不碰系统求解。

- `src/windows/`  
  负责从 split 后轨线派生 one-step / rollout / statistics 样本。

- `src/tasks/`  
  把窗口对象绑定到 benchmark 任务定义。

- `src/diagnostics/`  
  负责 FHN 专属的峰值、阈值、相图覆盖、nullcline 关系等检查。

- `src/manifests/`  
  负责生成可复现元数据。

- `src/io/`  
  负责统一路径与读写。

- `src/registries/`  
  负责把 FHN 接入 `v1_core` 注册表。ODEs_dataset 的系统注册分层、对象配置与发布冻结规则都在代码指南里已有固定框架。fileciteturn5file1

---

## 6. Planned `##` sections

下面只列计划中的 Julia 文件标题结构，不写代码。

### `src/dynamics/fitzhugh_nagumo.jl`

- `## System identity and exported symbols`
- `## Standard FitzHugh–Nagumo parameter container`
- `## Continuous-time right-hand side`
- `## Equilibrium equation and residual`
- `## Jacobian at arbitrary state`
- `## Nullcline evaluators`
- `## Parameter validation and regime sanity checks`

### `src/generators/generate_fitzhugh_nagumo.jl`

- `## Generator purpose and supported configs`
- `## Load SystemSpec and observation config`
- `## Sample initial conditions`
- `## Integrate trajectories`
- `## Build RawTrajectory objects`
- `## Apply observation chain and build ObservedTrajectory`
- `## Save raw data processed data and manifests`
- `## Emit generation summary diagnostics`

### `src/diagnostics/fitzhugh_nagumo_diagnostics.jl`

- `## Diagnostic scope and expected outputs`
- `## Equilibrium and nullcline diagnostics`
- `## Time-series amplitude diagnostics`
- `## Threshold crossing and spike counting`
- `## Phase-portrait coverage diagnostics`
- `## Split-level summary tables`
- `## Plot builders for reports`

### `experiments/smoke_tests/generate_fitzhugh_nagumo_smoke.jl`

- `## Smoke objective and reduced configuration`
- `## Resolve benchmark config`
- `## Run generation pipeline`
- `## Check object counts and dimensions`
- `## Run lightweight diagnostics`
- `## Save smoke report and exit summary`

### `test/unit/test_fitzhugh_nagumo_dynamics.jl`

- `## Parameter validation tests`
- `## RHS dimension and finiteness tests`
- `## Equilibrium residual tests`
- `## Jacobian consistency tests`

### `test/integration/test_fitzhugh_nagumo_pipeline.jl`

- `## End-to-end generation setup`
- `## Raw and observed trajectory creation tests`
- `## Split and window creation tests`
- `## Manifest completeness tests`

### `test/regression/test_fitzhugh_nagumo_smoke_regression.jl`

- `## Fixed smoke reference setup`
- `## Reference object counts check`
- `## Reference summary-statistics check`
- `## Manifest hash and metadata consistency check`

---

## 7. Data flow and dimensions

### 7.1 单条轨线

状态：
$$

\mathbf x_m^{(q)}\in\mathbb R^2,\qquad
\mathbf x_m^{(q)}=\begin{bmatrix}v_m^{(q)}\\ w_m^{(q)}\end{bmatrix}.

$$

状态矩阵：
$$

\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

观测矩阵：
$$

\mathbf Z^{(q)}=\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

时间向量：
$$

\mathbf t^{(q)}\in\mathbb R^{M+1}.

$$

参数实例：
$$

\mu^{(q)}=(a,b,\varepsilon,I)\in\mathbb R^4,

$$
但在本版本中所有 $q$ 使用同一固定参数。

### 7.2 多轨线集合

共有 $Q$ 条轨线时，数据对象应是：
- 一个 `Vector{RawTrajectory}` 风格的轨线容器；
- 一个 `Vector{ObservedTrajectory}` 风格的轨线容器；
而不是一开始就把不同轨线拼成一个超大矩阵。

### 7.3 split 之后

训练集轨线数：
$$

Q_{\mathrm{tr}},
\quad
Q_{\mathrm{va}},
\quad
Q_{\mathrm{te}},
\qquad
Q_{\mathrm{tr}}+Q_{\mathrm{va}}+Q_{\mathrm{te}}=Q.

$$

### 7.4 窗口对象

一步样本数，单条轨线约为：
$$

M.

$$

长度为 $L$ 的 rollout 窗口数，单条轨线约为：
$$

M+1-L.

$$

statistics 窗口同理。

### 7.5 输出对象关联

$$

(\text{SystemSpec},\text{ObservationSpec})
\rightarrow
\text{RawTrajectory}
\rightarrow
\text{ObservedTrajectory}
\rightarrow
\text{SplitSpec}
\rightarrow
\text{WindowSpec}
\rightarrow
\text{TaskSpec}
\rightarrow
\text{BenchmarkSpec}
\rightarrow
\text{ReleaseManifest}.

$$

这正对应 ODEs_dataset 的标准数据工厂协议。fileciteturn5file1

---

## 8. Package and documentation plan

这里只给包方向，不虚构接口。

- `DifferentialEquations.jl / OrdinaryDiffEq.jl`  
  用于 ODE 积分。实现前需查官方文档确认：固定采样输出、容差控制、保存策略、适合快慢系统的求解器选择。

- `LinearAlgebra`  
  用于 Jacobian、局部稳定性、条件数与基本矩阵运算。

- `Random`  
  用于初值采样与 split 种子控制。

- `Statistics`  
  用于峰值统计、均值方差、窗口统计摘要。

- `JSON3.jl` 或等价配置/manifest 包  
  用于配置对象与 manifest 序列化。具体字段编码方式需查文档。

- `JLD2.jl` 或 `HDF5.jl`  
  用于轨线对象持久化。正式编码前应确认：矩阵、向量、字典、metadata 的推荐保存模式。

- `Plots.jl` 或 `CairoMakie.jl`  
  用于时间序列图、相图、nullcline 图和 split 覆盖图。具体绘图库可按项目已有习惯决定。

- `Test`  
  用于 unit / integration / regression 测试。

---

## 9. Debugging and inspection plan

这部分是 FHN 最关键的。

### 生成时必须打印或保存

- `system_id`
- 固定参数值 $(a,b,\varepsilon,I)$
- `dt`、`tspan`、`trajectory_length`
- 轨线条数 $Q$
- 每条轨线 `state_matrix` 尺寸
- split 后各集合轨线数
- 各类窗口样本数

### 必须计算的数值检查

- 平衡点残差
- 轨线最小值 / 最大值：`v_min, v_max, w_min, w_max`
- 是否存在 NaN / Inf
- 采样时间网格是否一致
- 每条轨线是否成功覆盖预期时间区间

### 必须输出的图

- $v(t)$、$w(t)$ 时间序列样例图
- $v$-$w$ 相图
- 相图 + 两条 nullcline
- 多轨线覆盖图
- train / val / test 的相图覆盖对比

### 建议输出的统计表

- 每条轨线峰值高度
- 每条轨线是否触发 excursion
- split 级别的峰值分布摘要
- one-step / rollout / statistics 窗口数量表

---

## 10. Expected outputs

本任务完成后，应该稳定产出以下对象。

### 数据对象

- 原始状态轨线 `RawTrajectory`
- 处理轨线 `ObservedTrajectory`
- split 索引
- one-step 样本
- rollout 窗口
- statistics 窗口

### 元数据对象

- `SystemSpec`
- `ObservationSpec`
- `SplitSpec`
- `WindowSpec`
- `TaskSpec`
- `BenchmarkSpec`
- `ReleaseManifest`

### 图表

保存在：

- `reports/v1_core/fitzhugh_nagumo_formal/plots/phase_portraits/`
- `reports/v1_core/fitzhugh_nagumo_formal/plots/time_series/`
- `reports/v1_core/fitzhugh_nagumo_formal/plots/split_coverage/`

### 表格

保存在：

- `reports/v1_core/fitzhugh_nagumo_formal/tables/generation_summary/`
- `reports/v1_core/fitzhugh_nagumo_formal/tables/diagnostics/`

### 日志

保存在：

- `reports/v1_core/fitzhugh_nagumo_formal/logs/`

### 发布对象

保存在：

- `data/releases/odes_dataset_fitzhugh_nagumo_v1/`

---

## 11. Failure points and debugging strategies

### 失败点 1：轨线全部塌缩成平衡点附近小扰动
**表现**  
看起来“能跑”，但没有明显快慢 excursion。

**诊断**  
检查初值域、参数是否过于稳定、峰值统计是否过小。

**修复方向**  
扩大初值域到阈值附近；必要时轻调固定参数到更明显的 excitable 区域。

---

### 失败点 2：轨线出现异常爆炸或数值不稳定
**表现**  
NaN、Inf、非物理大幅度。

**诊断**  
检查 solver 容差、积分器选择、初值域是否过大。

**修复方向**  
缩小初值域；调整求解器与容差；增加状态范围保护性检查。

---

### 失败点 3：split 后某个集合几乎没有 excursion
**表现**  
train/test 动力学分布极不均衡。

**诊断**  
比较各 split 的峰值分布与相图覆盖。

**修复方向**  
split 前先按轨线诊断标签分层抽样；至少保证不同 split 都含有代表性轨线。

---

### 失败点 4：窗口计数不一致
**表现**  
one-step、rollout、statistics 样本数与理论值不符。

**诊断**  
检查 horizon、边界索引与是否错误跨越轨线尾部。

**修复方向**  
把窗口生成逻辑独立测试，不与训练逻辑混写。

---

### 失败点 5：manifest 与文件路径不一致
**表现**  
数据能生成，但不能稳定复现或不能正确回读。

**诊断**  
核对 `system_id / observation_id / split_id / release_version`。

**修复方向**  
强制所有保存函数由统一 path resolver 与 manifest builder 驱动。

---

### 失败点 6：后续扩展到参数泛化时协议不兼容
**表现**  
当前版本只能处理单一固定参数，未来不好扩展到 `Split-P`。

**诊断**  
检查 `parameter_instance` 是否仍按通用对象保留，而不是被写死在脚本局部常量里。

**修复方向**  
从第一版开始就让参数实例以配置对象形式流过全流水线。

---

## 12. Stop before code

这份计划到这里停止。  
当前阶段不写代码，不给伪代码，不展开 Julia 实现。

下一步若你要继续，我建议直接进入 **FitzHugh–Nagumo 的具体文件级实现说明**，按上面的目标路径逐个落到 `.jl` 与 `.json`。