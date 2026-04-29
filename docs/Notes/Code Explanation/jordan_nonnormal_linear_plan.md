## Step 2：Jordan / 非正规线性系统代码工程计划书

### 1. Confirmed task summary

本次任务是在 **ODEs_dataset** 中加入第三个内部单元测试系统：

$$

\texttt{unit\_internal / jordan\_nonnormal\_linear}

$$

数学对象为二维 Jordan 非正规线性系统：

$$

\dot{\mathbf x}
=
\mathbf A\mathbf x,
\qquad
\mathbf A=
\begin{bmatrix}
\alpha & \gamma\\
0 & \alpha
\end{bmatrix},
\qquad
\alpha<0,\ \gamma>0.

$$

默认观测为全状态、无噪声观测：

$$

\mathbf z_m=\mathbf x_m\in\mathbb R^2.

$$

本系统属于 `unit_internal`，用于检查不可对角化、重复特征值、Jordan 链、非正规瞬态放大、离散传播矩阵和窗口构造是否正确。ODEs_dataset 指南要求数据集工程按“动力系统 → 观测链 → split → window → task → metric”的协议组织，并且把线性对角、旋转–收缩、Jordan / 非正规系统列为内部单元测试层。fileciteturn3file0 fileciteturn3file1

---

### 2. Task decomposition

本任务分成 10 个子任务。

1. **系统配置定义**  
   定义 smoke 与 formal 两套 `SystemSpec`，控制 $\alpha,\gamma,\tau,M,R$、初值范围和随机种子。

2. **观测配置定义**  
   定义全状态、无噪声、无归一化或固定归一化策略的 `ObservationSpec`。

3. **split 配置定义**  
   定义轨线级 `Split-I`，即参数固定、初值泛化。

4. **window 配置定义**  
   定义 one-step 与 rollout 窗口。

5. **动力系统模块实现计划**  
   在 `src/dynamics/` 中加入 Jordan 系统矩阵、解析离散传播矩阵、解析连续时间解的可复用组件。

6. **生成器流程实现计划**  
   在 `src/generators/` 中加入根据配置批量生成 raw / processed / manifest 的流程。

7. **诊断模块实现计划**  
   在 `src/diagnostics/` 中加入 Jordan 专属检查：解析误差、闭合误差、rank 检查、非正规瞬态放大检查、维度检查。

8. **smoke 入口计划**  
   在 `experiments/smoke_tests/` 中放最小运行入口，用小规模数据快速确认系统对象、轨线、split、window、manifest 是否正确。

9. **正式生成入口计划**  
   在 `experiments/smoke_tests/` 或后续独立生成入口中放 formal 数据生成入口。本阶段它仍属于内部数据集生成，不是 baseline 实验。

10. **自动化测试计划**  
   在 `test/unit/`、`test/integration/`、`test/regression/` 中加入针对 Jordan 系统的数值一致性测试。

---

### 3. Sub-task specification

#### 3.1 系统配置定义

**Purpose**  
把 Jordan 系统的所有参数从代码中抽离出来，由配置控制。

**Input**  
`SystemSpec` 参数：

$$

\alpha,\gamma,\tau,M,R,d_x,\mathcal D_{x_0},\text{seed}.

$$

**Output**  
两套配置：

- smoke：小规模快速检查；
- formal：正式生成内部测试数据。

**Dependency**  
无，是后续所有模块的入口。

**Mathematical expression**

$$

\mathbf A=
\begin{bmatrix}
\alpha&\gamma\\
0&\alpha
\end{bmatrix},
\qquad
\mathbf K_\tau
=
e^{\alpha\tau}
\begin{bmatrix}
1&\gamma\tau\\
0&1
\end{bmatrix}.

$$

**Diagnostic checks**

- `state_dim = 2`；
- $\alpha<0$；
- $\gamma>0$；
- $\gamma\tau$ 不过小；
- 轨线时间范围覆盖 $t_\star\approx -1/\alpha$；
- 初值范围必须允许 $x_{2,0}\neq0$。

---

#### 3.2 观测配置定义

**Purpose**  
保持动力系统与观测链解耦。

**Input**

$$

\mathbf x_m\in\mathbb R^2.

$$

**Output**

$$

\mathbf z_m=\mathbf x_m\in\mathbb R^2.

$$

**Dependency**  
依赖系统轨线生成。

**Mathematical expression**

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.

$$

**Diagnostic checks**

- $d_z=d_x=2$；
- `observation_matrix` 与 `state_matrix` 尺寸一致；
- 无噪声时 $\max_m\|\mathbf z_m-\mathbf x_m\|_2=0$。

---

#### 3.3 Split 配置定义

**Purpose**  
按照轨线级别切分 train / val / test，避免窗口泄漏。

**Input**  
完整轨线集合：

$$

\left\{
\mathbf Z^{(q)}
\right\}_{q=1}^R.

$$

**Output**

$$

