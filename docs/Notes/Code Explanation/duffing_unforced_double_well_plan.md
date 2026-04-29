# Step 2：Duffing 振子代码工程计划书

## 1. Confirmed task summary

本次任务是在 **ODEs_dataset** 中接入 `v1_core` 系统对象：**无强迫、阻尼、双井、全状态观测的二维自治 Duffing 振子**。

系统为

$$

\dot q = v,
\qquad
\dot v = -\delta v-\alpha q-\beta q^3.

$$

状态为

$$

\mathbf x =
\begin{bmatrix}
q\\
v
\end{bmatrix}
\in\mathbb R^2.

$$

第一版采用全状态观测：

$$

\mathbf z=\mathbf x,
\qquad
d_x=d_z=2.

$$

默认双井参数建议为

$$

\delta=0.2,\qquad \alpha=-1,\qquad \beta=1.

$$

势能为

$$

V(q)=\frac{\alpha}{2}q^2+\frac{\beta}{4}q^4,

$$

总能量为

$$

E(q,v)=\frac12 v^2+V(q),

$$

阻尼系统应满足

$$

\frac{dE}{dt}=-\delta v^2\le 0.

$$

工程上仍遵守 ODEs_dataset 的基本思想：配置负责声明系统与数据生成参数，`src/` 放可复用实现，`experiments/` 放实验入口，`data/` 放生成数据，`reports/` 放人工可读输出。这个分工也与项目目录文档中“配置、源码、数据、实验、报告分离”的原则一致。fileciteturn8file0

---

## 2. Task decomposition

本任务拆成 10 个子任务：

1. 注册 Duffing 系统对象；
2. 编写 Duffing 动力学模块；
3. 编写全状态观测配置；
4. 编写初值泛化 split 配置；
5. 编写 one-step / rollout / statistics 窗口配置；
6. 编写 smoke 生成配置与 smoke 入口；
7. 编写正式生成配置与正式入口；
8. 编写 Duffing 专属诊断；
9. 编写单元、集成、回归测试计划；
10. 更新系统注册文档与任务说明文档。

本次只规划代码工程，不写 Julia 代码。

---

## 3. Sub-task specification

### Sub-task 1：注册 Duffing 系统对象

**Purpose**

把 Duffing 作为 `v1_core` 系统加入 ODEs_dataset 的系统注册表。

**Input**

- 系统名称：`duffing_unforced_double_well`
- 层级：`v1_core`
- 状态维数：`2`
- 参数：$\delta,\alpha,\beta$
- 默认参数：$\delta=0.2,\alpha=-1,\beta=1$

**Output**

- 系统配置文件；
- 系统注册表更新；
- manifest 中可追踪的 `system_id`。

**Dependency**

无，是本任务的入口。

**Mathematical expression**

$$

\mathbf f(q,v;\delta,\alpha,\beta)
=
\begin{bmatrix}
v\\
-\delta v-\alpha q-\beta q^3
\end{bmatrix}.

$$

**Diagnostic checks**

- `state_dim = 2`；
- 参数名完整；
- 默认参数满足 $\delta>0,\alpha<0,\beta>0$；
- 势阱中心为

$$

q^\ast=\pm\sqrt{-\frac{\alpha}{\beta}}.

$$

---

### Sub-task 2：实现 Duffing 动力学模块

**Purpose**

在 `src/dynamics/` 中提供可复用的 Duffing 右端函数、能量函数、平衡点诊断函数。

**Input**

- 状态 $\mathbf x=(q,v)^\top$；
- 参数 $\boldsymbol\mu=(\delta,\alpha,\beta)$。

**Output**

- 状态导数 $\dot{\mathbf x}$；
- 能量 $E(q,v)$；
- 平衡点位置；
- 局部 Jacobian 诊断量。

**Dependency**

依赖 Sub-task 1 的参数约定。

**Mathematical expression**

$$

\dot q=v,

$$

$$

\dot v=-\delta v-\alpha q-\beta q^3.

$$

Jacobian：

$$

D\mathbf f(q,v)
=
\begin{bmatrix}
0 & 1\\
-\alpha-3\beta q^2 & -\delta
\end{bmatrix}.

$$

**Diagnostic checks**

- 输入状态长度必须为 2；
- 输出导数长度必须为 2；
- 对默认参数，平衡点应为 $(-1,0),(0,0),(1,0)$；
- 阻尼能量导数应满足

$$

\dot E=-\delta v^2.

$$

---

### Sub-task 3：全状态观测配置

**Purpose**

定义最简单观测链：

$$

\mathbf z=\mathbf x.

$$

**Input**

- 原始状态矩阵

$$

