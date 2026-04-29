# Step 2：Rössler 系统详细代码工程计划书

## 1. Confirmed task summary

本次确认接入 **Rössler 系统**，作为 `ODEs_dataset` 的 `v1_core` 经典混沌系统之一。项目指南中已将 Rössler 列入 `v1_core`，并要求新增系统同时具备 `SystemSpec`、`ObservationSpec`、`SplitSpec`、`TaskSpec`、smoke test 与 manifest 示例。fileciteturn4file0

本任务固定为：

$$

\begin{aligned}
\dot x &= -y-z,\\
\dot y &= x+a y,\\
\dot z &= b+z(x-c),
\end{aligned}
\qquad
(a,b,c)=(0.2,0.2,5.7).

$$

设：

$$

\mathbf x(t)=(x(t),y(t),z(t))^\top\in\mathbb R^3.

$$

采用：

- 标准参数；
- 固定参数，不做参数泛化；
- 全状态观测；
- 无噪声；
- burn-in 后保存吸引子轨线；
- 正式诊断输出三维相空间轨线图；
- 轨线级 train / val / test 切分；
- 支持 one-step、rollout、statistics 窗口。

项目规范中数据对象应经过

$$

\mathbf x \xmapsto{U} \mathbf u \xmapsto{S} \mathbf s \xmapsto{Z} \mathbf z

$$

的观测链；低维 ODE 全状态情形可以取 $U=S=Z=\mathcal I$，此时 $\mathbf z=\mathbf x$。fileciteturn4file0

---

## 2. Task decomposition

本任务分为 12 个子任务。

1. 注册 Rössler 动力系统配置。
2. 注册全状态无噪声观测配置。
3. 注册 Split-I 初值泛化切分配置。
4. 注册 one-step、rollout、statistics 窗口配置。
5. 注册基础 benchmark task 配置。
6. 实现 Rössler 右端函数与系统元信息。
7. 实现基于配置的轨线生成流程。
8. 实现 burn-in 后吸引子轨线保存。
9. 实现全状态观测处理。
10. 实现数据质量诊断，包括三维相空间图。
11. 实现 smoke test 实验入口。
12. 实现回归测试与 manifest 检查。

---

## 3. Sub-task specification

### 3.1 Rössler `SystemSpec`

**Purpose**  
声明 Rössler 系统的动力学、参数、初值范围、采样步长、轨线长度、积分器公差和随机种子策略。

**Input**

- `system_id = rossler_standard`
- `family = chaotic_ode`
- `state_dim = 3`
- parameters：
  $$

  a=0.2,\quad b=0.2,\quad c=5.7
  
$$
- initial condition domain：
  $$

  \mathbf x_0=(x_0,y_0,z_0)^\top\in\Omega_0\subset\mathbb R^3
  
$$
- burn-in time：
  $$

  T_{\mathrm{burn}}>0
  
$$
- sampling step：
  $$

  \tau>0
  
$$
- saved trajectory length：
  $$

  M+1
  
$$

**Output**

- 一个系统配置文件；
- 可被 generator 读取的系统元信息。

**Dependency**

无前置依赖，但必须符合已有 `SystemSpec` 协议。

**Mathematical expression**

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x)
=
\begin{bmatrix}
-y-z\\
x+a y\\
b+z(x-c)
\end{bmatrix}.

$$

**Diagnostic checks**

- `state_dim == 3`
- 参数名称与参数值数量一致；
- `dt > 0`
- `trajectory_length > 0`
- `burnin_time > 0`
- 固定参数版本中 `parameter_domain` 应退化为单点或明确声明无参数扫描。

---

### 3.2 全状态 `ObservationSpec`

**Purpose**  
声明从状态到数据对象的观测链。

**Input**

$$

\mathbf x_m\in\mathbb R^3.

$$

**Output**

$$

\mathbf z_m=\mathbf x_m\in\mathbb R^3.

$$

**Dependency**

依赖 Rössler `SystemSpec` 的 `state_dim = 3`。

**Mathematical expression**

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,
\qquad
\mathbf z_m=\mathbf x_m.

$$

**Diagnostic checks**

- `output_dim == 3`
- `noise_model == none`
- `noise_level == 0`
- `normalization_policy == none` 或明确标记为 raw physical scale；
- `observation_matrix` 与 `state_matrix` 维度一致。

---

### 3.3 Split-I 初值泛化配置