\mathcal R_{\mathrm{train}},
\qquad
\mathcal R_{\mathrm{val}},
\qquad
\mathcal R_{\mathrm{test}}.

$$

**Dependency**  
依赖已生成的 observed trajectories。

**Mathematical expression**

$$

\mathcal R
=
\mathcal R_{\mathrm{train}}
\sqcup
\mathcal R_{\mathrm{val}}
\sqcup
\mathcal R_{\mathrm{test}}.

$$

**Diagnostic checks**

- 三个集合互不相交；
- 并集覆盖所有轨线；
- split 单位是 trajectory，不是窗口；
- train / val / test 数量与配置比例一致。

---

#### 3.4 Window 配置定义

**Purpose**  
从各 split 内部构造 one-step 与 rollout 样本。

**Input**

$$

\mathbf Z^{(q)}
=
\begin{bmatrix}
\mathbf z_1^{(q)}&\cdots&\mathbf z_{M+1}^{(q)}
\end{bmatrix}.

$$

**Output**

One-step：

$$

(\mathbf z_m,\mathbf z_{m+1}).

$$

Rollout：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

**Dependency**  
依赖 split 结果。

**Mathematical expression**

one-step 样本数：

$$

N_{\mathrm{1step}}^{(q)}=M.

$$

rollout 窗口数：

$$

N_{\mathrm{rollout}}^{(q)}=M-L+1.

$$

**Diagnostic checks**

- horizon $L<M$；
- 窗口不跨轨线；
- 窗口不跨 split；
- 每个窗口的 shape 为 $d_z\times(L+1)$。

---

#### 3.5 动力系统模块

**Purpose**  
提供 Jordan 系统本体、解析解、离散传播矩阵和系统元信息。

**Input**

$$

\alpha,\gamma,\tau,\mathbf x_0,t_m.

$$

**Output**

$$

\mathbf A,\quad \mathbf K_\tau,\quad \mathbf x(t_m),\quad \mathbf X.

$$

**Dependency**  
依赖系统配置。

**Mathematical expression**

$$

\mathbf x(t)
=
e^{\alpha t}
\begin{bmatrix}
1&\gamma t\\
0&1
\end{bmatrix}
\mathbf x_0.

$$

**Diagnostic checks**

- $\mathbf A\in\mathbb R^{2\times2}$；
- $\mathbf K_\tau\in\mathbb R^{2\times2}$；
- $\sigma(\mathbf K_\tau)=\{e^{\alpha\tau},e^{\alpha\tau}\}$；
- $\dim\ker(\mathbf A-\alpha I)=1$；
- $\operatorname{rank}(\mathbf A-\alpha I)=1$。

---

#### 3.6 数据生成器流程

**Purpose**  
把配置对象转换为 raw trajectory、observed trajectory、split、window 和 manifest。

**Input**

- `SystemSpec`
- `ObservationSpec`
- `SplitSpec`
- `WindowSpec`
- `TaskSpec`

**Output**

- raw trajectory 文件；
- processed trajectory 文件；
- split 索引；
- window 索引；
- manifest；
- diagnostics 表；
- smoke plots。

**Dependency**  
依赖 dynamics、observations、splits、windows、io、manifests。

**Mathematical expression**

完整流水线为：

$$

(\mathbf A,\mathbf x_0,\tau)
\Longrightarrow
\mathbf X
\Longrightarrow
\mathbf Z
\Longrightarrow
\text{splits}
\Longrightarrow
\text{windows}
\Longrightarrow
\text{manifest}.

$$

**Diagnostic checks**

- 文件是否全部生成；
- manifest 是否记录所有参数；
- raw 与 processed 维度是否一致；
- split 与 window 数量是否可由 $R,M,L$ 推导出来；
- 解析传播残差是否接近数值零。

---

#### 3.7 诊断模块

**Purpose**  
专门检查 Jordan 非正规系统是否真的生成了目标结构。

**Input**

$$

\mathbf A,\mathbf K_\tau,\mathbf X,\mathbf Z.

$$

**Output**

诊断指标表：

- `state_dim`
- `num_trajectories`
- `trajectory_length`
- `alpha`
- `gamma`
- `dt`
- `lambda_discrete`
- `rank_A_minus_alphaI`
- `geom_mult`
- `max_closed_form_error`
- `max_one_step_residual`
- `max_rollout_residual`
- `max_norm_amplification`
- `x2_activation_min_abs`
- `x2_activation_mean_abs`

**Dependency**  
依赖 dynamics 与 generated data。

**Mathematical expression**

一步闭合残差：

$$

r_m^{(q)}
=
\left\|
\mathbf x_{m+1}^{(q)}
-
\mathbf K_\tau\mathbf x_m^{(q)}
\right\|_2.

$$

多步残差：

$$

r_{m,k}^{(q)}
=
\left\|
\mathbf x_{m+k}^{(q)}
-
\mathbf K_\tau^k\mathbf x_m^{(q)}
\right\|_2.

$$

非正规放大因子：

$$