\mathbf X^{(r)}\in\mathbb R^{2\times(M+1)}.

$$

**Output**

- 观测矩阵

$$

\mathbf Z^{(r)}\in\mathbb R^{2\times(M+1)}.

$$

**Dependency**

依赖动力系统轨线生成。

**Mathematical expression**

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.

$$

**Diagnostic checks**

- `size(Z) = size(X)`；
- `d_z = d_x = 2`；
- 不引入噪声；
- 不做标准化，除非后续单独增加 normalized observation 版本。

---

### Sub-task 4：初值泛化 split 配置

**Purpose**

先实现 `Split-I`：参数固定，训练 / 验证 / 测试使用不同初值轨线。

**Input**

完整轨线集合：

$$

\{\mathbf Z^{(r)}\}_{r=1}^R.

$$

**Output**

轨线编号集合：

$$

\mathcal R_{\mathrm{train}},
\quad
\mathcal R_{\mathrm{val}},
\quad
\mathcal R_{\mathrm{test}}.

$$

**Dependency**

依赖正式轨线生成。

**Mathematical expression**

默认比例：

$$

70\%/15\%/15\%.

$$

切分单位为整条轨线：

$$

r\in\mathcal R_{\mathrm{train}}
\quad\text{or}\quad
r\in\mathcal R_{\mathrm{val}}
\quad\text{or}\quad
r\in\mathcal R_{\mathrm{test}}.

$$

**Diagnostic checks**

- train / val / test 轨线编号互不重叠；
- 三个集合的轨线总数等于 $R$；
- 不允许按窗口随机打散；
- 左井 / 右井 / 势垒附近样本在三个 split 中不要严重失衡。

---

### Sub-task 5：窗口配置

**Purpose**

为后续算法统一派生 one-step、rollout 和 statistics 窗口。

**Input**

每条观测轨线：

$$

\mathbf Z^{(r)}
=
[\mathbf z^{(r)}_1,\dots,\mathbf z^{(r)}_{M+1}].

$$

**Output**

- one-step 样本：

$$

(\mathbf z_m,\mathbf z_{m+1}).

$$

- rollout 窗口：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

- statistics 窗口：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1}).

$$

**Dependency**

依赖 split 后的轨线集合。

**Diagnostic checks**

- one-step 样本数为每条轨线 $M$；
- rollout 起点数为每条轨线 $M-L+1$；
- 窗口不能跨轨线；
- train / val / test 内部独立派生窗口。

---

### Sub-task 6：smoke 生成配置与入口

**Purpose**

快速验证 Duffing 系统的方程、积分、观测、存盘、诊断和绘图流程。

**Input**

少量手工初值，例如覆盖：

- 左势阱附近；
- 右势阱附近；
- 原点势垒附近；
- 高能跨势阱附近。

建议 smoke 使用：

$$

R_{\mathrm{smoke}}=6\sim 8,
\qquad
T_{\mathrm{smoke}}\approx 10\sim 20,
\qquad
\tau_{\mathrm{smoke}}\approx 0.02.

$$

**Output**

- smoke raw trajectory；
- smoke processed trajectory；
- smoke manifest；
- smoke 诊断图；
- smoke 日志。

**Dependency**

依赖 Sub-task 1–5。

**Diagnostic checks**

- 是否生成所有轨线；
- 每条轨线矩阵维度是否为 $2\times(M+1)$；
- 能量是否基本单调非增；
- 左右势阱是否都被访问；
- 相图是否符合双井阻尼结构。

---

### Sub-task 7：正式生成配置与入口

**Purpose**

生成可作为 `v1_core` 正式 benchmark 候选的数据。

**Input**

随机初值区域建议：

$$

q_0\in[-2,2],
\qquad
v_0\in[-2,2].

$$

默认参数：

$$

\delta=0.2,
\qquad
\alpha=-1,
\qquad
\beta=1.

$$

建议正式 small 级别先采用：

$$

R_{\mathrm{small}}=64\sim128,
\qquad
T_{\mathrm{small}}\approx 20\sim30,
\qquad
\tau_{\mathrm{small}}\approx 0.02.

$$

**Output**

- `data/raw/v1_core/duffing_unforced_double_well/...`
- `data/processed/v1_core/duffing_unforced_double_well/...`
- `data/manifests/v1_core/duffing_unforced_double_well/...`
- split 文件；
- window 索引或派生样本；
- 正式诊断报告。

**Dependency**

依赖 smoke 通过。

**Diagnostic checks**

- 轨线数量正确；
- 每条轨线长度一致；
- 初值分布覆盖完整区域；
- 最终落入左右势阱的比例不要极端失衡；
- 能量异常增长次数应接近 0；
- manifest 中记录 solver、容差、参数、seed、dt、tspan。