**Purpose**  
固定参数，使用不同初值轨线进行 train / val / test 切分。

**Input**

轨线编号集合：

$$

\mathcal R=\{1,\dots,R\}.

$$

**Output**

$$

\mathcal R_{\mathrm{train}},
\quad
\mathcal R_{\mathrm{val}},
\quad
\mathcal R_{\mathrm{test}}.

$$

**Dependency**

依赖已生成的轨线列表或轨线 manifest。

**Mathematical expression**

默认比例：

$$

70\%/15\%/15\%.

$$

切分单位必须是整条轨线，而不是窗口。项目规范明确要求先按轨线切分，再在各自集合内部派生窗口，禁止将同一条轨线的相邻窗口分散到 train 与 test。fileciteturn4file0

**Diagnostic checks**

- 三个集合互不相交；
- 并集等于全部轨线；
- 每条轨线只属于一个 split；
- split 结果可由 seed 复现。

---

### 3.4 窗口配置

**Purpose**  
从观测轨线中派生 one-step、rollout、statistics 三类任务样本。

**Input**

$$

\mathbf Z^{(q)}
=
[\mathbf z_1^{(q)},\dots,\mathbf z_{M+1}^{(q)}]
\in\mathbb R^{3\times(M+1)}.

$$

**Output**

one-step：

$$

(\mathbf z_m,\mathbf z_{m+1}).

$$

rollout：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

statistics：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1}).

$$

**Dependency**

依赖 split 结果；窗口只能在各 split 内部分别生成。

**Diagnostic checks**

- one-step 样本数应为每条轨线 $M$；
- rollout 起点满足：
  $$

  1\le s\le M+1-L;
  
$$
- statistics 窗口长度一致；
- 不跨轨线、不跨 split。

---

### 3.5 TaskSpec 与 benchmark 配置

**Purpose**  
声明 Rössler 数据支持哪些标准任务。

**Input**

- one-step samples；
- rollout windows；
- statistics windows。

**Output**

任务配置：

- `one_step_forecast`
- `multi_step_rollout`
- `long_time_statistics`

**Dependency**

依赖 window 配置。

**Mathematical expressions**

一步预测误差：

$$

\mathcal E_{\mathrm{1step}}
=
\frac1M
\sum_m
\|\widehat{\mathbf z}_{m+1}-\mathbf z_{m+1}\|_2^2.

$$

rollout 误差：

$$

\mathcal E_{\mathrm{roll}}^{(L)}
=
\frac1S
\sum_s
\frac1L
\sum_{\ell=1}^L
\|\widehat{\mathbf z}_{s+\ell\mid s}-\mathbf z_{s+\ell}\|_2^2.

$$

长期统计诊断至少包括均值、协方差、坐标范围、吸引子几何图。

**Diagnostic checks**

- task 引用的 `window_id` 存在；
- metric 列表与 task 类型一致；
- benchmark 引用的 system、observation、split、window、task 均存在。

---

### 3.6 Rössler 动力学模块

**Purpose**  
提供可复用的 Rössler 右端函数和系统元信息。

**Input**

$$

\mathbf x=(x,y,z)^\top,
\qquad
(a,b,c).

$$

**Output**

$$

\dot{\mathbf x}=\mathbf f(\mathbf x).

$$

**Dependency**

由 generator 调用，不应直接负责数据保存、绘图或 split。

**Relevant expression**

$$

\mathbf f(\mathbf x)
=
(-y-z,\ x+a y,\ b+z(x-c))^\top.

$$

**Diagnostic checks**

- 输入状态长度为 3；
- 输出导数长度为 3；
- 参数包含 $a,b,c$；
- 对典型状态无 NaN / Inf。

---

### 3.7 轨线生成器

**Purpose**  
根据 `SystemSpec` 和 `ObservationSpec` 生成 raw 与 processed 数据。

项目规范要求数据生成按固定流水线执行：参数与初值采样、状态轨线生成、观测链处理、轨线级存盘、split、窗口、task、manifest。fileciteturn4file0

**Input**

- system config；
- observation config；
- split config；
- window config；
- random seed。

**Output**

- raw trajectories；
- observed trajectories；
- split index；
- window index；
- manifest；
- diagnostic tables；
- diagnostic plots。

**Dependency**

依赖：

- Rössler dynamics；
- observation chain；
- IO utilities；
- manifest utilities；
- diagnostics utilities。

**Diagnostic checks**

