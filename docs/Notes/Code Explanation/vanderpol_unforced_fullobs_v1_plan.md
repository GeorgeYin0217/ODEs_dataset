## Step 2：范德波尔振子详细代码工程计划书

### 1. Confirmed task summary

本次任务是在 `ODEs_dataset` 项目中接入 `v1_core` 的 **无受迫范德波尔振子**，并严格遵循数据集工程指南中的三层分离：

- 数据层：生成状态轨线与观测轨线；
- 任务层：由轨线派生一步样本、多步窗口、统计窗口；
- 评测层：定义可复用的 benchmark 指标与诊断。

本次确认的系统设定为：

$$

\dot{x}_1=x_2,\qquad
\dot{x}_2=\mu(1-x_1^2)x_2-x_1,
\qquad \mu>0,

$$

且采用：

- **无受迫系统**；
- **全观测**；
- **非强刚性参数区间**；
- 第一版不引入控制、随机扰动、部分观测、非线性传感器。

因此本任务的目标不是写某个算法实验，而是把 Van der Pol 作为一个标准 ODE benchmark 系统，完整接入：

$$

\text{system} \to \text{raw trajectory} \to \text{observed trajectory} \to \text{split} \to \text{window} \to \text{task} \to \text{report}.

$$

建议本次任务同时准备两档配置：

- **smoke 档**：固定单一较温和参数，例如 $\mu=1$；
- **formal 档**：在非强刚性范围内做参数采样，例如 $\mu\in[1,3]$。

---

### 2. Task decomposition

建议把整个任务拆成 10 个子任务。

1. 定义 Van der Pol 的 `SystemSpec`
2. 定义全观测 `ObservationSpec`
3. 设计 smoke 与 formal 两套系统配置
4. 实现状态轨线生成逻辑
5. 实现观测轨线封装逻辑
6. 实现轨线级 split 逻辑
7. 实现一步 / rollout / statistics 三类窗口逻辑
8. 编写 smoke 生成脚本与 formal 生成脚本
9. 编写诊断、manifest 与回归检查
10. 冻结 v1_core 的 Van der Pol 发布配置与报告

---

### 3. Sub-task specification

#### 子任务 A：系统对象注册

**purpose**  
把范德波尔振子注册为 `v1_core` 系统对象。

**input**  
系统名称、状态维数、参数名、参数域、默认参数、初值域、时间步长、轨线长度、积分器配置。

**output**  
一个可被生成器读取的 `SystemSpec`。

**dependency**  
无。

**relevant math**  
$$

\mathbf x=
\begin{bmatrix}
x_1\\x_2
\end{bmatrix}\in\mathbb R^2,\qquad
\dot{\mathbf x}=
\begin{bmatrix}
x_2\\
\mu(1-x_1^2)x_2-x_1
\end{bmatrix}.

$$

**diagnostic checks**  
- `state_dim == 2`
- 参数名只包含 `mu`
- 默认参数落在非强刚性范围内
- `trajectory_length`、`dt`、`tspan` 自洽

---

#### 子任务 B：观测链定义

**purpose**  
为该系统提供标准全观测配置，并保留未来扩展接口。

**input**  
状态轨线 $\mathbf X\in\mathbb R^{2\times(M+1)}$。

**output**  
观测轨线 $\mathbf Z\in\mathbb R^{2\times(M+1)}$。

**dependency**  
子任务 A。

**relevant math**  
本次固定：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,
\qquad \mathbf z_m=\mathbf x_m.

$$

**diagnostic checks**  
- `output_dim == 2`
- `observation_matrix` 与 `state_matrix` 尺寸一致
- 全观测模式下不允许额外传感器矩阵误配置

---

#### 子任务 C：smoke 配置设计

**purpose**  
提供最小可运行、低风险、便于回归测试的版本。

**input**  
固定参数 $\mu_{\text{smoke}}$，有限条轨线，较短时间窗。

**output**  
smoke 级配置对象、smoke 原始轨线、smoke 处理轨线。

**dependency**  
子任务 A、B。

**relevant math**  
建议固定：

$$

\mu_{\text{smoke}}=1.

$$

初值从有限矩形区域中采样：

$$

\mathbf x_0\in\Omega_{0,\text{smoke}}\subset\mathbb R^2.

$$

**diagnostic checks**  
- 所有轨线积分成功
- 相图存在向极限环收敛趋势
- 采样点数与配置一致
- 可在短时间内完整跑完