a^{(q)}
=
\frac{\max_m\|\mathbf x_m^{(q)}\|_2}
{\|\mathbf x_1^{(q)}\|_2}.

$$

**Diagnostic checks**

- `max_one_step_residual` 应接近机器精度；
- `max_rollout_residual` 应接近机器精度；
- `rank_A_minus_alphaI = 1`；
- `geom_mult = 1`；
- 至少部分轨线有 $a^{(q)}>1$，否则非正规瞬态放大不明显；
- $x_2$ 方向必须被激活。

---

### 4. Directory and file plan

本任务属于 **ODEs_dataset 数据集工程**，不是 KoopmanLearning 训练工程。KoopmanLearning 的目录原则中也强调：数据集配置负责“数据怎么生成”，学习工程负责“模型怎么训练、评测、保存”，二者不应混在一起。fileciteturn7file6

#### 4.1 文档文件

| Target path | Role |
|---|---|
| `docs/project guide/unit_internal/jordan_nonnormal_linear_plan.md` | 保存本次 Jordan 系统代码工程计划书 |
| `docs/notes/file explanation/jordan_nonnormal_linear_outputs.md` | 编码完成后记录生成文件说明、运行方式和输出解释 |
| `docs/spec/system_registry.md` | 更新系统注册表，加入 `jordan_nonnormal_linear` |
| `docs/spec/task_registry.md` | 记录本系统支持 one-step 与 rollout 任务 |
| `docs/spec/metric_registry.md` | 记录 Jordan 专属诊断指标 |

---

#### 4.2 配置文件

| Target path | Role |
|---|---|
| `configs/systems/unit_internal/jordan_nonnormal_linear_smoke.json` | smoke 版 `SystemSpec`，小规模、快速运行 |
| `configs/systems/unit_internal/jordan_nonnormal_linear_formal.json` | formal 版 `SystemSpec`，正式内部测试数据生成 |
| `configs/observations/unit_internal/jordan_full_state_clean.json` | 全状态、无噪声观测配置 |
| `configs/splits/unit_internal/jordan_split_i_smoke.json` | smoke 版轨线级初值泛化 split |
| `configs/splits/unit_internal/jordan_split_i_formal.json` | formal 版轨线级初值泛化 split |
| `configs/windows/unit_internal/jordan_one_step_smoke.json` | smoke 版 one-step 窗口配置 |
| `configs/windows/unit_internal/jordan_rollout_smoke.json` | smoke 版 rollout 窗口配置 |
| `configs/windows/unit_internal/jordan_one_step_formal.json` | formal 版 one-step 窗口配置 |
| `configs/windows/unit_internal/jordan_rollout_formal.json` | formal 版 rollout 窗口配置 |
| `configs/tasks/unit_internal/jordan_one_step_forecast.json` | one-step forecast task |
| `configs/tasks/unit_internal/jordan_rollout_forecast.json` | multi-step rollout task |
| `configs/benchmarks/unit_internal/jordan_nonnormal_smoke_benchmark.json` | smoke benchmark 组合配置 |
| `configs/benchmarks/unit_internal/jordan_nonnormal_formal_benchmark.json` | formal benchmark 组合配置 |
| `configs/releases/unit_internal/jordan_nonnormal_v0_1.json` | 内部版本冻结清单 |

---

#### 4.3 源码文件

| Target path | Role |
|---|---|
| `src/dynamics/jordan_nonnormal_linear.jl` | Jordan 系统矩阵、解析流、离散传播矩阵、系统元信息 |
| `src/registries/system_registry.jl` | 注册 `jordan_nonnormal_linear` |
| `src/generators/generate_jordan_nonnormal_linear.jl` | Jordan 系统专属生成器入口组件 |
| `src/diagnostics/jordan_nonnormal_diagnostics.jl` | Jordan 专属诊断：rank、闭合残差、瞬态放大 |
| `src/manifests/jordan_nonnormal_manifest.jl` | Jordan manifest 字段组织与检查 |
| `src/io/jordan_nonnormal_paths.jl` | Jordan 系统数据、报告、日志路径管理 |
| `src/utils/linear_system_checks.jl` | 线性系统通用检查，可被线性对角、旋转–收缩、Jordan 共用 |

如果前两个内部系统已经有通用文件，例如 `linear_systems.jl`、`linear_diagnostics.jl`、`path_utils.jl`，则本次优先扩展已有文件，不重复造新模块。

---

#### 4.4 实验入口文件

| Target path | Role |
|---|---|
| `experiments/smoke_tests/run_jordan_nonnormal_smoke.jl` | 最小端到端 smoke 入口 |
| `experiments/smoke_tests/run_jordan_nonnormal_formal_generation.jl` | 正式内部数据生成入口 |

说明：formal generation 目前仍可放在 `experiments/smoke_tests/` 下，因为它属于 `unit_internal` 层的内部生成与回归验证，不属于 `baseline_forecasting`、`baseline_identification` 或 `baseline_representation`。