- 轨线数量 $R$ 正确；
- 每条轨线状态矩阵形状：
  $$

  3\times(M+1)
  
$$
- 每条观测矩阵形状：
  $$

  3\times(M+1)
  
$$
- time vector 长度：
  $$

  M+1
  
$$
- raw 与 processed 的 trajectory id 对齐。

---

### 3.8 Burn-in 与吸引子保存

**Purpose**  
避免保存暂态轨线，保证正式数据主要位于 Rössler 吸引子上。

**Input**

初值：

$$

\mathbf x_0^{(q)}.

$$

**Output**

保存轨线：

$$

\mathbf x_m^{(q)}
=
\mathbf x(T_{\mathrm{burn}}+m\tau;\mathbf x_0^{(q)}),
\qquad
m=0,\dots,M.

$$

**Dependency**

依赖数值积分器和采样策略。

**Diagnostic checks**

- burn-in 前状态不写入正式 raw trajectory；
- manifest 中记录 `burnin_time`；
- 保存时间从正式区间开始；
- 若保留调试信息，可记录 burn-in 结束状态：
  $$

  \mathbf x_{\mathrm{burn}}^{(q)}.
  
$$

---

### 3.9 数据质量诊断

**Purpose**  
验证 Rössler 轨线合理、有限、落入混沌吸引子区域，并生成可人工检查的图和表。

**Input**

$$

\mathbf X^{(q)}\in\mathbb R^{3\times(M+1)}.

$$

**Output**

- 坐标范围表；
- 均值与标准差表；
- 增量范数表；
- 散度长期平均表；
- 三维相空间图；
- 可选二维投影图。

**Relevant expressions**

坐标均值：

$$

\bar{\mathbf x}^{(q)}
=
\frac1{M+1}
\sum_{m=0}^M
\mathbf x_m^{(q)}.

$$

协方差：

$$

\mathbf C_x^{(q)}
=
\frac1M
\sum_{m=0}^M
(\mathbf x_m^{(q)}-\bar{\mathbf x}^{(q)})
(\mathbf x_m^{(q)}-\bar{\mathbf x}^{(q)})^\top.

$$

步进增量：

$$

\Delta_m^{(q)}
=
\|\mathbf x_{m+1}^{(q)}-\mathbf x_m^{(q)}\|_2.

$$

散度：

$$

\nabla\cdot \mathbf f
=
x+a-c.

$$

标准参数下：

$$

\nabla\cdot \mathbf f=x-5.5.

$$

**Diagnostic checks**

- 无 NaN / Inf；
- $\max_m\|\mathbf x_m\|_2$ 不异常；
- $\max_m \Delta_m$ 不异常；
- 长期平均散度大体为负；
- 三维相图呈 Rössler 单卷曲吸引子结构。

---

### 3.10 Smoke test

**Purpose**  
最小规模验证 Rössler 系统配置、积分、观测、保存、manifest 和绘图全流程可运行。

**Input**

小规模参数，例如：

- 较少轨线数 $R_{\mathrm{smoke}}$；
- 较短轨线长度 $M_{\mathrm{smoke}}$；
- 固定 seed；
- 保留 burn-in。

**Output**

- 小型 raw 文件；
- 小型 processed 文件；
- 小型 manifest；
- 小型诊断表；
- 一张三维相空间 smoke 图。

**Dependency**

依赖完整 generator，但使用 smoke config。

**Diagnostic checks**

- 流程能端到端完成；
- 文件全部生成；
- 数据维度正确；
- plot 文件非空；
- manifest 字段完整。

---

### 3.11 Regression test

**Purpose**  
防止后续修改破坏 Rössler 数据生成协议。

**Input**

固定 smoke config 和 seed。

**Output**

回归检查结果。

**Diagnostic checks**

- 轨线条数固定；
- 每条轨线长度固定；
- state_dim 与 output_dim 固定为 3；
- split 大小固定；
- one-step 样本数固定；
- rollout 窗口数固定；
- manifest 中 system id、参数、dt、burn-in、seed 与预期一致。

---

## 4. Directory and file plan

以下路径以 `ODEs_dataset/` 为项目根目录。代码指南中规定配置放在 `configs/`，源码放在 `src/`，数据放在 `data/`，实验入口放在 `experiments/`，诊断输出放在 `reports/`，测试放在 `test/`。fileciteturn4file0

### 4.1 文档文件