---

#### 子任务 D：formal 配置设计

**purpose**  
提供正式版本的数据生成入口。

**input**  
参数区间、初值域、轨线数量、采样步长、时长、随机种子策略。

**output**  
formal 级 `SystemSpec` 实例和轨线生成配置。

**dependency**  
子任务 A、B。

**relevant math**  
建议使用：

$$

\mu\sim \Pi_{\text{formal}},\qquad \Pi_{\text{formal}}=[1,3].

$$

初值仍在统一矩形区域采样：

$$

\mathbf x_0\in\Omega_{0,\text{formal}}\subset\mathbb R^2.

$$

**diagnostic checks**  
- $\mu$ 样本确实分布在目标区间
- 不出现明显强刚性导致的积分失败
- 轨线覆盖极限环内外的 transient 与吸引段

---

#### 子任务 E：状态轨线生成

**purpose**  
把 `SystemSpec + parameter_instance + initial_condition_instance` 变成 `RawTrajectory`。

**input**  
$$

(\mu^{(q)},\mathbf x_0^{(q)},\tau,M)

$$

**output**  
$$

\mathbf X^{(q)}=
[\mathbf x_1^{(q)}\ \cdots\ \mathbf x_{M+1}^{(q)}]
\in\mathbb R^{2\times(M+1)}.

$$

**dependency**  
子任务 C 或 D。

**relevant math**  
$$

\mathbf x_{m+1}^{(q)}=\mathbf F^\tau_{\mu^{(q)}}(\mathbf x_m^{(q)}).

$$

**diagnostic checks**  
- `times` 长度与 `state_matrix` 列数匹配
- 无 NaN / Inf
- 相图闭合合理
- 轨线末段靠近稳定极限环而非发散

---

#### 子任务 F：观测轨线封装

**purpose**  
把 `RawTrajectory` 变成 `ObservedTrajectory`。

**input**  
`RawTrajectory` 与 `ObservationSpec`。

**output**  
`ObservedTrajectory`。

**dependency**  
子任务 E。

**relevant math**  
$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

**diagnostic checks**  
- `state_matrix` 和 `observation_matrix` 行列一致
- 观测矩阵元数据完整
- `system_id`、`observation_id`、`trajectory_id` 一致

---

#### 子任务 G：轨线级 split 生成

**purpose**  
构造训练/验证/测试划分。

**input**  
轨线编号集合 $\{1,\dots,R\}$、split 配置、随机种子。

**output**  
$$

\mathcal R_{\mathrm{train}},\quad
\mathcal R_{\mathrm{val}},\quad
\mathcal R_{\mathrm{test}}.

$$

**dependency**  
子任务 F。

**relevant math**  
本任务至少做两种 split：

- **Split-I**：固定参数，未见初值泛化；
- **Split-P**：训练与测试参数集分离。

formal 版本中建议：

$$

\Pi_{\mathrm{train}}\cap \Pi_{\mathrm{test}}=\varnothing

$$

或至少采用不重叠的参数采样区间。

**diagnostic checks**  
- 切分单位必须是整条轨线
- 比例符合配置
- train / val / test 无轨线重叠
- Split-P 中参数集合确实分离

---

#### 子任务 H：窗口对象派生

**purpose**  
从轨线派生标准任务对象。

**input**  
`ObservedTrajectory` 与 `WindowSpec`。

**output**  
- `OneStepSample`
- `RolloutWindowSample`
- `StatisticsWindowSample`

**dependency**  
子任务 G。

**relevant math**  

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

**diagnostic checks**  
- 索引不越界
- 起点数与 horizon 一致
- 每类样本计数可复算
- 绝不跨 split 取窗口

---

#### 子任务 I：诊断与报告

**purpose**  
对生成结果做最基本的数据健康检查。

**input**  
raw / processed / split / windows。

**output**  
表格、图、日志、manifest。

**dependency**  
子任务 E–H。

**relevant math**  
建议至少检查：

- 状态范围：
  $$

  \min x_i,\ \max x_i
  
$$
- 轨线范数与最大速度：
  $$

  \max_m \|\mathbf x_m\|_2
  
$$
- 周期粗估计
- 末段与前段的幅值变化
- 按 split 的轨线数量与窗口数量

**diagnostic checks**  
- smoke 与 formal 结果格式一致
- 报告可用于回归比较
- manifest 能回溯配置和随机种子

---