---

### Sub-task 8：Duffing 专属诊断

**Purpose**

为 Duffing 数据质量提供专属检查，而不是只看轨线是否成功保存。

**Input**

$$

\mathbf X^{(r)},\quad \mathbf Z^{(r)},\quad \boldsymbol\mu.

$$

**Output**

- 能量曲线；
- 相图；
- 初值散点图；
- 终点势阱分类表；
- 能量单调性检查表；
- 基础统计表。

**Dependency**

依赖 raw / processed 数据生成。

**Relevant diagnostics**

每条轨线能量：

$$

E_m^{(r)}
=
\frac12(v_m^{(r)})^2
+
\frac{\alpha}{2}(q_m^{(r)})^2
+
\frac{\beta}{4}(q_m^{(r)})^4.

$$

能量增量：

$$

\Delta E_m^{(r)}
=
E_{m+1}^{(r)}-E_m^{(r)}.

$$

终点势阱标签：

$$

\mathrm{well}^{(r)}
=
\begin{cases}
\mathrm{left}, & q_{M+1}^{(r)}<0,\\
\mathrm{right}, & q_{M+1}^{(r)}>0,\\
\mathrm{barrier}, & |q_{M+1}^{(r)}|\approx 0.
\end{cases}

$$

**Diagnostic checks**

- `max_positive_energy_jump`；
- `mean_energy_drop`；
- `left_well_count`；
- `right_well_count`；
- `barrier_near_count`；
- `q_min, q_max, v_min, v_max`；
- 是否出现 NaN / Inf。

---

### Sub-task 9：测试计划

**Purpose**

保证 Duffing 接入不会破坏已有数据协议。

**Input**

- Duffing 动力学模块；
- smoke 配置；
- smoke 生成结果。

**Output**

- 单元测试；
- 集成测试；
- 回归测试参考输出。

**Dependency**

依赖 Sub-task 1–8。

**Test checks**

单元测试检查：

$$

\mathbf f(q,v)\in\mathbb R^2.

$$

能量函数输出标量。

平衡点满足：

$$

\mathbf f(q^\ast,0)\approx 0.

$$

集成测试检查：

$$

\mathbf X\in\mathbb R^{2\times(M+1)},
\qquad
\mathbf Z\in\mathbb R^{2\times(M+1)}.

$$

回归测试检查：

- 固定 seed 下轨线数量不变；
- split 数量不变；
- 窗口数量不变；
- 核心诊断统计在合理容差内稳定。

---

### Sub-task 10：文档与注册更新

**Purpose**

让未来重复试验时可以直接查 registry，而不是重新设计 Duffing 任务。

**Input**

本次系统定义、配置路径、生成脚本、输出路径、诊断结论。

**Output**

- 系统注册说明；
- 本次任务代码计划书；
- 任务完成后的文件说明；
- smoke 与正式数据说明；
- 后续扩展备注。

**Dependency**

依赖所有子任务完成。

**Diagnostic checks**

- 文档中 `system_id` 与配置一致；
- 文档中路径与真实文件一致；
- 参数、初值范围、采样步长、轨线长度明确；
- 明确说明第一版不包含受迫 Duffing。

---

## 4. Directory and file plan

### 4.1 文档文件

| 文件路径 | 作用 |
|---|---|
| `docs/notes/mathematical explanation/duffing_unforced_double_well_math.md` | 保存本次数学说明书 |
| `docs/notes/code explanation/duffing_unforced_double_well_code_plan.md` | 保存本次代码工程计划书 |
| `docs/notes/file explanation/duffing_unforced_double_well_files.md` | 任务完成后说明新增文件、运行方式、输出解释 |
| `docs/spec/system_registry.md` | 更新 `duffing_unforced_double_well` 的系统注册记录 |
| `docs/spec/task_registry.md` | 更新 Duffing 支持的 one-step、rollout、statistics 任务 |
| `docs/spec/split_registry.md` | 更新 Duffing 的 `Split-I` 初值泛化切分 |
| `docs/spec/metric_registry.md` | 记录 Duffing 专属能量诊断与通用预测指标 |

---

### 4.2 配置文件