---

#### 4.5 数据输出文件

| Target path | Role |
|---|---|
| `data/raw/unit_internal/jordan_nonnormal_linear/smoke/raw_trajectories.jld2` | smoke raw state trajectories |
| `data/processed/unit_internal/jordan_nonnormal_linear/smoke/observed_trajectories.jld2` | smoke observed trajectories |
| `data/manifests/unit_internal/jordan_nonnormal_linear/smoke/manifest.json` | smoke 数据生成元信息 |
| `data/raw/unit_internal/jordan_nonnormal_linear/formal/raw_trajectories.jld2` | formal raw state trajectories |
| `data/processed/unit_internal/jordan_nonnormal_linear/formal/observed_trajectories.jld2` | formal observed trajectories |
| `data/processed/unit_internal/jordan_nonnormal_linear/formal/splits.json` | formal split 索引 |
| `data/processed/unit_internal/jordan_nonnormal_linear/formal/windows_one_step.jld2` | formal one-step 窗口索引或样本 |
| `data/processed/unit_internal/jordan_nonnormal_linear/formal/windows_rollout.jld2` | formal rollout 窗口索引或样本 |
| `data/manifests/unit_internal/jordan_nonnormal_linear/formal/manifest.json` | formal 数据生成元信息 |
| `data/releases/unit_internal/jordan_nonnormal_linear_v0_1/release_manifest.json` | 内部冻结版本清单 |

---

#### 4.6 报告输出文件

| Target path | Role |
|---|---|
| `reports/unit_internal/jordan_nonnormal_linear/tables/smoke_diagnostics.csv` | smoke 诊断表 |
| `reports/unit_internal/jordan_nonnormal_linear/tables/formal_diagnostics.csv` | formal 诊断表 |
| `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_phase_portrait.png` | smoke 相图 |
| `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_time_series.png` | smoke 时间序列 |
| `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_norm_amplification.png` | smoke 范数瞬态放大图 |
| `reports/unit_internal/jordan_nonnormal_linear/plots/formal_phase_portrait.png` | formal 相图 |
| `reports/unit_internal/jordan_nonnormal_linear/plots/formal_norm_amplification.png` | formal 范数放大图 |
| `reports/unit_internal/jordan_nonnormal_linear/logs/smoke_generation.log` | smoke 运行日志 |
| `reports/unit_internal/jordan_nonnormal_linear/logs/formal_generation.log` | formal 运行日志 |

---

#### 4.7 测试文件

| Target path | Role |
|---|---|
| `test/unit/test_jordan_nonnormal_dynamics.jl` | 测试 $\mathbf A$、$\mathbf K_\tau$、解析解 |
| `test/unit/test_jordan_nonnormal_diagnostics.jl` | 测试 rank、几何重数、残差、瞬态放大指标 |
| `test/integration/test_jordan_nonnormal_generation_pipeline.jl` | 测试从配置到数据、split、window、manifest 的端到端流程 |
| `test/regression/test_jordan_nonnormal_smoke_regression.jl` | 固定 smoke 配置下的回归测试 |
| `test/reference_outputs/unit_internal/jordan_nonnormal_linear_smoke_reference.json` | smoke 参考输出摘要 |

---

### 5. Module / component responsibilities

#### `configs/`

只保存参数，不写逻辑。

主要控制：

$$

\alpha,\gamma,\tau,M,R,L,\text{seed},\text{split ratio}.

$$

#### `src/dynamics/`

负责系统本体：

$$

\mathbf A,\quad \mathbf K_\tau,\quad \mathbf x(t),\quad \mathbf X.

$$

不负责保存数据，不负责 split，不负责画图。

#### `src/observations/`

负责：

$$

\mathbf x_m\mapsto \mathbf z_m.

$$

本次默认是 identity observation，但仍然走统一观测链。

#### `src/generators/`

负责调度：

$$

\text{config}
\to
\text{raw}
\to
\text{processed}
\to
\text{split}
\to
\text{window}
\to
\text{manifest}.

$$

#### `src/splits/`

负责轨线级 train / val / test 切分。

#### `src/windows/`

负责 one-step 与 rollout 窗口索引。

#### `src/diagnostics/`

负责数值检查与科学诊断。

本次核心是：

$$

\operatorname{rank}(\mathbf A-\alpha I),
\quad
\dim\ker(\mathbf A-\alpha I),
\quad
\max_m\|\mathbf x_{m+1}-\mathbf K_\tau\mathbf x_m\|_2,
\quad
\max_m\frac{\|\mathbf x_m\|_2}{\|\mathbf x_1\|_2}.

$$

#### `src/manifests/`

负责记录：

- 系统参数；
- 观测配置；
- split 配置；
- window 配置；
- 随机种子；
- 数据版本；
- 文件路径；
- 诊断摘要。

#### `src/io/`

负责路径和读写协议。

#### `experiments/smoke_tests/`