#### 子任务 J：发布冻结

**purpose**  
把该系统冻结到 v1_core 的标准清单中。

**input**  
系统、观测、split、window、task、benchmark、release 配置。

**output**  
release 级 manifest 与发布索引。

**dependency**  
前面全部子任务。

**relevant math**  
不是新的动力学公式，而是把前面所有配置对象绑定到同一版本号。

**diagnostic checks**  
- release 中引用的所有配置文件都存在
- release 与 benchmark 中的 id 一一对应
- data/manifests 与 data/releases 可相互验证

---

### 4. Directory and file plan

下面给出建议的文件清单。路径全部落在 `ODEs_dataset` 工程目录内。

#### 文档

- `docs/notes/mathematical explanation/vanderpol_unforced_fullobs_v1_math.md`  
  角色：保存本次数学说明书。

- `docs/notes/code explanation/vanderpol_unforced_fullobs_v1_plan.md`  
  角色：保存本次代码工程计划书。

- `docs/notes/file explanation/vanderpol_unforced_fullobs_v1_file_guide.md`  
  角色：任务完成后记录文件用途、运行顺序、产物位置。

- `docs/spec/system_registry.md`  
  角色：补充 Van der Pol 在 `v1_core` 中的系统登记说明。

---

#### 配置文件

- `configs/systems/v1_core/vanderpol_unforced_smoke.toml`  
  角色：smoke 系统配置，固定 $\mu=1$。

- `configs/systems/v1_core/vanderpol_unforced_formal.toml`  
  角色：formal 系统配置，$\mu\in[1,3]$。

- `configs/observations/v1_core/fullstate_identity_2d.toml`  
  角色：全状态全观测配置；可复用于其他二维系统。

- `configs/splits/v1_core/vanderpol_split_initial_condition.toml`  
  角色：Split-I。

- `configs/splits/v1_core/vanderpol_split_parameter.toml`  
  角色：Split-P。

- `configs/windows/v1_core/vanderpol_one_step.toml`  
  角色：一步样本窗口。

- `configs/windows/v1_core/vanderpol_rollout_short.toml`  
  角色：短 rollout 窗口。

- `configs/windows/v1_core/vanderpol_rollout_long.toml`  
  角色：长 rollout 窗口。

- `configs/windows/v1_core/vanderpol_statistics_window.toml`  
  角色：统计窗口。

- `configs/tasks/v1_core/vanderpol_one_step_forecast.toml`  
  角色：一步预测任务。

- `configs/tasks/v1_core/vanderpol_multi_step_rollout.toml`  
  角色：多步 rollout 任务。

- `configs/tasks/v1_core/vanderpol_long_time_statistics.toml`  
  角色：长期统计任务。

- `configs/benchmarks/v1_core/vanderpol_smoke_benchmark.toml`  
  角色：smoke 级完整 benchmark 组合。

- `configs/benchmarks/v1_core/vanderpol_formal_benchmark.toml`  
  角色：formal 级完整 benchmark 组合。

- `configs/releases/ODEs_dataset_v1/vanderpol_v1_release.toml`  
  角色：正式发布清单中的 Van der Pol 条目。

---

#### 源码文件

- `src/dynamics/vanderpol_unforced.jl`  
  角色：定义范德波尔右端函数和系统元信息。

- `src/observations/fullstate_identity.jl`  
  角色：实现全状态恒等观测。

- `src/generators/generate_vanderpol_dataset.jl`  
  角色：根据系统和观测配置生成 raw / processed 轨线。

- `src/datasets/trajectory_types.jl`  
  角色：定义 `RawTrajectory`、`ObservedTrajectory` 等对象；若已存在则仅扩展，不新建重复文件。

- `src/splits/trajectory_level_splits.jl`  
  角色：实现轨线级 Split-I 与 Split-P；若已有公共 split 文件则扩展注册。

- `src/windows/one_step_windows.jl`  
  角色：一步样本窗口构造；若已存在则复用。

- `src/windows/rollout_windows.jl`  
  角色：rollout 窗口构造；若已存在则复用。

- `src/windows/statistics_windows.jl`  
  角色：统计窗口构造；若已存在则复用。

- `src/tasks/forecast_tasks.jl`  
  角色：一步预测与 rollout 任务映射。

- `src/tasks/statistics_tasks.jl`  
  角色：长期统计任务映射。