| 目标路径 | 作用 |
|---|---|
| `docs/notes/mathematical explanation/rossler_standard_math.md` | 保存本次数学说明书 |
| `docs/notes/code explanation/rossler_standard_code_plan.md` | 保存本代码工程计划书 |
| `docs/notes/file explanation/rossler_standard_file_explanation.md` | 任务完成后记录生成文件说明 |
| `docs/spec/object_registry.md` | 追加 Rössler 系统注册记录 |
| `docs/spec/project_task_list.md` | 追加本次开发任务状态 |

### 4.2 配置文件

| 目标路径 | 作用 |
|---|---|
| `configs/systems/rossler_standard.json` | Rössler 系统参数、初值范围、dt、burn-in、轨线长度、积分器公差 |
| `configs/observations/rossler_full_state_clean.json` | 全状态、无噪声、无归一化观测配置 |
| `configs/splits/rossler_split_initial_condition.json` | Split-I 初值泛化配置 |
| `configs/windows/rossler_one_step.json` | one-step 样本窗口配置 |
| `configs/windows/rossler_rollout_short.json` | 短期 rollout 窗口配置 |
| `configs/windows/rossler_rollout_long.json` | 长期 rollout 窗口配置 |
| `configs/windows/rossler_statistics_window.json` | 长期统计窗口配置 |
| `configs/tasks/rossler_forecasting_tasks.json` | one-step、rollout、statistics 任务配置 |
| `configs/benchmarks/rossler_v1_core_benchmark.json` | Rössler v1_core benchmark 组合配置 |
| `configs/releases/rossler_v1_core_release.json` | 正式 release 清单配置 |

### 4.3 源码文件

| 目标路径 | 作用 |
|---|---|
| `src/dynamics/rossler.jl` | Rössler 右端函数与系统元信息 |
| `src/generators/generate_rossler.jl` | 基于配置生成 Rössler raw / processed / split / window / manifest |
| `src/diagnostics/rossler_diagnostics.jl` | Rössler 专属数据质量诊断与三维相图诊断 |
| `src/registries/register_rossler.jl` | 将 Rössler 挂入系统注册表 |
| `src/manifests/rossler_manifest.jl` | Rössler manifest 字段组织与检查 |
| `src/io/rossler_paths.jl` | Rössler 数据与报告路径管理；若已有通用 path 模块，则不新增专用文件 |

### 4.4 实验入口

| 目标路径 | 作用 |
|---|---|
| `experiments/smoke_tests/smoke_rossler_standard.jl` | 最小规模 Rössler 端到端生成测试 |
| `experiments/baseline_forecasting/generate_rossler_v1_core.jl` | 正式生成 Rössler v1_core 数据入口 |

这里的 `baseline_forecasting` 不表示训练 baseline，而是沿用工程目录中预测类 benchmark 入口位置；核心生成逻辑仍在 `src/generators/`。

### 4.5 数据产物

| 目标路径 | 作用 |
|---|---|
| `data/raw/rossler_standard/` | 保存 burn-in 后的原始状态轨线 |
| `data/processed/rossler_full_state_clean/` | 保存全状态观测轨线 |
| `data/manifests/rossler_standard/` | 保存生成元信息 |
| `data/releases/v1_core/rossler_standard/` | 保存正式 release 索引或冻结清单 |

### 4.6 报告产物

| 目标路径 | 作用 |
|---|---|
| `reports/tables/rossler_standard/trajectory_summary.csv` | 轨线范围、均值、标准差、增量范数汇总 |
| `reports/tables/rossler_standard/split_summary.csv` | train / val / test 轨线数与窗口数 |
| `reports/tables/rossler_standard/statistics_summary.csv` | 长期统计诊断表 |
| `reports/plots/rossler_standard/phase3d_attractor.png` | 正式三维相空间吸引子图 |
| `reports/plots/rossler_standard/phase_xy.png` | $x$-$y$ 投影图 |
| `reports/plots/rossler_standard/phase_xz.png` | $x$-$z$ 投影图 |
| `reports/plots/rossler_standard/phase_yz.png` | $y$-$z$ 投影图 |
| `reports/plots/rossler_standard/timeseries_xyz.png` | 三个坐标的时间序列图 |
| `reports/logs/rossler_standard/generation_log.txt` | 正式生成日志 |
| `reports/logs/rossler_standard/smoke_log.txt` | smoke 运行日志 |

### 4.7 测试文件