| 文件路径 | 作用 |
|---|---|
| `configs/systems/duffing_unforced_double_well_smoke.json` | smoke 系统参数、手工初值、短时间积分设置 |
| `configs/systems/duffing_unforced_double_well_small.json` | 正式 small 数据集系统参数与随机初值范围 |
| `configs/observations/duffing_full_state_clean.json` | 全状态、无噪声、无标准化观测配置 |
| `configs/splits/duffing_split_i_seed001.json` | 初值泛化 split 配置 |
| `configs/windows/duffing_one_step.json` | one-step 样本窗口配置 |
| `configs/windows/duffing_rollout_L50.json` | 短中期 rollout 窗口配置 |
| `configs/windows/duffing_statistics_L200.json` | 统计窗口配置 |
| `configs/tasks/duffing_one_step_forecast.json` | 一步预测任务配置 |
| `configs/tasks/duffing_multi_step_rollout.json` | 多步 rollout 任务配置 |
| `configs/tasks/duffing_long_time_statistics.json` | 长期统计任务配置 |
| `configs/benchmarks/duffing_v1_core_small.json` | Duffing small benchmark 组合配置 |
| `configs/releases/duffing_v1_core_draft.json` | 当前 Duffing 数据发布草案 |

---

### 4.3 源码文件

| 文件路径 | 作用 |
|---|---|
| `src/dynamics/duffing.jl` | Duffing 右端、能量、平衡点、Jacobian 诊断 |
| `src/observations/full_state.jl` | 若项目已有则复用；否则提供全状态观测通用组件 |
| `src/generators/generate_ode_trajectories.jl` | 若项目已有则复用；负责从系统配置生成 raw 轨线 |
| `src/generators/apply_observation_chain.jl` | 若项目已有则复用；负责从 raw 生成 processed |
| `src/datasets/trajectory_objects.jl` | 若项目已有则复用；定义 raw / observed trajectory 数据对象 |
| `src/splits/trajectory_split.jl` | 若项目已有则复用；轨线级 split |
| `src/windows/window_builders.jl` | 若项目已有则复用；one-step / rollout / statistics 窗口 |
| `src/diagnostics/duffing_diagnostics.jl` | Duffing 能量、势阱、相图、统计诊断 |
| `src/manifests/manifest_writer.jl` | 若项目已有则复用；写入生成元数据 |
| `src/io/path_utils.jl` | 若项目已有则复用；统一路径管理 |
| `src/registries/system_registry.jl` | 若项目已有则复用；注册 Duffing 系统对象 |

如果上述通用文件已经存在，本任务只需要扩展 Duffing 相关对象，不重复创建通用基础设施。

---

### 4.4 实验入口文件

| 文件路径 | 作用 |
|---|---|
| `experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl` | 最小 smoke 数据生成与诊断入口 |
| `experiments/baseline_forecasting/run_duffing_v1_core_small_generation.jl` | 正式 small 数据生成入口 |
| `experiments/baseline_forecasting/check_duffing_v1_core_small_dataset.jl` | 正式数据质量检查入口 |

这里虽然放在 `baseline_forecasting/` 下，但本阶段仍是数据生成和检查，不做学习算法。

---

### 4.5 数据输出

| 文件路径 | 作用 |
|---|---|
| `data/raw/v1_core/duffing_unforced_double_well/smoke/` | smoke 原始状态轨线 |
| `data/processed/v1_core/duffing_unforced_double_well/smoke/full_state_clean/` | smoke 全状态观测轨线 |
| `data/manifests/v1_core/duffing_unforced_double_well/smoke/` | smoke manifest |
| `data/raw/v1_core/duffing_unforced_double_well/small/` | 正式 small 原始状态轨线 |
| `data/processed/v1_core/duffing_unforced_double_well/small/full_state_clean/` | 正式 small 观测轨线 |
| `data/manifests/v1_core/duffing_unforced_double_well/small/` | 正式 small manifest |
| `data/releases/v1_core/duffing_unforced_double_well/` | 后续冻结发布索引 |

---

### 4.6 报告输出