只负责组织运行，不保存核心逻辑。工程指南中也强调实验入口不放核心函数，核心逻辑应沉淀到 `src/`。fileciteturn7file2

#### `test/`

负责自动化检查：

- 单模块数值正确性；
- 小型端到端流程；
- 固定配置回归结果。

---

### 6. Planned `##` sections

以下是每个计划 Julia 文件中的 `##` section 标题。只列结构，不写代码。

#### `src/dynamics/jordan_nonnormal_linear.jl`

- `## Module role and mathematical definition`
- `## Parameter validation for Jordan nonnormal system`
- `## Continuous-time generator matrix construction`
- `## Discrete-time flow matrix construction`
- `## Closed-form trajectory evaluation`
- `## Trajectory batch construction`
- `## Jordan structure metadata`
- `## Numerical consistency checks`

---

#### `src/generators/generate_jordan_nonnormal_linear.jl`

- `## Generator role and expected configuration objects`
- `## Load and validate system configuration`
- `## Load and validate observation configuration`
- `## Generate initial condition ensemble`
- `## Generate raw state trajectories`
- `## Apply observation chain`
- `## Build trajectory-level splits`
- `## Build one-step and rollout windows`
- `## Run Jordan-specific diagnostics`
- `## Save raw, processed, split, window, and manifest outputs`
- `## Save diagnostic tables and plots`

---

#### `src/diagnostics/jordan_nonnormal_diagnostics.jl`

- `## Diagnostic role for Jordan nonnormal systems`
- `## Matrix structure diagnostics`
- `## Eigenvalue and geometric multiplicity diagnostics`
- `## One-step closure residual diagnostics`
- `## Multi-step rollout residual diagnostics`
- `## Nonnormal transient amplification diagnostics`
- `## Initial condition activation diagnostics`
- `## Diagnostic summary table construction`

---

#### `src/manifests/jordan_nonnormal_manifest.jl`

- `## Manifest role and required fields`
- `## System parameter metadata`
- `## Observation metadata`
- `## Split and window metadata`
- `## File path metadata`
- `## Diagnostic summary metadata`
- `## Reproducibility metadata`
- `## Manifest validation rules`

---

#### `src/io/jordan_nonnormal_paths.jl`

- `## Path role for unit_internal Jordan dataset`
- `## Raw data path construction`
- `## Processed data path construction`
- `## Manifest path construction`
- `## Report table path construction`
- `## Report plot path construction`
- `## Log path construction`
- `## Release path construction`

---

#### `src/utils/linear_system_checks.jl`

- `## Shared linear system check utilities`
- `## Matrix dimension checks`
- `## Discrete flow consistency checks`
- `## Eigenvalue summary checks`
- `## Rank and nullity checks`
- `## Residual aggregation checks`

---

#### `src/registries/system_registry.jl`

- `## Registry role`
- `## Existing unit_internal systems`
- `## Jordan nonnormal linear system registration`
- `## Registry consistency checks`

---

#### `experiments/smoke_tests/run_jordan_nonnormal_smoke.jl`

- `## Smoke run purpose`
- `## Load smoke benchmark configuration`
- `## Resolve all dependent configuration paths`
- `## Generate smoke dataset`
- `## Run smoke diagnostics`
- `## Save smoke outputs`
- `## Print smoke summary`

---

#### `experiments/smoke_tests/run_jordan_nonnormal_formal_generation.jl`

- `## Formal generation purpose`
- `## Load formal benchmark configuration`
- `## Resolve release and output paths`
- `## Generate formal dataset`
- `## Run formal diagnostics`
- `## Save formal data products`
- `## Save release manifest`
- `## Print formal generation summary`

---

#### `test/unit/test_jordan_nonnormal_dynamics.jl`

- `## Test matrix construction`
- `## Test discrete flow construction`
- `## Test closed-form trajectory formula`
- `## Test Jordan rank and nullity`
- `## Test dimension conventions`

---

#### `test/unit/test_jordan_nonnormal_diagnostics.jl`

- `## Test one-step residual diagnostics`
- `## Test rollout residual diagnostics`
- `## Test transient amplification diagnostics`
- `## Test initial condition activation diagnostics`
- `## Test diagnostic table fields`

---

#### `test/integration/test_jordan_nonnormal_generation_pipeline.jl`

- `## Integration test purpose`
- `## Load smoke configs`
- `## Run minimal generation pipeline`
- `## Check generated files`
- `## Check split and window consistency`
- `## Check manifest completeness`

---

#### `test/regression/test_jordan_nonnormal_smoke_regression.jl`

- `## Regression test purpose`
- `## Load fixed smoke reference`
- `## Recompute smoke summary`
- `## Compare dimensions and counts`
- `## Compare numerical diagnostic tolerances`
- `## Report regression status`

---

### 7. Data flow and dimensions

#### 7.1 Configuration level

Smoke 建议维度：

$$

d_x=d_z=2,\qquad R_{\mathrm{smoke}}\text{ 小},\qquad M_{\mathrm{smoke}}\text{ 小}.