| 目标路径 | 作用 |
|---|---|
| `test/unit/test_rossler_dynamics.jl` | 检查 Rössler 右端函数维度与数值有限性 |
| `test/integration/test_rossler_generation_smoke.jl` | 检查 smoke 数据生成端到端流程 |
| `test/regression/test_rossler_standard_regression.jl` | 检查固定 seed 下样本数、split、manifest、维度稳定 |

---

## 5. Module / component responsibilities

### `configs/systems/`

只描述系统本体和生成参数：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\boldsymbol\mu),
\qquad
\boldsymbol\mu=(0.2,0.2,5.7).

$$

不写观测、不写 split、不写窗口逻辑。

### `configs/observations/`

只描述：

$$

\mathbf z=\mathbf x.

$$

不写动力系统，不写任务。

### `configs/splits/`

只描述轨线级切分：

$$

\mathcal R
\to
\mathcal R_{\mathrm{train}},
\mathcal R_{\mathrm{val}},
\mathcal R_{\mathrm{test}}.

$$

### `configs/windows/`

只描述如何从每条观测轨线内部生成窗口。

### `src/dynamics/`

只负责 Rössler 右端函数和系统元信息。

### `src/generators/`

负责串联：

$$

\text{config}
\to
\text{integrate}
\to
\text{observe}
\to
\text{save}
\to
\text{split}
\to
\text{window}
\to
\text{manifest}.

$$

### `src/diagnostics/`

负责数据检查、统计表、三维相空间图，不负责生成动力学。

### `src/manifests/`

负责记录：

- system id；
- 参数；
- dt；
- burn-in；
- solver；
- tolerance；
- seed；
- trajectory ids；
- observation id；
- split id；
- window ids；
- task ids；
- generated file paths。

### `experiments/`

只作为入口，不堆积核心函数。

### `data/`

保存机器可读数据。

### `reports/`

保存人类可读表格、图和日志。

### `test/`

保存自动化检查。

---

## 6. Planned `##` sections

### `src/dynamics/rossler.jl`

计划章节：

1. `## Module purpose and mathematical definition`
2. `## Rössler parameter validation`
3. `## Rössler vector field evaluation`
4. `## System metadata construction`
5. `## Basic finite-value diagnostics`

### `src/generators/generate_rossler.jl`

计划章节：

1. `## Load Rössler generation configs`
2. `## Validate system, observation, split, and window specs`
3. `## Sample trajectory initial conditions`
4. `## Integrate burn-in segment`
5. `## Integrate saved attractor segment`
6. `## Build raw trajectory objects`
7. `## Apply full-state clean observation chain`
8. `## Save raw and processed trajectories`
9. `## Build trajectory-level split indices`
10. `## Derive one-step, rollout, and statistics windows`
11. `## Build task objects and benchmark references`
12. `## Write manifest and release metadata`
13. `## Run Rössler diagnostics`
14. `## Write generation log`

### `src/diagnostics/rossler_diagnostics.jl`

计划章节：

1. `## Load Rössler trajectory objects`
2. `## Check array dimensions and finite values`
3. `## Compute coordinate ranges`
4. `## Compute trajectory means and covariance summaries`
5. `## Compute step-increment diagnostics`
6. `## Compute divergence statistics`
7. `## Build time-series diagnostic plots`
8. `## Build two-dimensional phase projection plots`
9. `## Build three-dimensional attractor plot`
10. `## Save diagnostic tables and plot metadata`

### `src/registries/register_rossler.jl`

计划章节：

1. `## Registry purpose`
2. `## Register Rössler system id`
3. `## Register default observation id`
4. `## Register default split and window ids`
5. `## Register v1_core benchmark references`
6. `## Registry consistency checks`

### `src/manifests/rossler_manifest.jl`

计划章节：

1. `## Manifest schema for Rössler`
2. `## System and parameter metadata`
3. `## Solver and sampling metadata`
4. `## Burn-in metadata`
5. `## Observation metadata`
6. `## Split and window metadata`
7. `## File path metadata`
8. `## Manifest validation checks`

### `src/io/rossler_paths.jl`

计划章节：

1. `## Rössler path naming conventions`
2. `## Raw data path construction`
3. `## Processed data path construction`
4. `## Manifest path construction`
5. `## Report table path construction`
6. `## Report plot path construction`
7. `## Release path construction`

### `experiments/smoke_tests/smoke_rossler_standard.jl`