| 文件路径 | 作用 |
|---|---|
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/smoke_phase_portrait.png` | smoke 相图 |
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/smoke_energy_curves.png` | smoke 能量曲线 |
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/smoke_initial_conditions.png` | smoke 初值分布 |
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_phase_portrait_samples.png` | 正式 small 抽样相图 |
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_energy_diagnostics.png` | 正式 small 能量诊断 |
| `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_final_well_distribution.png` | 最终势阱分布图 |
| `reports/v1_core/duffing_unforced_double_well_smoke/tables/smoke_diagnostics.csv` | smoke 数值诊断表 |
| `reports/v1_core/duffing_unforced_double_well_smoke/tables/small_dataset_summary.csv` | 正式数据规模与统计摘要 |
| `reports/v1_core/duffing_unforced_double_well_smoke/tables/small_energy_checks.csv` | 能量单调性检查表 |
| `reports/v1_core/duffing_unforced_double_well_smoke/logs/smoke_generation.log` | smoke 运行日志 |
| `reports/v1_core/duffing_unforced_double_well_smoke/logs/small_generation.log` | 正式生成日志 |
| `reports/v1_core/duffing_unforced_double_well_smoke/logs/small_dataset_check.log` | 正式检查日志 |

---

### 4.7 测试文件

| 文件路径 | 作用 |
|---|---|
| `test/unit/test_duffing_dynamics.jl` | Duffing 右端、能量、平衡点单元测试 |
| `test/unit/test_duffing_observation.jl` | 全状态观测维度测试 |
| `test/integration/test_duffing_smoke_generation.jl` | smoke 端到端生成测试 |
| `test/regression/test_duffing_small_regression.jl` | 固定 seed 下的数据规模与诊断回归测试 |
| `test/reference_outputs/duffing_smoke_summary.json` | smoke 回归参考摘要 |
| `test/reference_outputs/duffing_small_summary.json` | small 回归参考摘要 |

---

## 5. Module / component responsibilities

### `src/dynamics/`

负责 Duffing 的数学系统本体：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\boldsymbol\mu).

$$

只处理状态导数、能量、平衡点、Jacobian，不处理存盘、绘图、split、window。

### `src/observations/`

负责

$$

\mathbf x\mapsto \mathbf z.

$$

本任务只需要全状态观测：

$$

\mathbf z=\mathbf x.

$$

### `src/generators/`

负责把系统配置、初值、参数、时间设置转化为轨线数据：

$$

(\mathbf f,\boldsymbol\mu,\mathbf x_0,\tau)
\mapsto
\mathbf X.

$$

### `src/datasets/`

负责统一数据对象协议：

$$

\mathbf X\in\mathbb R^{2\times(M+1)},
\qquad
\mathbf Z\in\mathbb R^{2\times(M+1)}.

$$

### `src/splits/`

负责轨线级 train / val / test 切分。

### `src/windows/`

负责从 split 内部派生 one-step、rollout、statistics 窗口。

### `src/diagnostics/`

负责 Duffing 专属检查：

- 能量；
- 势阱归属；
- 相图；
- 轨线统计；
- NaN / Inf；
- 维度一致性。

### `src/manifests/`

负责记录：

- `system_id`；
- 参数；
- 初值采样；
- solver；
- 容差；
- dt；
- tspan；
- seed；
- 数据文件路径；
- split 文件路径；
- window 配置路径。

### `experiments/`

只作为入口，不堆积底层函数。

### `reports/`

保存给人看的图、表、日志。

### `test/`

保存自动化一致性检查。

---

## 6. Planned `##` sections

### `src/dynamics/duffing.jl`

计划 `##` section：

1. `## Duffing system identity and parameter convention`
2. `## State dimension and parameter validation`
3. `## Duffing vector field for unforced damped double-well system`
4. `## Duffing potential energy and total energy`
5. `## Equilibrium points for double-well parameter regime`
6. `## Local Jacobian and linearization diagnostics`
7. `## Basic numerical sanity checks for Duffing states`

---

### `src/diagnostics/duffing_diagnostics.jl`

计划 `##` section：

1. `## Load Duffing trajectory objects for diagnostics`
2. `## Compute trajectory-wise energy sequences`
3. `## Check monotone energy decay under damping`
4. `## Classify final well membership`
5. `## Summarize state ranges and trajectory statistics`
6. `## Prepare phase portrait diagnostic data`
7. `## Prepare energy diagnostic tables`
8. `## Export Duffing diagnostic summaries`

---

### `experiments/smoke_tests/run_duffing_unforced_double_well_smoke.jl`

计划 `##` section：

1. `## Load smoke configuration for Duffing double-well system`
2. `## Initialize reproducible random seed and output paths`
3. `## Build smoke initial-condition set`
4. `## Generate raw Duffing state trajectories`
5. `## Apply full-state clean observation`
6. `## Build smoke split and window summaries`
7. `## Run Duffing smoke diagnostics`
8. `## Save smoke raw data, processed data, manifest, plots, and tables`
9. `## Print smoke completion summary`

---

### `experiments/baseline_forecasting/run_duffing_v1_core_small_generation.jl`

计划 `##` section：

1. `## Load v1-core small Duffing benchmark configuration`
2. `## Validate system, observation, split, window, and task configs`
3. `## Sample parameter and initial-condition instances`
4. `## Generate raw trajectories for all sampled instances`
5. `## Apply full-state clean observation chain`
6. `## Create trajectory-level Split-I partitions`
7. `## Derive one-step, rollout, and statistics window metadata`
8. `## Run full Duffing dataset diagnostics`
9. `## Save raw, processed, split, window, and manifest outputs`
10. `## Save human-readable plots, tables, and logs`