- `src/diagnostics/vanderpol_diagnostics.jl`  
  角色：范德波尔专属数据诊断，例如极限环覆盖、周期粗估、状态范围。

- `src/manifests/release_manifest_builder.jl`  
  角色：写入数据 manifest；若已有公共 manifest 文件则扩展。

- `src/io/path_helpers.jl`  
  角色：统一路径管理；若已有则复用。

- `src/registries/system_registry.jl`  
  角色：注册 `vanderpol_unforced` 到 `v1_core`。

- `src/registries/observation_registry.jl`  
  角色：注册 `fullstate_identity_2d`。

- `src/registries/task_registry.jl`  
  角色：注册 Van der Pol 相关任务组合。

- `src/registries/benchmark_registry.jl`  
  角色：注册 smoke / formal benchmark。

---

#### 实验入口脚本

- `experiments/smoke_tests/run_vanderpol_smoke_generation.jl`  
  角色：最小可运行数据生成入口。

- `experiments/smoke_tests/run_vanderpol_smoke_checks.jl`  
  角色：smoke 产物检查与可视化入口。

- `experiments/baseline_forecasting/run_vanderpol_formal_generation.jl`  
  角色：formal 数据生成入口。虽然名字在 `baseline_forecasting` 下看起来偏任务，但它可作为正式 benchmark 数据生成与任务派生的入口；若你后续想更纯粹，也可统一只在 `experiments/smoke_tests/` 放测试入口，把正式数据发布入口放到 release 流程里。

---

#### 数据输出路径

- `data/raw/v1_core/vanderpol_unforced/smoke/`
- `data/raw/v1_core/vanderpol_unforced/formal/`
- `data/processed/v1_core/vanderpol_unforced/fullstate_identity_2d/smoke/`
- `data/processed/v1_core/vanderpol_unforced/fullstate_identity_2d/formal/`
- `data/manifests/v1_core/vanderpol_unforced/`
- `data/releases/ODEs_dataset_v1/v1_core/vanderpol_unforced/`

---

#### 报告输出路径

- `reports/v1_core/vanderpol_unforced_fullobs_v1/tables/`
- `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/`
- `reports/v1_core/vanderpol_unforced_fullobs_v1/logs/`

---

#### 测试文件

- `test/unit/test_vanderpol_dynamics.jl`
- `test/unit/test_fullstate_identity_observation.jl`
- `test/integration/test_vanderpol_generation_pipeline.jl`
- `test/regression/test_vanderpol_smoke_regression.jl`

---

### 5. Module / component responsibilities

#### `src/dynamics/`
负责系统本体，只关心：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\mu).

$$

不负责观测、切分和报告。

#### `src/observations/`
负责：

$$

\mathbf x\to\mathbf z.

$$

本次仅实现恒等全观测，但接口必须允许未来扩展到部分观测和加噪。

#### `src/generators/`
负责把系统配置和观测配置串起来，输出 raw / processed 轨线。

#### `src/datasets/`
负责统一数据对象格式，保证训练器或评测器不直接依赖底层 solver 细节。

#### `src/splits/`
只负责轨线级切分，不掺杂窗口逻辑。

#### `src/windows/`
只负责从轨线派生样本，不负责训练和预测。

#### `src/tasks/`
负责把窗口对象映射为 benchmark 任务对象。

#### `src/diagnostics/`
负责数据健康检查、统计检查、图表和回归比较所需的量。

#### `src/manifests/`
负责记录生成器版本、配置、种子、时间戳、数据路径、对象计数。

#### `src/registries/`
负责让 Van der Pol 作为 `v1_core` 系统被项目统一发现和调度。

---

### 6. Planned `##` sections

下面只列 Julia 文件的计划性章节标题，不写代码。

#### `src/dynamics/vanderpol_unforced.jl`

- `## Van der Pol system overview and identifiers`
- `## State variables and parameter definitions`
- `## Unforced Van der Pol vector field`
- `## Default parameter domain and initial-condition domain`
- `## SystemSpec construction helpers`
- `## Validation checks for Van der Pol system configuration`

---

#### `src/observations/fullstate_identity.jl`

- `## Observation mode overview`
- `## Full-state identity observation map`
- `## ObservationSpec construction`
- `## Output-dimension checks`
- `## Observation metadata helpers`

---

#### `src/generators/generate_vanderpol_dataset.jl`