$$

Formal 建议维度：

$$

d_x=d_z=2,\qquad R_{\mathrm{formal}}>R_{\mathrm{smoke}},
\qquad M_{\mathrm{formal}}>M_{\mathrm{smoke}}.

$$

具体数值留给配置文件，不写死在源码中。

---

#### 7.2 Raw trajectory

每条轨线：

$$

\mathbf X^{(q)}
\in
\mathbb R^{2\times(M+1)}.

$$

批量轨线可理解为：

$$

\{\mathbf X^{(q)}\}_{q=1}^R.

$$

存储时建议保留：

- `trajectory_id`
- `times`
- `state_matrix`
- `parameter_instance`
- `initial_condition_instance`

---

#### 7.3 Observed trajectory

默认：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in
\mathbb R^{2\times(M+1)}.

$$

但对象层仍然保存 `state_matrix` 和 `observation_matrix`，避免未来部分观测时破坏接口。

---

#### 7.4 One-step samples

对每条轨线：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
m=1,\dots,M.

$$

其中：

$$

\mathbf z_m\in\mathbb R^2,
\qquad
\mathbf z_{m+1}\in\mathbb R^2.

$$

单条轨线样本数：

$$

M.

$$

总样本数：

$$

R_{\mathrm{split}}M.

$$

---

#### 7.5 Rollout windows

窗口长度为 $L$。

每个窗口：

$$

\mathbf W_s^{(q)}
=
\begin{bmatrix}
\mathbf z_s^{(q)}
&
\mathbf z_{s+1}^{(q)}
&
\cdots
&
\mathbf z_{s+L}^{(q)}
\end{bmatrix}
\in
\mathbb R^{2\times(L+1)}.

$$

单条轨线窗口数：

$$

M-L+1.

$$

总窗口数：

$$

R_{\mathrm{split}}(M-L+1).

$$

---

#### 7.6 Split flow

先生成完整轨线：

$$

q=1,\dots,R.

$$

再切分轨线编号：

$$

\mathcal R_{\mathrm{train}},
\mathcal R_{\mathrm{val}},
\mathcal R_{\mathrm{test}}.

$$

最后在各集合内部生成窗口。禁止先生成所有窗口再随机分配。

---

#### 7.7 Diagnostic data flow

核心诊断输入：

$$

\mathbf A,\mathbf K_\tau,\mathbf X^{(q)},\mathbf Z^{(q)}.

$$

核心诊断输出：

$$

\text{diagnostic table}
\in
\text{reports/unit_internal/jordan_nonnormal_linear/tables}.

$$

图像输出：

- 时间序列：$x_1(t),x_2(t)$；
- 相图：$(x_1(t),x_2(t))$；
- 范数曲线：$\|\mathbf x(t)\|_2$；
- 放大因子曲线：

$$

\frac{\|\mathbf x(t)\|_2}{\|\mathbf x(0)\|_2}.

$$

---

### 8. Package and documentation plan

#### `LinearAlgebra`

**Why needed**  
矩阵、范数、特征值、rank、nullspace / SVD / Schur 类诊断。

**Expected functionality**

- 构造与检查 $\mathbf A$、$\mathbf K_\tau$；
- 检查 eigenvalues；
- 检查 rank；
- 计算 norm；
- 计算残差。

**Docs to check before coding**

- rank 判定容差；
- eigenvalue 顺序是否稳定；
- Schur / eigen 分解返回对象的字段与类型。

---

#### `Random`

**Why needed**  
初值采样和 split 随机性可复现。

**Expected functionality**

- 固定 seed；
- 采样初值；
- split 洗牌。

**Docs to check before coding**

- 随机数生成器对象的推荐用法；
- 避免全局随机状态污染；
- 不同 Julia 版本下随机序列稳定性问题。

---

#### `JSON3` 或 `TOML`

**Why needed**  
读取配置文件与保存 manifest。

**Expected functionality**

- 读取 `SystemSpec`、`ObservationSpec`、`SplitSpec`；
- 写出 `manifest.json`；
- 写出 `release_manifest.json`。

**Docs to check before coding**

- JSON 对象与 Julia struct / Dict 的转换方式；
- 数组、嵌套对象、浮点数精度保存；
- pretty print 或稳定字段顺序。

---

#### `JLD2` 或 `HDF5`

**Why needed**  
保存轨线矩阵、窗口对象和中间数据。

**Expected functionality**

- 保存 raw trajectories；
- 保存 observed trajectories；
- 保存 window samples 或 window indices；
- 读取回归测试参考数据。

**Docs to check before coding**

- 多数组对象保存结构；
- 跨 Julia 版本兼容性；
- 文件覆盖策略；
- 大数据文件读取方式。

---

#### `CSV` / `Tables` / `DataFrames`

**Why needed**  
保存诊断表。

**Expected functionality**

- 输出 `smoke_diagnostics.csv`；
- 输出 `formal_diagnostics.csv`；
- 后续便于人工检查和报告汇总。