计划章节：

1. `## Smoke test purpose`
2. `## Load smoke-scale Rössler configs`
3. `## Run end-to-end generation`
4. `## Check generated files`
5. `## Check trajectory and observation dimensions`
6. `## Check manifest completeness`
7. `## Check diagnostic figure existence`
8. `## Write smoke log`

### `experiments/baseline_forecasting/generate_rossler_v1_core.jl`

计划章节：

1. `## Formal v1_core generation purpose`
2. `## Load formal Rössler configs`
3. `## Run formal attractor trajectory generation`
4. `## Run formal split and window derivation`
5. `## Run formal diagnostics`
6. `## Freeze release metadata`
7. `## Write formal generation log`

### `test/unit/test_rossler_dynamics.jl`

计划章节：

1. `## Test vector-field output dimension`
2. `## Test standard-parameter finite output`
3. `## Test parameter validation behavior`
4. `## Test metadata consistency`

### `test/integration/test_rossler_generation_smoke.jl`

计划章节：

1. `## Test smoke config loading`
2. `## Test smoke trajectory generation`
3. `## Test raw and processed object creation`
4. `## Test split and window creation`
5. `## Test smoke manifest creation`
6. `## Test smoke plot creation`

### `test/regression/test_rossler_standard_regression.jl`

计划章节：

1. `## Load fixed regression configuration`
2. `## Check trajectory count and dimensions`
3. `## Check split counts`
4. `## Check window counts`
5. `## Check manifest stable fields`
6. `## Check diagnostic summary fields`

---

## 7. Data flow and dimensions

### 7.1 Single trajectory

Initial state:

$$

\mathbf x_0^{(q)}\in\mathbb R^3.

$$

After burn-in:

$$

\mathbf x_{\mathrm{burn}}^{(q)}
=
\mathbf x(T_{\mathrm{burn}};\mathbf x_0^{(q)})
\in\mathbb R^3.

$$

Saved trajectory:

$$

\mathbf X^{(q)}
=
[\mathbf x_0^{(q,\mathrm{save})},\dots,\mathbf x_M^{(q,\mathrm{save})}]
\in\mathbb R^{3\times(M+1)}.

$$

Full-state observation:

$$

\mathbf Z^{(q)}
=
\mathbf X^{(q)}
\in\mathbb R^{3\times(M+1)}.

$$

### 7.2 Multiple trajectories

For $R$ trajectories:

$$

\{\mathbf X^{(q)}\}_{q=1}^R,
\qquad
\{\mathbf Z^{(q)}\}_{q=1}^R.

$$

Each matrix has shape:

$$

3\times(M+1).

$$

### 7.3 Split

Trajectory ids:

$$

\mathcal R
=
\{1,\dots,R\}.

$$

Split:

$$

\mathcal R_{\mathrm{train}}
\cup
\mathcal R_{\mathrm{val}}
\cup
\mathcal R_{\mathrm{test}}
=
\mathcal R,

$$

with disjoint subsets.

### 7.4 One-step windows

For one trajectory:

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
m=0,\dots,M-1.

$$

Number per trajectory:

$$

M.

$$

Each input and target has dimension:

$$

3.

$$

### 7.5 Rollout windows

For horizon $L$:

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

Valid start index count per trajectory:

$$

M+1-L.

$$

Input:

$$

\mathbf z_s\in\mathbb R^3.

$$

Target sequence:

$$

[\mathbf z_{s+1},\dots,\mathbf z_{s+L}]
\in\mathbb R^{3\times L}.

$$

### 7.6 Statistics windows

For statistics horizon $L_{\mathrm{stat}}$:

$$

[\mathbf z_s,\dots,\mathbf z_{s+L_{\mathrm{stat}}-1}]
\in\mathbb R^{3\times L_{\mathrm{stat}}}.

$$

Used for:

- time average；
- covariance；
- marginal distribution；
- attractor geometry diagnostics；
- power-spectrum preparation, if needed later.

---

## 8. Package and documentation plan

### DifferentialEquations.jl / OrdinaryDiffEq.jl

**Why needed**  
用于连续时间 ODE 数值积分。

**Expected functionality**

- 定义三维 ODE 初值问题；
- 设置积分时间区间；
- 设置保存采样点；
- 设置绝对误差与相对误差公差；
- 批量生成多条轨线。

**Documentation to check**