- `## Generator scope and entry points`
- `## System and observation config loading`
- `## Parameter-instance sampling`
- `## Initial-condition sampling`
- `## Raw trajectory generation`
- `## Observed trajectory construction`
- `## Data saving and manifest writing`
- `## Generation summary diagnostics`

---

#### `src/splits/trajectory_level_splits.jl`

- `## Split protocol overview`
- `## Initial-condition generalization split`
- `## Parameter generalization split`
- `## Trajectory-level integrity checks`
- `## Split summary reporting`

---

#### `src/windows/one_step_windows.jl`

- `## One-step window protocol`
- `## OneStepSample construction`
- `## Boundary and index checks`
- `## One-step sample counting`

---

#### `src/windows/rollout_windows.jl`

- `## Rollout window protocol`
- `## RolloutWindowSample construction`
- `## Horizon validation`
- `## Rollout sample counting`

---

#### `src/windows/statistics_windows.jl`

- `## Statistics window protocol`
- `## StatisticsWindowSample construction`
- `## Segment extraction checks`
- `## Statistics sample counting`

---

#### `src/tasks/forecast_tasks.jl`

- `## Forecast task overview`
- `## One-step forecast task mapping`
- `## Multi-step rollout task mapping`
- `## Task-object validation`

---

#### `src/tasks/statistics_tasks.jl`

- `## Long-time statistics task overview`
- `## Statistics-window task mapping`
- `## Task metadata and metric binding`

---

#### `src/diagnostics/vanderpol_diagnostics.jl`

- `## Diagnostic scope for Van der Pol trajectories`
- `## State-range and trajectory-scale checks`
- `## Limit-cycle coverage checks`
- `## Period and oscillation diagnostics`
- `## Split and window count summaries`
- `## Plot-ready diagnostic outputs`

---

#### `src/registries/system_registry.jl`

- `## System registry overview`
- `## v1_core system registration for Van der Pol`
- `## Registry lookup validation`

---

#### `experiments/smoke_tests/run_vanderpol_smoke_generation.jl`

- `## Smoke experiment purpose and config selection`
- `## Dataset generation entry point`
- `## Smoke-level artifact locations`
- `## Smoke completion summary`

---

#### `experiments/smoke_tests/run_vanderpol_smoke_checks.jl`

- `## Smoke diagnostic entry point`
- `## Raw and processed data checks`
- `## Plot generation`
- `## Regression-summary logging`

---

#### `experiments/baseline_forecasting/run_vanderpol_formal_generation.jl`

- `## Formal benchmark purpose and config selection`
- `## Formal dataset generation entry point`
- `## Split and window materialization`
- `## Formal artifact and report summary`

---

### 7. Data flow and dimensions

下面给出该系统的数据流与关键尺寸。

#### 7.1 单条轨线级别

状态维数：

$$

d_x=2.

$$

观测维数：

$$

d_z=2.

$$

单条轨线长度为 $M+1$ 时：

$$

\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)},
\qquad
\mathbf Z^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

由于本次全观测：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

---

#### 7.2 多轨线集合

若共有 $R$ 条轨线，则原始数据对象集合为：

$$

\left\{
(\mu^{(q)},\mathbf x_0^{(q)},\mathbf X^{(q)},\mathbf Z^{(q)})
\right\}_{q=1}^R.

$$

其中：

- $\mu^{(q)}\in\mathbb R$
- $\mathbf x_0^{(q)}\in\mathbb R^2$

---

#### 7.3 Split 后的数据流

划分为：

$$

\mathcal R_{\mathrm{train}},\quad
\mathcal R_{\mathrm{val}},\quad
\mathcal R_{\mathrm{test}}.

$$

每个 split 内部保留对应轨线子集。

---

#### 7.4 一步样本维度

对任意轨线 $q$：

$$

(\mathbf z_m^{(q)},\mathbf z_{m+1}^{(q)})
\in
\mathbb R^2\times\mathbb R^2.

$$

单条轨线可产生 $M$ 个一步样本。

---

#### 7.5 rollout 窗口维度

若 horizon 为 $L$，则：

$$

\mathbf z_s^{(q)}\in\mathbb R^2,
\qquad
(\mathbf z_{s+1}^{(q)},\dots,\mathbf z_{s+L}^{(q)})
\in \mathbb R^{2\times L}.

$$

单条轨线可产生：

$$

M+1-L

$$

个 rollout 起点。

---

#### 7.6 statistics 窗口维度

长度为 $L$ 时：

$$