---

### `experiments/baseline_forecasting/check_duffing_v1_core_small_dataset.jl`

计划 `##` section：

1. `## Load generated Duffing small dataset and manifest`
2. `## Verify raw and processed trajectory dimensions`
3. `## Verify trajectory-level split consistency`
4. `## Verify window counts and index legality`
5. `## Recompute energy diagnostics from saved data`
6. `## Recompute final well distribution`
7. `## Compare dataset summary against expected configuration`
8. `## Save dataset check report`

---

### `test/unit/test_duffing_dynamics.jl`

计划 `##` section：

1. `## Test Duffing vector field output dimension`
2. `## Test default double-well parameter validation`
3. `## Test equilibrium residuals`
4. `## Test energy scalar output`
5. `## Test local Jacobian dimension`

---

### `test/integration/test_duffing_smoke_generation.jl`

计划 `##` section：

1. `## Run Duffing smoke generation in isolated test mode`
2. `## Check generated raw trajectory objects`
3. `## Check generated observed trajectory objects`
4. `## Check smoke manifest fields`
5. `## Check diagnostic summary fields`

---

### `test/regression/test_duffing_small_regression.jl`

计划 `##` section：

1. `## Load Duffing small reference summary`
2. `## Regenerate or reload fixed-seed small summary`
3. `## Compare trajectory counts and dimensions`
4. `## Compare split and window counts`
5. `## Compare energy diagnostic tolerances`
6. `## Compare final well distribution tolerance`

---

## 7. Data flow and dimensions

### 7.1 系统输入

每条轨线有：

$$

\boldsymbol\mu^{(r)}=(\delta,\alpha,\beta),

$$

$$

\mathbf x_0^{(r)}
=
\begin{bmatrix}
q_0^{(r)}\\
v_0^{(r)}
\end{bmatrix}
\in\mathbb R^2.

$$

第一版正式数据中参数固定：

$$

\boldsymbol\mu^{(r)}=(0.2,-1,1).

$$

初值变化：

$$

q_0^{(r)}\in[-2,2],
\qquad
v_0^{(r)}\in[-2,2].

$$

---

### 7.2 Raw trajectory

积分后得到：

$$

\mathbf X^{(r)}
=
\begin{bmatrix}
\mathbf x_1^{(r)}
&
\cdots
&
\mathbf x_{M+1}^{(r)}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

其中：

$$

\mathbf x_m^{(r)}
=
\begin{bmatrix}
q_m^{(r)}\\
v_m^{(r)}
\end{bmatrix}.

$$

---

### 7.3 Observed trajectory

全状态观测：

$$

\mathbf Z^{(r)}=\mathbf X^{(r)}.

$$

所以：

$$

\mathbf Z^{(r)}\in\mathbb R^{2\times(M+1)}.

$$

---

### 7.4 Split

轨线级划分：

$$

\{1,\dots,R\}
=
\mathcal R_{\mathrm{train}}
\cup
\mathcal R_{\mathrm{val}}
\cup
\mathcal R_{\mathrm{test}}.

$$

三个集合两两不交。

---

### 7.5 One-step samples

对每条轨线：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
m=1,\dots,M.

$$

每个样本维度：

$$

\mathbf z_m\in\mathbb R^2,
\qquad
\mathbf z_{m+1}\in\mathbb R^2.

$$

---

### 7.6 Rollout windows

窗口长度 $L$ 时：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

每个窗口可视为矩阵：

$$

\mathbf W_s^{(r)}
=
\begin{bmatrix}
\mathbf z_s^{(r)}
&
\mathbf z_{s+1}^{(r)}
&
\cdots
&
\mathbf z_{s+L}^{(r)}
\end{bmatrix}
\in\mathbb R^{2\times(L+1)}.

$$

---

### 7.7 Diagnostics data

能量序列：

$$

\mathbf e^{(r)}
=
(E_1^{(r)},\dots,E_{M+1}^{(r)})
\in\mathbb R^{M+1}.

$$

能量增量：

$$

\Delta\mathbf e^{(r)}
=
(E_2^{(r)}-E_1^{(r)},\dots,E_{M+1}^{(r)}-E_M^{(r)})
\in\mathbb R^M.

$$

终点势阱标签：

$$

\ell^{(r)}\in\{\text{left},\text{right},\text{near-barrier}\}.

$$

---

## 8. Package and documentation plan

### `DifferentialEquations.jl`

**Why needed**

用于 ODE 数值积分。

**Expected functionality**