**Docs to check before coding**

- CSV 写出时浮点格式；
- 缺失值处理；
- 表结构与字段顺序稳定性。

---

#### 绘图包：`Plots.jl` 或 `CairoMakie.jl`

**Why needed**  
生成时间序列、相图、范数放大图。

**Expected functionality**

- 保存 PNG 图；
- 支持多轨线可视化；
- 支持简单坐标轴和标题。

**Docs to check before coding**

- 保存文件 API；
- 后端选择；
- 图像尺寸与分辨率设置；
- 非交互式环境下是否稳定运行。

---

#### `Test`

**Why needed**  
自动化单元测试、集成测试和回归测试。

**Expected functionality**

- 数值近似比较；
- 文件存在性检查；
- 维度与字段检查；
- 诊断指标容差检查。

**Docs to check before coding**

- 浮点近似比较方式；
- testset 组织方式；
- CI 或本地测试入口组织方式。

---

### 9. Debugging and inspection plan

#### 9.1 必须打印的摘要

Smoke 和 formal 入口都应打印：

- `system_id`
- `state_dim`
- `observation_dim`
- $\alpha$
- $\gamma$
- $\tau$
- $M$
- $R$
- rollout horizon $L$
- train / val / test 轨线数量
- one-step 样本数量
- rollout 窗口数量
- raw 输出路径
- processed 输出路径
- manifest 输出路径
- diagnostics 输出路径

---

#### 9.2 必须检查的矩阵量

$$

\mathbf A=
\begin{bmatrix}
\alpha&\gamma\\
0&\alpha
\end{bmatrix}

$$

检查：

- `size(A) = (2,2)`；
- `size(Kτ) = (2,2)`；
- repeated eigenvalue：

$$

\lambda_\tau=e^{\alpha\tau};

$$

- rank：

$$

\operatorname{rank}(\mathbf A-\alpha I)=1;

$$

- 几何重数：

$$

\dim\ker(\mathbf A-\alpha I)=1.

$$

---

#### 9.3 必须检查的轨线量

对每条轨线检查：

$$

\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

记录：

- `minimum(x1)`
- `maximum(x1)`
- `minimum(x2)`
- `maximum(x2)`
- `maximum(abs(x2))`
- `norm(x_start)`
- `max_norm`
- `final_norm`
- `max_norm / start_norm`

---

#### 9.4 必须检查的残差

一步残差：

$$

\max_{q,m}
\left\|
\mathbf x_{m+1}^{(q)}
-
\mathbf K_\tau\mathbf x_m^{(q)}
\right\|_2.

$$

多步残差：

$$

\max_{q,s,k}
\left\|
\mathbf x_{s+k}^{(q)}
-
\mathbf K_\tau^k\mathbf x_s^{(q)}
\right\|_2.

$$

解析解残差：

$$

\max_{q,m}
\left\|
\mathbf x_m^{(q)}
-
e^{t_m\mathbf A}\mathbf x_0^{(q)}
\right\|_2.

$$

这些值在解析生成路径下应接近机器精度；若数值积分路径参与交叉验证，则容差应由 solver tolerance 决定。

---

#### 9.5 必须检查的 split 与 window

Split 检查：

$$

\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{val}}
=
\varnothing,

$$

$$

\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{test}}
=
\varnothing,

$$

$$

\mathcal R_{\mathrm{val}}
\cap
\mathcal R_{\mathrm{test}}
=
\varnothing.

$$

Window 检查：

- one-step 样本数量是否为 $R_{\mathrm{split}}M$；
- rollout 数量是否为 $R_{\mathrm{split}}(M-L+1)$；
- 所有窗口 start index 满足：

$$

1\le s\le M-L+1.

$$

---

#### 9.6 必须保存的图

Smoke 至少保存：

- `smoke_time_series.png`
- `smoke_phase_portrait.png`
- `smoke_norm_amplification.png`

Formal 至少保存：

- `formal_phase_portrait.png`
- `formal_norm_amplification.png`

图像只用于人工检查，不作为数据对象本身。

---

### 10. Expected outputs

本次任务完成后，应能得到以下输出。

#### 10.1 Smoke 输出

- `data/raw/unit_internal/jordan_nonnormal_linear/smoke/raw_trajectories.jld2`
- `data/processed/unit_internal/jordan_nonnormal_linear/smoke/observed_trajectories.jld2`
- `data/manifests/unit_internal/jordan_nonnormal_linear/smoke/manifest.json`
- `reports/unit_internal/jordan_nonnormal_linear/tables/smoke_diagnostics.csv`
- `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_time_series.png`
- `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_phase_portrait.png`
- `reports/unit_internal/jordan_nonnormal_linear/plots/smoke_norm_amplification.png`
- `reports/unit_internal/jordan_nonnormal_linear/logs/smoke_generation.log`

---

#### 10.2 Formal 输出