- ODEProblem 构造方式；
- solver 选择；
- `saveat` 或等价采样机制；
- tolerance 参数；
- 解对象转数组的推荐方式；
- 是否需要避免保存 burn-in 段。

不从记忆中假设 API 名称、关键字或 solver 默认行为。

### JSON3.jl / TOML.jl

**Why needed**  
读取配置文件。你当前规划中配置可以用 JSON；若项目已有 TOML 约定，则保持一致。

**Expected functionality**

- 读取 system / observation / split / window / task 配置；
- 将配置转换成内部 spec 对象；
- 保存 frozen config 或 manifest 片段。

**Documentation to check**

- 解析 JSON object 的字段访问方式；
- 数组、字典、数值类型的读写细节；
- 浮点数精度是否会被改变。

### JLD2.jl / HDF5.jl

**Why needed**  
保存轨线矩阵、时间向量、split index、window index 和 manifest 引用。

**Expected functionality**

- 保存多个轨线对象；
- 保存矩阵 $\mathbf X,\mathbf Z$；
- 保存元数据；
- 读取时保持数组维度。

**Documentation to check**

- 文件结构组织方式；
- group / dataset 的推荐写法；
- 数组维度读写是否保持列优先约定；
- 与 Windows 路径兼容性。

### Statistics / LinearAlgebra

**Why needed**  
计算均值、协方差、范数、有限性检查和基础统计量。

**Expected functionality**

- 均值；
- 标准差；
- 协方差；
- 向量范数；
- 矩阵维度检查。

**Documentation to check**

主要是确认项目中已有工具函数是否已经封装，不重复实现。

### Plots.jl / Makie.jl

**Why needed**  
输出 Rössler 三维相空间图和二维投影图。

**Expected functionality**

- 三维轨线图；
- 二维相图；
- 时间序列图；
- 保存 PNG 或 PDF。

**Documentation to check**

- 三维绘图接口；
- 后端设置；
- 保存图片 API；
- 大量点绘图性能；
- 透明度和抽样策略。

---

## 9. Debugging and inspection plan

### 9.1 配置检查

需要打印或记录：

- `system_id`
- `observation_id`
- `split_id`
- `window_id`
- `task_id`
- $a,b,c$
- $d_x=3$
- $d_z=3$
- $R$
- $M+1$
- $\tau$
- $T_{\mathrm{burn}}$
- solver name
- tolerance
- seed

### 9.2 轨线检查

对每条轨线检查：

$$

\mathrm{size}(\mathbf X^{(q)})=(3,M+1),
\qquad
\mathrm{size}(\mathbf Z^{(q)})=(3,M+1).

$$

检查：

- no NaN；
- no Inf；
- coordinate min / max；
- coordinate mean / std；
- maximum state norm；
- maximum step increment；
- average step increment。

### 9.3 吸引子检查

输出：

- `phase3d_attractor.png`
- `phase_xy.png`
- `phase_xz.png`
- `phase_yz.png`
- `timeseries_xyz.png`

三维图应使用正式轨线，优先使用 test 或第一条代表轨线，也可以叠加少量轨线，但不要把所有点完全堆叠导致不可读。

### 9.4 散度检查

计算：

$$

d_m=x_m+a-c.

$$

记录：

$$

\min_m d_m,\quad
\max_m d_m,\quad
\frac1{M+1}\sum_m d_m.

$$

长期平均散度应大体为负，用作耗散性诊断。

### 9.5 Split 检查

记录：

- train trajectory count；
- val trajectory count；
- test trajectory count；
- 三者是否互斥；
- 是否覆盖全部轨线；
- seed 是否写入 manifest。

### 9.6 Window 检查

记录：

- one-step sample count；
- short rollout window count；
- long rollout window count；
- statistics window count；
- 每类窗口的 horizon；
- 每个窗口 start index 是否合法；
- 是否存在跨 split 或跨轨线窗口。

### 9.7 Manifest 检查

检查 manifest 是否包含：

- dataset version；
- system id；
- observation id；
- split id；
- window ids；
- task ids；
- benchmark id；
- release id；
- generator metadata；
- solver metadata；
- burn-in metadata；
- file path 列表；
- created time；
- seed。

### 9.8 Smoke 检查

smoke test 应输出紧凑日志：

- config successfully loaded；
- generated trajectory count；
- saved raw path；
- saved processed path；
- saved manifest path；
- saved plot path；
- all dimension checks passed。

---

## 10. Expected outputs