(\mathbf z_s^{(q)},\dots,\mathbf z_{s+L-1}^{(q)})
\in
\mathbb R^{2\times L}.

$$

---

#### 7.7 smoke 与 formal 的逻辑区别

- smoke：小 $R$、短 $M$、固定 $\mu$、少量窗口，重点是协议和回归；
- formal：更大 $R$、更长 $M$、参数区间采样、包含 Split-I 与 Split-P，重点是 benchmark 质量。

---

### 8. Package and documentation plan

下面只给方向，不假设具体 API。

#### `DifferentialEquations.jl` / `OrdinaryDiffEq.jl`
**why**  
用于 ODE 数值积分，是该任务的核心依赖。

**expected functionality**  
- 定义 ODE 问题
- 指定容差
- 指定时间采样
- 读取求解状态与离散轨线

**docs to check**  
- ODEProblem 的标准构造
- solver 选择策略
- `saveat` 与时间网格对齐方式
- 容差与事件处理
- 对中等快慢系统的推荐求解器

---

#### `SciMLBase.jl`
**why**  
用于与 SciML 问题对象、解对象保持接口一致。

**expected functionality**  
问题对象和求解对象的统一抽象。

**docs to check**  
- 问题定义约定
- 解对象字段和访问方式

---

#### `Random`
**why**  
参数和初值采样、split 随机化、复现控制。

**expected functionality**  
- 固定种子
- 轨线级随机采样

**docs to check**  
- RNG 对象传递方式
- 不同模块共享随机状态的规范

---

#### `LinearAlgebra`
**why**  
基本向量范数、矩阵尺寸、数值检查。

**expected functionality**  
- 范数
- 线性代数基础操作

**docs to check**  
无需重点查复杂接口，但需确认性能相关约定。

---

#### `Statistics`
**why**  
均值、方差、协方差、时间平均等统计检查。

**expected functionality**  
- 均值
- 方差
- 协方差

**docs to check**  
- 行维 / 列维统计约定

---

#### `JSON3.jl` 或 `TOML`
**why**  
配置和 manifest 序列化。

**expected functionality**  
- 读取 TOML 配置
- 写出 JSON 或 TOML manifest

**docs to check**  
- 嵌套配置对象的读写方式
- 数组、字典和数值类型的序列化细节

---

#### `JLD2.jl` 或 `HDF5.jl`
**why**  
保存轨线矩阵和中间数据对象。

**expected functionality**  
- 存储矩阵
- 存储元数据
- 可复现读取

**docs to check**  
- 复合对象存储方式
- 标量、向量、矩阵与字典混合保存
- 性能与兼容性差异

---

#### `Plots.jl` 或 `Makie.jl`
**why**  
生成相图、时间序列图、split 统计图。

**expected functionality**  
- 2D 相图
- 多轨线可视化
- 保存图片

**docs to check**  
- 批量绘图输出
- 非交互环境下的保存方式

---

### 9. Debugging and inspection plan

本任务最重要的不是“能运行”，而是“能证明生成正确”。

建议固定检查以下内容。

#### 配置级检查
- `system_id`
- `family`
- `state_dim`
- `parameter_domain`
- `default_parameters`
- `trajectory_length`
- `dt`
- `tspan`
- `observation_id`
- `output_dim`

#### 轨线级检查
- 每条轨线的 `times` 长度
- `state_matrix` 尺寸是否为 $2\times(M+1)$
- `observation_matrix` 尺寸是否为 $2\times(M+1)$
- 是否出现 NaN / Inf
- 首末状态是否异常发散
- 相图是否呈稳定极限环吸引结构

#### 参数与初值检查
- 实际采样到的 $\mu$ 最小值、最大值、均值
- 初值矩形域覆盖情况
- 训练/测试中参数集合是否重叠

#### split 检查
- 轨线编号是否互斥
- 比例是否符合配置
- Split-P 是否真的实现参数泛化
- 是否误把窗口作为切分单位

#### 窗口检查
- one-step 样本总数
- rollout 窗口总数
- statistics 窗口总数
- 每类窗口的起点范围是否合法

#### 周期与极限环检查
- 轨线后半段幅值是否基本稳定
- 主周期粗估是否落在合理范围
- 不同 $\mu$ 下波形变化是否符合预期

#### 需要保存的诊断图
- 单条轨线时间序列图
- 单条轨线相图
- 多轨线相图叠加图
- 不同 $\mu$ 轨线对比图
- split 样本数量柱状图
- rollout horizon 对应样本数量表