- `data/raw/unit_internal/jordan_nonnormal_linear/formal/raw_trajectories.jld2`
- `data/processed/unit_internal/jordan_nonnormal_linear/formal/observed_trajectories.jld2`
- `data/processed/unit_internal/jordan_nonnormal_linear/formal/splits.json`
- `data/processed/unit_internal/jordan_nonnormal_linear/formal/windows_one_step.jld2`
- `data/processed/unit_internal/jordan_nonnormal_linear/formal/windows_rollout.jld2`
- `data/manifests/unit_internal/jordan_nonnormal_linear/formal/manifest.json`
- `data/releases/unit_internal/jordan_nonnormal_linear_v0_1/release_manifest.json`
- `reports/unit_internal/jordan_nonnormal_linear/tables/formal_diagnostics.csv`
- `reports/unit_internal/jordan_nonnormal_linear/plots/formal_phase_portrait.png`
- `reports/unit_internal/jordan_nonnormal_linear/plots/formal_norm_amplification.png`
- `reports/unit_internal/jordan_nonnormal_linear/logs/formal_generation.log`

---

#### 10.3 测试输出

- `test/reference_outputs/unit_internal/jordan_nonnormal_linear_smoke_reference.json`

该文件保存 smoke 配置下的参考摘要，例如：

- 轨线条数；
- 每条轨线长度；
- one-step 样本数；
- rollout 窗口数；
- 关键残差上界；
- rank 与几何重数；
- 最大范数放大因子。

---

### 11. Failure points and debugging strategies

#### 11.1 非正规项不可见

**Symptom**  
相图看起来像普通指数衰减，没有明显剪切或瞬态放大。

**Likely cause**

$$

x_{2,0}\approx 0

$$

或

$$

\gamma\tau\approx 0.

$$

**Debugging strategy**

- 检查初值采样中 $x_{2,0}$ 的分布；
- 检查 $\gamma$ 与 $\tau$；
- 检查 `max_norm / start_norm` 是否大于 1；
- 在 smoke 配置中选几条明确激活 $x_2$ 的初值。

---

#### 11.2 误判为对角系统

**Symptom**  
诊断只看到重复特征值，但没有确认 Jordan 结构。

**Likely cause**  
只检查 eigenvalues，没有检查 rank / nullity。

**Debugging strategy**

- 必须检查：

$$

\operatorname{rank}(\mathbf A-\alpha I)=1;

$$

- 必须检查：

$$

\dim\ker(\mathbf A-\alpha I)=1.

$$

---

#### 11.3 轨线衰减太快

**Symptom**  
大部分时间点接近零，窗口信息量很低。

**Likely cause**  
$|\alpha|$ 太大或时间窗太长。

**Debugging strategy**

- 检查终点范数；
- 检查 $t_\star\approx -1/\alpha$ 是否落在采样区间内；
- 调整 formal 配置中的 $\alpha$、$\tau$、$M$。

---

#### 11.4 轨线增长或放大过强

**Symptom**  
数据尺度过大，图像或残差异常。

**Likely cause**  
$\gamma$ 太大，或者初值范围太大。

**Debugging strategy**

- 检查最大范数；
- 检查 $\gamma t e^{\alpha t}$ 的峰值量级；
- 缩小初值范围或减小 $\gamma$。

---

#### 11.5 split 泄漏

**Symptom**  
train / test 窗口来自同一条轨线。

**Likely cause**  
先生成窗口再 split。

**Debugging strategy**

- split 必须存 trajectory id；
- window 生成时必须绑定 split；
- integration test 检查 train / val / test 的 trajectory id 互斥。

---

#### 11.6 window off-by-one 错误

**Symptom**  
rollout 窗口长度不一致，或者访问 $M+2$ 快照。

**Likely cause**  
把 $M$、$M+1$、horizon $L$ 混淆。

**Debugging strategy**

- 明确轨线矩阵列数是 $M+1$；
- one-step 有 $M$ 个相邻对；
- rollout 起点最大为 $M-L+1$；
- 单个 rollout window shape 应为 $2\times(L+1)$。

---

#### 11.7 manifest 不完整

**Symptom**  
生成的数据无法复现。

**Likely cause**  
manifest 未记录配置路径、随机种子、参数、split、window 或输出路径。

**Debugging strategy**

manifest 必须至少记录：

- `system_id`
- `observation_id`
- `split_id`
- `window_ids`
- `task_ids`
- `alpha`
- `gamma`
- `dt`
- `trajectory_length`
- `num_trajectories`
- `seed`
- `raw_data_path`
- `processed_data_path`
- `diagnostics_path`
- `generator_version`
- `created_at`

---

### 12. Stop before code

到这里，本次 Jordan / 非正规线性系统的代码工程计划已经完整覆盖：

- 配置对象；
- 源码模块；
- smoke 与 formal 入口；
- 数据、manifest、报告与测试输出；
- 维度流；
- 诊断指标；
- 失败点与调试策略。

我在这里停止，不写 Julia 代码。下一步需要单独给出实现请求。