- 定义 ODE 问题；
- 设置时间区间；
- 设置参数；
- 选择求解器；
- 在固定采样时间点保存解；
- 控制 `abstol`、`reltol`。

**Documentation to check**

- ODE problem construction；
- solver selection for non-stiff low-dimensional ODE；
- saving at fixed time grid；
- reproducibility with deterministic solve settings。

---

### `LinearAlgebra`

**Why needed**

用于 Jacobian、特征值、基础矩阵诊断。

**Expected functionality**

- 局部线性化矩阵；
- 平衡点附近特征值检查；
- 范数计算。

**Documentation to check**

Julia 标准库接口即可，但仍需确认当前项目中的导入风格。

---

### `Random`

**Why needed**

用于初值采样与 split 随机种子控制。

**Expected functionality**

- 固定 seed；
- 生成可复现初值；
- shuffle 轨线编号。

**Documentation to check**

标准库接口即可，重点是项目内是否已有统一 seed 工具。

---

### `Statistics`

**Why needed**

用于状态范围、均值、方差、能量统计。

**Expected functionality**

- 均值；
- 方差；
- 最小最大摘要；
- 诊断表统计。

---

### `JSON3.jl` 或 `TOML`

**Why needed**

用于读取声明式配置与写入 manifest。

**Expected functionality**

- 配置读取；
- manifest 写出；
- 保持数值字段和字符串字段可读。

**Documentation to check**

确认项目最终使用 JSON 还是 TOML，不混用主要配置格式。

---

### `JLD2.jl` 或 `HDF5.jl`

**Why needed**

用于保存较大矩阵数据。

**Expected functionality**

- 保存 raw trajectory；
- 保存 processed trajectory；
- 保存 split / window metadata；
- 读取数据用于测试和诊断。

**Documentation to check**

- 多数组保存方式；
- 字典或结构化对象保存方式；
- 跨 Julia 版本读取稳定性；
- 大批量轨线存储效率。

---

### `CSV.jl` 与 `DataFrames.jl`

**Why needed**

用于导出人工可读的诊断表。

**Expected functionality**

- 写入 `reports/v1_core/duffing_unforced_double_well_smoke/tables/*.csv`；
- 读取回归参考摘要；
- 整理 dataset summary。

**Documentation to check**

确认表格写入方式和项目依赖是否已有。

---

### `Plots.jl` 或 `Makie.jl`

**Why needed**

用于相图、能量曲线、初值分布、最终势阱分布图。

**Expected functionality**

- 2D 相图；
- 多轨线能量曲线；
- scatter 初值图；
- bar chart 势阱分布图。

**Documentation to check**

项目若已有统一绘图后端，优先服从项目规范，不在 Duffing 任务中单独引入新的绘图库。

---

## 9. Debugging and inspection plan

### 9.1 维度检查

每次生成后打印或保存：

$$

d_x=2,\qquad d_z=2.

$$

每条轨线：

$$

\mathrm{size}(\mathbf X^{(r)})=(2,M+1),

$$

$$

\mathrm{size}(\mathbf Z^{(r)})=(2,M+1).

$$

---

### 9.2 参数检查

保存并检查：

$$

\delta>0,\qquad \alpha<0,\qquad \beta>0.

$$

默认平衡点：

$$

(-1,0),\quad (0,0),\quad (1,0).

$$

---

### 9.3 数值积分检查

记录：

- solver 名称；
- `abstol`；
- `reltol`；
- dt；
- tspan；
- 保存点数量；
- 是否出现 solver warning；
- 是否出现 NaN / Inf。

---

### 9.4 能量检查

对每条轨线保存：

- 初始能量；
- 终止能量；
- 最大能量；
- 最小能量；
- 最大正能量跳跃；
- 正能量跳跃次数；
- 平均能量下降。

理论上：

$$

E_{m+1}-E_m\le 0

$$

应近似成立。允许非常小的数值容差，但不允许系统性增长。

---

### 9.5 势阱覆盖检查

统计：

- `left_well_count`；
- `right_well_count`；
- `near_barrier_count`；
- train / val / test 中每类比例。

如果某个 split 几乎只包含一个势阱，应调整初值采样或 stratified split 策略。

---

### 9.6 图像检查

必须保存：

1. 初值散点图；
2. 相图；
3. 能量曲线；
4. 最终势阱分布图；
5. 抽样轨线的 $q(t)$、$v(t)$ 曲线。

---

### 9.7 split 和 window 检查

保存：

- train 轨线数；
- val 轨线数；
- test 轨线数；
- one-step 样本数；
- rollout window 数；
- statistics window 数。

检查：

$$

R_{\mathrm{train}}+R_{\mathrm{val}}+R_{\mathrm{test}}=R.