#### 需要保存的日志/表
- 轨线生成摘要表
- split 摘要表
- 窗口摘要表
- manifest 完整记录
- smoke regression 摘要日志

---

### 10. Expected outputs

#### 数据文件
保存在：

- `data/raw/v1_core/vanderpol_unforced/smoke/`
- `data/raw/v1_core/vanderpol_unforced/formal/`
- `data/processed/v1_core/vanderpol_unforced/fullstate_identity_2d/smoke/`
- `data/processed/v1_core/vanderpol_unforced/fullstate_identity_2d/formal/`

内容包括：

- `RawTrajectory`
- `ObservedTrajectory`
- split 索引
- window 索引或派生对象
- manifest

---

#### 表格
保存在：

- `reports/v1_core/vanderpol_unforced_fullobs_v1/tables/`

建议输出：

- 参数范围表
- 轨线数量与长度表
- split 统计表
- one-step / rollout / statistics 样本数表

---

#### 图像
保存在：

- `reports/v1_core/vanderpol_unforced_fullobs_v1/plots/`

建议输出：

- 时间序列图
- 相图
- 多轨线覆盖图
- 不同参数轨线图
- split 可视化图

---

#### 日志
保存在：

- `reports/v1_core/vanderpol_unforced_fullobs_v1/logs/`

建议输出：

- smoke 运行日志
- formal 运行日志
- 诊断日志
- regression 对比日志

---

#### 发布对象
保存在：

- `data/releases/ODEs_dataset_v1/v1_core/vanderpol_unforced/`

内容包括：

- release 级索引
- 冻结配置
- 对应 manifest
- 版本号与生成器信息

---

### 11. Failure points and debugging strategies

#### 失败点 1：参数区间虽然写成“非强刚性”，但轨线仍出现积分困难
**symptom**  
生成慢、失败、轨线中出现异常跳变。

**strategy**  
- 先固定 $\mu=1$ 做 smoke
- 检查 solver 与容差
- 再逐渐扩展到 $[1,3]$
- 不要一开始把 formal 区间设太宽

---

#### 失败点 2：采样步长过大导致相位严重欠采样
**symptom**  
相图像多边形，极限环粗糙，rollout 任务失真。

**strategy**  
- 检查每周期采样点数
- 用相图和时间序列同时核验
- 先保证数据质量，再考虑压缩存储

---

#### 失败点 3：初值域太窄，数据只覆盖极限环附近
**symptom**  
所有轨线几乎重合，transient 很弱。

**strategy**  
- 扩大初值矩形域
- 增加极限环内外的覆盖
- 报告中单独画初值散点图与相图覆盖图

---

#### 失败点 4：初值域太宽，导致少数异常轨线主导数据分布
**symptom**  
状态范围跨度过大，formal 数据尺度不稳定。

**strategy**  
- 先用较保守的矩形域
- 对状态范围做分位数检查
- 必要时对初值采样加边界约束

---

#### 失败点 5：Split-P 名义上做了参数泛化，实际上参数集合仍重叠
**symptom**  
train/test 性能异常乐观。

**strategy**  
- 显式保存 train/test 参数列表
- 在 manifest 中写入参数区间
- 生成 split 统计表进行人工复核

---

#### 失败点 6：窗口越界或跨 split 泄漏
**symptom**  
样本总数不对，回归结果不稳定。

**strategy**  
- 所有窗口从 split 后轨线内部生成
- 单元测试检查起点和终点
- regression 中固定样本计数

---

#### 失败点 7：manifest 不完整导致结果无法复现
**symptom**  
后续不知道某份数据是用什么配置生成的。

**strategy**  
manifest 必须写入：
- system_id
- observation_id
- split_id
- window_id
- benchmark_id
- dataset_version
- dt
- trajectory_length
- parameter_domain
- random_seed
- generator_commit_hash

---

### 12. Stop before code

以上是 **Van der Pol / 无受迫 / 全观测 / 非强刚性参数区间** 在 `ODEs_dataset` 中的详细代码工程计划书。

这里到此为止，**不写代码**。  
下一步如果你要继续，我应当进入具体实现阶段，例如先从下面任一项开始：

- 先写 `vanderpol_unforced_smoke` 的配置与文件清单
- 先写 `src/dynamics/vanderpol_unforced.jl` 的实现任务书
- 或直接开始逐文件实现