### 10.1 数据输出

- `data/raw/rossler_standard/`
  - burn-in 后的 $\mathbf X^{(q)}\in\mathbb R^{3\times(M+1)}$
  - time vector
  - trajectory metadata

- `data/processed/rossler_full_state_clean/`
  - $\mathbf Z^{(q)}=\mathbf X^{(q)}$
  - observation metadata

- `data/manifests/rossler_standard/`
  - generation manifest
  - split manifest
  - window manifest
  - task manifest

- `data/releases/v1_core/rossler_standard/`
  - release index
  - frozen config references
  - generated file list

### 10.2 报告输出

- `reports/tables/rossler_standard/trajectory_summary.csv`
- `reports/tables/rossler_standard/split_summary.csv`
- `reports/tables/rossler_standard/statistics_summary.csv`
- `reports/plots/rossler_standard/phase3d_attractor.png`
- `reports/plots/rossler_standard/phase_xy.png`
- `reports/plots/rossler_standard/phase_xz.png`
- `reports/plots/rossler_standard/phase_yz.png`
- `reports/plots/rossler_standard/timeseries_xyz.png`
- `reports/logs/rossler_standard/generation_log.txt`
- `reports/logs/rossler_standard/smoke_log.txt`

### 10.3 测试输出

- unit test pass / fail；
- integration smoke pass / fail；
- regression test pass / fail；
- 若失败，报告具体失败字段：维度、样本数、split、manifest、plot、NaN / Inf。

---

## 11. Failure points and debugging strategies

### 11.1 轨线没有进入吸引子

**Symptom**

- 三维相图不像 Rössler 吸引子；
- 坐标范围异常；
- transient 明显。

**Strategy**

- 增加 $T_{\mathrm{burn}}$；
- 检查初值区域；
- 检查参数是否为 $(0.2,0.2,5.7)$；
- 检查积分区间是否把 burn-in 段误保存为正式段。

### 11.2 采样过粗

**Symptom**

- 三维轨线呈折线跳跃；
- $\max_m \Delta_m$ 异常大；
- time series 不平滑。

**Strategy**

- 减小 $\tau$；
- 检查 `saveat` 或采样机制；
- 检查 solver tolerance。

### 11.3 采样过密

**Symptom**

- one-step 任务过于简单；
- 文件体积偏大；
- 相邻样本高度相关。

**Strategy**

- 增大 $\tau$；
- 或在正式配置中保留中等采样步长，另设 high-frequency raw 版本。

### 11.4 维度转置错误

**Symptom**

- 数据形状变成 $(M+1)\times 3$；
- window 逻辑索引错误；
- 下游算法读取异常。

**Strategy**

- 强制检查：
  $$

  \mathbf X\in\mathbb R^{3\times(M+1)},
  \quad
  \mathbf Z\in\mathbb R^{3\times(M+1)}.
  
$$
- 所有保存和读取后都进行维度断言。

### 11.5 split 泄漏

**Symptom**

- 同一条轨线的窗口同时出现在 train 和 test；
- rollout 指标虚高。

**Strategy**

- 先切轨线编号，再生成窗口；
- 在 window manifest 中记录 trajectory id；
- regression test 检查 split disjointness。

### 11.6 manifest 不完整

**Symptom**

- 无法复现实验；
- 不清楚使用了哪个 solver、seed、dt、burn-in。

**Strategy**

- manifest schema 必须固定；
- smoke test 检查关键字段；
- release 前做 manifest completeness check。

### 11.7 三维绘图失败或不可读

**Symptom**

- 图为空；
- 点太密看不清；
- backend 报错。

**Strategy**

- smoke 图使用少量点；
- 正式图可抽样绘制；
- 保存 plot metadata；
- 检查图片文件存在且大小非零。

### 11.8 数值积分不稳定

**Symptom**

- NaN / Inf；
- $\max_m\|\mathbf x_m\|_2$ 爆炸；
- 坐标范围远离典型吸引子。

**Strategy**

- 检查参数符号；
- 检查 $\dot z=b+z(x-c)$ 是否误写；
- 缩小 dt 或提高 solver 精度；
- 检查初值范围是否过大。

---

## 12. Stop before code

到这里为止，本回复只给出 **Rössler 系统的详细代码工程计划书**，没有写 Julia 代码，也没有写伪代码。

下一步需要你单独发出实现请求后，才进入具体文件内容或 Julia 实现。