$$

窗口起点必须满足：

$$

1\le s\le M-L+1.

$$

---

## 10. Expected outputs

### Smoke 输出

- `data/raw/v1_core/duffing_unforced_double_well/smoke/`
- `data/processed/v1_core/duffing_unforced_double_well/smoke/full_state_clean/`
- `data/manifests/v1_core/duffing_unforced_double_well/smoke/`
- `reports/v1_core/duffing_unforced_double_well_smoke/plots/smoke_phase_portrait.png`
- `reports/v1_core/duffing_unforced_double_well_smoke/plots/smoke_energy_curves.png`
- `reports/v1_core/duffing_unforced_double_well_smoke/tables/smoke_diagnostics.csv`
- `reports/v1_core/duffing_unforced_double_well_smoke/logs/smoke_generation.log`

### 正式 small 输出

- `data/raw/v1_core/duffing_unforced_double_well/small/`
- `data/processed/v1_core/duffing_unforced_double_well/small/full_state_clean/`
- `data/manifests/v1_core/duffing_unforced_double_well/small/`
- `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_phase_portrait_samples.png`
- `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_energy_diagnostics.png`
- `reports/v1_core/duffing_unforced_double_well_smoke/plots/small_final_well_distribution.png`
- `reports/v1_core/duffing_unforced_double_well_smoke/tables/small_dataset_summary.csv`
- `reports/v1_core/duffing_unforced_double_well_smoke/tables/small_energy_checks.csv`
- `reports/v1_core/duffing_unforced_double_well_smoke/logs/small_generation.log`
- `reports/v1_core/duffing_unforced_double_well_smoke/logs/small_dataset_check.log`

### 测试输出

- `test/reference_outputs/duffing_smoke_summary.json`
- `test/reference_outputs/duffing_small_summary.json`

---

## 11. Failure points and debugging strategies

### Failure 1：能量明显增长

**Likely cause**

- 时间步长太大；
- 求解器容差太松；
- 能量公式写错；
- 参数符号写错。

**Strategy**

先用单条轨线检查：

$$

E_m=\frac12v_m^2+\frac{\alpha}{2}q_m^2+\frac{\beta}{4}q_m^4.

$$

再检查：

$$

\dot E=-\delta v^2.

$$

若公式正确，则减小 $\tau$ 或收紧 solver tolerance。

---

### Failure 2：轨线全部落入同一势阱

**Likely cause**

- 初值采样偏置；
- 轨线数太少；
- split 随机后类别失衡。

**Strategy**

先画初值散点图，再统计终点 $q(T)$ 的符号。必要时对初值区域分层采样：左井、右井、势垒附近分别采样。

---

### Failure 3：数据长期全接近平衡点

**Likely cause**

- 轨线太长；
- 阻尼太大；
- 初值能量太低。

**Strategy**

缩短 $T$，或降低 $\delta$，或提高初值能量范围。正式 small 数据中不要让绝大多数时间点都集中在 $(\pm1,0)$ 附近。

---

### Failure 4：轨线数、窗口数不符合预期

**Likely cause**

- $M$、$L$、保存点数量定义不一致；
- 把 $M$ 当成快照数而不是步数；
- rollout 窗口边界多算或少算。

**Strategy**

统一约定：

$$

M+1=\text{快照数},
\qquad
M=\text{one-step 对数}.

$$

rollout 起点数为：

$$

M-L+1.

$$

---

### Failure 5：raw 与 processed 数据混淆

**Likely cause**

全状态观测下 $\mathbf Z=\mathbf X$，容易误以为 raw 与 processed 可以合并。

**Strategy**

即使数值相同，也必须分开保存：

- raw 表示积分得到的状态；
- processed 表示观测链后的算法输入。

这样后续加入部分观测、噪声观测、标准化观测时不会破坏协议。

---

### Failure 6：配置和源码参数不一致

**Likely cause**

参数被硬编码在源码中。

**Strategy**

所有实验参数必须从 `configs/` 读取；`src/dynamics/duffing.jl` 只表达数学系统，不决定实验规模、路径、seed 或 split。

---

### Failure 7：测试依赖大规模正式数据

**Likely cause**

回归测试直接读取 large / small 数据，导致测试慢。

**Strategy**

单元测试只测函数；集成测试只跑 smoke；回归测试只比较小型 summary，不重复生成大数据。

---

## 12. Stop before code

到这里为止，本次 Duffing 振子的 **代码工程计划书** 已完成。

我没有写 Julia 代码，也没有给出伪代码。下一步只有在你明确要求“开始实现”或“写代码”后，才进入具体 Julia 文件编写。