# Step 2：Lotka–Volterra 代码工程计划书

## 1. Confirmed task summary

本次任务是在 **ODEs_dataset** 中新增 `v1_core` 系统对象：

$$

\texttt{lotka\_volterra}

$$

采用设定：

$$

\dot x = \alpha x-\beta xy,\qquad
\dot y=\delta xy-\gamma y

$$

其中：

$$

\mathbf x=(x,y)^\top\in\mathbb R^2_{>0},
\qquad
\boldsymbol\mu=(\alpha,\beta,\gamma,\delta),
\qquad
\alpha,\beta,\gamma,\delta>0.

$$

本任务固定为：

- 标准二维捕食者–猎物形式；
- 自治 ODE；
- 无控制输入；
- 全状态观测：

$$

\mathbf z_m=\mathbf x_m;

$$

- smoke 版本：单组参数、少量正初值、小规模轨线；
- 正式版本：固定一组参数，通过多组正初值覆盖不同闭合轨道族；
- 暂不加入参数泛化；
- 守恒量作为核心数据质量诊断：

$$

H(x,y)=\delta x-\gamma\log x+\beta y-\alpha\log y.

$$

目录映射遵循你上传的工程目录蓝图：配置放在 `configs/`，可复用源码放在 `src/`，实验入口放在 `experiments/`，人工可读结果放在 `reports/`，测试放在 `test/`。fileciteturn8file0

---

## 2. Task decomposition

本任务分解为 12 个子任务：

1. 注册 Lotka–Volterra 系统数学对象；
2. 定义系统参数、默认参数、状态维数与正初值范围；
3. 实现右端函数、正平衡点、Jacobian、守恒量诊断；
4. 定义 smoke 配置；
5. 定义正式轨道族配置；
6. 定义全状态无噪声观测配置；
7. 定义 Split-I 初值泛化切分；
8. 定义 one-step、rollout、statistics 三类窗口；
9. 生成 raw state trajectories；
10. 生成 processed observed trajectories；
11. 计算并保存守恒量漂移、正性、尺度、相图等诊断；
12. 编写 unit / integration / regression 测试。

---

## 3. Sub-task specification

### 3.1 系统动力学定义

**目的**  
在 `src/dynamics/` 中定义 Lotka–Volterra 系统本体。

**输入**

$$

\mathbf x=(x,y)^\top,\qquad
\boldsymbol\mu=(\alpha,\beta,\gamma,\delta).

$$

**输出**

$$

\mathbf f(\mathbf x;\boldsymbol\mu)
=
\begin{bmatrix}
\alpha x-\beta xy\\
\delta xy-\gamma y
\end{bmatrix}.

$$

**依赖**  
无前置依赖，是本任务的基础模块。

**诊断检查**

- `state_dim = 2`；
- 参数数量为 4；
- 参数全部为正；
- 初值满足 $x_0>0,\ y_0>0$；
- 右端返回向量维度为 $2$。

---

### 3.2 守恒量与几何诊断

**目的**  
为数据生成质量提供系统专属诊断。

**输入**

$$

x_m,\ y_m,\ \alpha,\beta,\gamma,\delta.

$$

**输出**

$$

H_m=H(x_m,y_m).

$$

以及漂移量：

$$

\Delta H_m=H_m-H_1,

$$

相对漂移：

$$

\epsilon_H
=
\frac{\max_m |H_m-H_1|}
{|H_1|+\varepsilon}.

$$

**依赖**  
依赖系统状态轨线 $\mathbf X$。

**诊断检查**

- 所有 $x_m,y_m$ 必须为正；
- `H` 不应出现 `NaN` 或 `Inf`；
- smoke 数据中 $\epsilon_H$ 应在容差内；
- 正式轨道族中应分别记录每条轨线的 $\epsilon_H^{(q)}$。

---

### 3.3 smoke 数据配置

**目的**  
快速检查系统右端、积分器、观测链、保存流程是否正确。

**输入**

- 单组参数，例如：

$$

\alpha=1.5,\quad \beta=1.0,\quad \gamma=3.0,\quad \delta=1.0.

$$

- 少量正初值；
- 较短时间区间；
- 较小轨线数 $R_{\text{smoke}}$。

**输出**

$$

\{\mathbf X^{(q)}\}_{q=1}^{R_{\text{smoke}}},
\qquad
\{\mathbf Z^{(q)}\}_{q=1}^{R_{\text{smoke}}}.

$$

**依赖**  
依赖系统动力学模块、全状态观测模块、IO 模块。

**诊断检查**

- 轨线矩阵尺寸：

$$

\mathbf X^{(q)},\mathbf Z^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

- 正性保持；
- 守恒量漂移；
- 相图是否为围绕正平衡点的闭合轨道；
- 时间序列是否存在捕食者–猎物相位滞后。

---

### 3.4 正式轨道族配置

**目的**  
生成固定参数下的多轨道族数据，用于测试初值泛化和不同守恒量能级上的模型表现。

**输入**

- 固定参数 $\boldsymbol\mu$；
- 多个正初值：

$$

\mathbf x_0^{(q)}=(x_0^{(q)},y_0^{(q)})^\top,
\qquad q=1,\dots,R.

$$

**输出**

多条闭合轨道族：

$$

\left\{
\mathbf X^{(q)}
\right\}_{q=1}^R,
\qquad
\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

**依赖**  
依赖 smoke 流程通过后再启用。

**诊断检查**

- 不同轨线的初始守恒量 $H(\mathbf x_0^{(q)})$ 应有区分度；
- 所有轨线保持在正象限；
- 不同轨线覆盖不同振幅；
- 不应过度靠近 $x=0$ 或 $y=0$。

---

### 3.5 全状态观测

**目的**  
实现第一版最简单观测链：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.

$$

**输入**

$$

\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

**输出**

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

**依赖**  
依赖 raw trajectory。

**诊断检查**

- `state_dim = output_dim = 2`；
- $\mathbf Z$ 与 $\mathbf X$ 尺寸完全一致；
- clean full-state 模式下二者数值一致；
- processed 数据中记录 observation metadata。

---

### 3.6 Split-I 初值泛化

**目的**  
在固定参数下，按整条轨线划分 train / val / test。

**输入**

轨线编号集合：

$$

\mathcal R=\{1,\dots,R\}.

$$

**输出**

$$

\mathcal R_{\text{train}},
\quad
\mathcal R_{\text{val}},
\quad
\mathcal R_{\text{test}}.

$$

**依赖**  
依赖正式轨道族生成完成。

**诊断检查**

- 三个集合互不重叠；
- 并集等于完整轨线集合；
- 切分单位必须是 trajectory，不是 window；
- 每个 split 内部再生成窗口。

---

### 3.7 窗口构造

**目的**  
从观测轨线中构造 benchmark 样本。

**输入**

$$

\mathbf Z^{(q)}
=
[\mathbf z_1^{(q)},\dots,\mathbf z_{M+1}^{(q)}].

$$

**输出**

one-step 样本：

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

**依赖**  
依赖 split 完成。

**诊断检查**

- one-step 样本数量应为每条轨线 $M$；
- rollout 窗口数量应为 $M-L+1$ 或按项目约定；
- 不允许跨轨线拼接窗口；
- 不允许 train/test 共享同一条轨线的窗口。

---

## 4. Directory and file plan

### 4.1 文档文件

| 路径 | 作用 |
|---|---|
| `docs/notes/mathematical explanation/lotka_volterra_math_explanation.md` | 保存本次数学说明书 |
| `docs/notes/code explanation/lotka_volterra_code_plan.md` | 保存本次代码工程计划书 |
| `docs/notes/file explanation/lotka_volterra_file_explanation.md` | 实现完成后记录文件说明、运行方式、输出解释 |
| `docs/spec/system_registry.md` | 增补 `lotka_volterra` 的 `v1_core` 注册条目 |
| `docs/spec/lotka_volterra_v1_core_entry.md` | 简短记录本次新增对象、版本、观测模式、split、任务，不写复杂实现细节 |

---

### 4.2 配置文件

| 路径 | 作用 |
|---|---|
| `configs/systems/lotka_volterra_smoke.json` | smoke 系统配置：少量轨线、短时间、小规模 |
| `configs/systems/lotka_volterra_orbit_family.json` | 正式系统配置：固定参数、多初值轨道族 |
| `configs/observations/lotka_volterra_full_state_clean.json` | 全状态、无噪声观测配置 |
| `configs/splits/lotka_volterra_split_i_smoke.json` | smoke 轨线切分配置 |
| `configs/splits/lotka_volterra_split_i_orbit_family.json` | 正式 Split-I 初值泛化切分配置 |
| `configs/windows/lotka_volterra_one_step.json` | one-step 样本窗口配置 |
| `configs/windows/lotka_volterra_rollout_short.json` | 短期 rollout 窗口配置 |
| `configs/windows/lotka_volterra_rollout_medium.json` | 中期 rollout 窗口配置 |
| `configs/windows/lotka_volterra_statistics_window.json` | 守恒量与长期统计窗口配置 |
| `configs/tasks/lotka_volterra_one_step_forecast.json` | 一步预测任务配置 |
| `configs/tasks/lotka_volterra_rollout_forecast.json` | 多步 rollout 任务配置 |
| `configs/tasks/lotka_volterra_long_time_statistics.json` | 长期统计与守恒量诊断任务配置 |
| `configs/benchmarks/lotka_volterra_v1_core_full_state_clean.json` | 汇总系统、观测、split、window、task 的 benchmark 配置 |
| `configs/releases/lotka_volterra_v1_core_release_candidate.json` | 正式发布候选清单 |

---

### 4.3 源码文件

| 路径 | 作用 |
|---|---|
| `src/dynamics/lotka_volterra.jl` | 系统右端、参数验证、正平衡点、Jacobian、守恒量 |
| `src/generators/lotka_volterra_generator.jl` | 按配置生成 smoke 与正式轨道族数据 |
| `src/diagnostics/lotka_volterra_diagnostics.jl` | 正性、守恒量漂移、轨线尺度、相图数据诊断 |
| `src/registries/system_registry.jl` | 增补 `lotka_volterra` 注册入口 |
| `src/observations/full_state_observation.jl` | 若尚未存在，则实现通用全状态观测；若已存在，则只复用 |
| `src/io/dataset_paths.jl` | 若已有路径工具，则新增 Lotka–Volterra 路径规则；若没有，则建立统一路径管理 |
| `src/manifests/manifest_writer.jl` | 若已有 manifest 写入工具，则复用；必要时补充系统字段 |
| `src/splits/trajectory_split.jl` | 复用或补充轨线级 split 逻辑 |
| `src/windows/window_construction.jl` | 复用或补充 one-step / rollout / statistics 窗口构造 |

---

### 4.4 实验入口文件

| 路径 | 作用 |
|---|---|
| `experiments/smoke_tests/run_lotka_volterra_smoke.jl` | 运行最小 smoke 流程，检查系统、积分、保存、诊断 |
| `experiments/smoke_tests/check_lotka_volterra_windows.jl` | 对 smoke 数据构造窗口并检查样本数量与尺寸 |
| `experiments/baseline_forecasting/inspect_lotka_volterra_one_step_data.jl` | 不训练模型，只检查 one-step benchmark 数据是否可被预测任务读取 |

说明：正式数据生成不单独写成“临时脚本”，而由 `configs/benchmarks/lotka_volterra_v1_core_full_state_clean.json` 驱动 `src/generators/lotka_volterra_generator.jl`。这样避免把正式数据生产逻辑散落在实验脚本中。

---

### 4.5 测试文件

| 路径 | 作用 |
|---|---|
| `test/unit/test_lotka_volterra_dynamics.jl` | 测试右端函数、参数验证、正平衡点、守恒量公式 |
| `test/unit/test_lotka_volterra_diagnostics.jl` | 测试守恒量诊断、正性诊断、轨线尺度诊断 |
| `test/integration/test_lotka_volterra_generation.jl` | 小规模端到端生成 raw / processed / manifest |
| `test/regression/test_lotka_volterra_smoke_regression.jl` | 固定 seed 下检查 smoke 输出规模、漂移量、split 数量不被意外破坏 |

---

### 4.6 数据输出文件

smoke 输出：

| 路径 | 内容 |
|---|---|
| `data/raw/v1_core/lotka_volterra/smoke/full_state_clean/raw_trajectories.jld2` | smoke 原始状态轨线 |
| `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/observed_trajectories.jld2` | smoke 全状态观测轨线 |
| `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/one_step_samples.jld2` | smoke one-step 样本 |
| `data/processed/v1_core/lotka_volterra/smoke/full_state_clean/rollout_windows.jld2` | smoke rollout 窗口 |
| `data/manifests/v1_core/lotka_volterra/smoke/full_state_clean/manifest.json` | smoke 生成元信息 |

正式轨道族输出：

| 路径 | 内容 |
|---|---|
| `data/raw/v1_core/lotka_volterra/orbit_family/full_state_clean/raw_trajectories.jld2` | 正式原始状态轨线 |
| `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/observed_trajectories.jld2` | 正式全状态观测轨线 |
| `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/splits.json` | 轨线级 train / val / test 切分 |
| `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/one_step_samples.jld2` | 正式 one-step 样本 |
| `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/rollout_windows.jld2` | 正式 rollout 窗口 |
| `data/processed/v1_core/lotka_volterra/orbit_family/full_state_clean/statistics_windows.jld2` | 正式 statistics 窗口 |
| `data/manifests/v1_core/lotka_volterra/orbit_family/full_state_clean/manifest.json` | 正式生成元信息 |
| `data/releases/ODEs_dataset-v1.0-candidate/lotka_volterra_full_state_clean_release_index.json` | 发布候选索引 |

---

### 4.7 报告输出文件

| 路径 | 内容 |
|---|---|
| `reports/v1_core/lotka_volterra_smoke/tables/diagnostics.csv` | smoke 轨线诊断表 |
| `reports/v1_core/lotka_volterra_orbit_family/tables/diagnostics.csv` | 正式轨道族诊断表 |
| `reports/v1_core/lotka_volterra_orbit_family/tables/split_summary.csv` | train / val / test 轨线与窗口数量 |
| `reports/v1_core/lotka_volterra_smoke/plots/smoke_phase_portrait.png` | smoke 相图 |
| `reports/v1_core/lotka_volterra_smoke/plots/smoke_time_series.png` | smoke 时间序列 |
| `reports/v1_core/lotka_volterra_smoke/plots/smoke_invariant_drift.png` | smoke 守恒量漂移 |
| `reports/v1_core/lotka_volterra_orbit_family/plots/orbit_family_phase_portraits.png` | 正式轨道族相图 |
| `reports/v1_core/lotka_volterra_orbit_family/plots/orbit_family_invariant_drift.png` | 正式轨道族守恒量漂移 |
| `reports/v1_core/lotka_volterra_orbit_family/plots/orbit_family_state_ranges.png` | 状态范围与尺度图 |
| `reports/v1_core/lotka_volterra_smoke/logs/smoke.log` | smoke 运行日志 |
| `reports/v1_core/lotka_volterra_orbit_family/logs/orbit_family.log` | 正式生成日志 |

本任务不产生模型 checkpoint，因为它是数据集生成任务，不是训练任务。

---

## 5. Module / component responsibilities

### `src/dynamics/`

负责数学系统本体：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\boldsymbol\mu).

$$

Lotka–Volterra 中包括：

- 右端函数；
- 参数名；
- 参数合法性；
- 状态合法性；
- 正平衡点；
- Jacobian；
- 守恒量。

---

### `src/generators/`

负责从配置生成轨线：

$$

(\mathbf f,\boldsymbol\mu,\mathbf x_0,\tau)
\rightarrow
\mathbf X.

$$

并调用观测链得到：

$$

\mathbf X\rightarrow \mathbf Z.

$$

---

### `src/observations/`

负责全状态观测：

$$

\mathbf z=\mathbf x.

$$

第一版不做噪声、不做归一化、不做部分观测。

---

### `src/splits/`

负责轨线级切分：

$$

\mathcal R
\rightarrow
\mathcal R_{\text{train}},
\mathcal R_{\text{val}},
\mathcal R_{\text{test}}.

$$

不能在窗口级随机切分。

---

### `src/windows/`

负责从每个 split 内部构造：

- one-step 样本；
- rollout 窗口；
- statistics 窗口。

---

### `src/diagnostics/`

负责数据质量检查：

- 正性；
- 守恒量漂移；
- 状态范围；
- 轨道族覆盖；
- 样本数量；
- 窗口数量；
- `NaN / Inf` 检查。

---

### `src/manifests/`

负责记录：

- 系统 ID；
- 参数；
- 初值；
- solver；
- tolerances；
- seed；
- observation ID；
- split ID；
- window ID；
- 数据文件路径；
- 生成时间；
- benchmark version。

---

### `reports/`

只保存给人看的结果：

- 表格；
- 图；
- 日志。

---

## 6. Planned `##` sections

### 6.1 `src/dynamics/lotka_volterra.jl`

计划章节：

```text
## System identity and state dimension
## Parameter names and default parameter set
## Parameter validation rules
## State validation rules for the positive quadrant
## Lotka–Volterra right-hand side
## Positive equilibrium formula
## Jacobian formula
## First integral / invariant formula
## Local frequency scale near the positive equilibrium
## Dynamics-level diagnostic summary
```

---

### 6.2 `src/generators/lotka_volterra_generator.jl`

计划章节：

```text
## Load Lotka–Volterra generation configuration
## Validate system, observation, split, and window specs
## Build smoke trajectory specifications
## Build orbit-family trajectory specifications
## Integrate raw state trajectories
## Apply full-state observation chain
## Construct trajectory-level split objects
## Construct one-step samples
## Construct rollout windows
## Construct statistics windows
## Save raw, processed, split, and window data
## Write manifest and generation summary
## Return paths and diagnostic handles
```

---

### 6.3 `src/diagnostics/lotka_volterra_diagnostics.jl`

计划章节：

```text
## Positivity diagnostics
## Invariant value computation along trajectories
## Absolute and relative invariant drift
## State range and scale diagnostics
## Equilibrium-centered amplitude diagnostics
## Orbit-family coverage diagnostics
## Split and window count diagnostics
## Diagnostic table assembly
## Plot data preparation for phase portraits and drift curves
```

---

### 6.4 `src/registries/system_registry.jl`

计划新增或修改章节：

```text
## v1_core system registrations
## Lotka–Volterra registration entry
## Registry consistency checks
```

---

### 6.5 `src/observations/full_state_observation.jl`

若尚未存在，计划章节：

```text
## Full-state observation identity map
## ObservationSpec validation for full-state mode
## State-to-observation matrix conversion
## Observation dimension checks
## Full-state clean observation metadata
```

---

### 6.6 `src/splits/trajectory_split.jl`

若需要补充，计划章节：

```text
## Trajectory index collection
## Seeded trajectory-level shuffle
## Train / validation / test partition
## Split disjointness checks
## Split summary table construction
```

---

### 6.7 `src/windows/window_construction.jl`

若需要补充，计划章节：

```text
## One-step sample construction
## Rollout window construction
## Statistics window construction
## Per-split window generation
## Window index validity checks
## Window count summary
```

---

### 6.8 `experiments/smoke_tests/run_lotka_volterra_smoke.jl`

计划章节：

```text
## Load smoke configuration
## Generate smoke raw trajectories
## Apply full-state observation
## Build smoke split and windows
## Run Lotka–Volterra diagnostics
## Save smoke reports and plots
## Print final smoke summary
```

---

### 6.9 `experiments/smoke_tests/check_lotka_volterra_windows.jl`

计划章节：

```text
## Load smoke processed trajectories
## Load window configuration
## Rebuild one-step samples for inspection
## Rebuild rollout windows for inspection
## Check window dimensions and counts
## Print window inspection summary
```

---

### 6.10 `experiments/baseline_forecasting/inspect_lotka_volterra_one_step_data.jl`

计划章节：

```text
## Load processed one-step samples
## Inspect input and target dimensions
## Compute naive persistence reference error
## Compute state scale statistics
## Save inspection table
## Print forecasting-data readiness summary
```

---

### 6.11 `test/unit/test_lotka_volterra_dynamics.jl`

计划章节：

```text
## Test parameter validation
## Test positive-state validation
## Test right-hand side output dimension
## Test positive equilibrium formula
## Test Jacobian dimension
## Test invariant formula on valid states
```

---

### 6.12 `test/integration/test_lotka_volterra_generation.jl`

计划章节：

```text
## Build minimal generation configuration
## Generate minimal raw trajectory set
## Apply full-state observation
## Save and reload generated data
## Check manifest completeness
## Check diagnostic thresholds
```

---

### 6.13 `test/regression/test_lotka_volterra_smoke_regression.jl`

计划章节：

```text
## Load fixed-seed smoke configuration
## Regenerate smoke dataset
## Compare trajectory counts
## Compare sample and window counts
## Compare invariant drift tolerance
## Compare split sizes
```

---

## 7. Data flow and dimensions

### 7.1 单条轨线

初值：

$$

\mathbf x_0^{(q)}
=
\begin{bmatrix}
x_0^{(q)}\\
y_0^{(q)}
\end{bmatrix}
\in\mathbb R^2_{>0}.

$$

采样后：

$$

\mathbf x_m^{(q)}
\in\mathbb R^2,
\qquad
m=1,\dots,M+1.

$$

状态矩阵：

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_1^{(q)} & \cdots & \mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

全状态观测：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

---

### 7.2 多轨线数据

轨线集合：

$$

\left\{
\mathbf Z^{(q)}
\right\}_{q=1}^{R}.

$$

若保存为三维数组，可采用：

$$

\mathcal Z\in\mathbb R^{2\times(M+1)\times R}.

$$

推荐在 manifest 中明确维度顺序：

```text
state_dim × time_index × trajectory_index
```

避免 Julia 中维度理解混乱。

---

### 7.3 one-step 样本

每条轨线可产生 $M$ 个 one-step 样本：

$$

\mathbf z_m^{(q)}
\rightarrow
\mathbf z_{m+1}^{(q)}.

$$

输入矩阵：

$$

\mathbf Z_{\text{now}}
\in\mathbb R^{2\times N_{\text{step}}},

$$

目标矩阵：

$$

\mathbf Z_{\text{next}}
\in\mathbb R^{2\times N_{\text{step}}}.

$$

其中

$$

N_{\text{step}}
=
\sum_{q\in\mathcal R_{\text{split}}} M.

$$

---

### 7.4 rollout 窗口

长度 $L$ 的 rollout 窗口：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

若使用三维数组保存：

$$

\mathcal W_{\text{roll}}
\in
\mathbb R^{2\times(L+1)\times N_{\text{roll}}}.

$$

其中 $L+1$ 包含起点和未来 $L$ 步。

---

### 7.5 statistics 窗口

统计窗口：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1}).

$$

保存维度：

$$

\mathcal W_{\text{stat}}
\in
\mathbb R^{2\times L\times N_{\text{stat}}}.

$$

用于计算：

- 时间均值；
- 状态范围；
- 守恒量局部漂移；
- 轨道周期粗略检查；
- 局部协方差。

---

## 8. Package and documentation plan

### 8.1 DifferentialEquations.jl / OrdinaryDiffEq.jl

**用途**

- 数值积分 Lotka–Volterra ODE；
- 控制 `dt`、`tspan`、保存采样点；
- 设置 `abstol` 与 `reltol`；
- 可能选择非刚性高精度 solver。

**需要查文档**

- ODEProblem 的推荐构造方式；
- 参数传递方式；
- `saveat` 的行为；
- solver 选择；
- 正性保护或 domain callback 是否需要；
- 解对象转矩阵的可靠方式。

---

### 8.2 LinearAlgebra

**用途**

- Jacobian；
- 特征值；
- 范数；
- 诊断中可能用到矩阵操作。

**需要查文档**

- 基础标准库通常不需要额外查 API，但仍应确认特征值输出类型与复数处理。

---

### 8.3 Random

**用途**

- 初值采样；
- split 随机种子；
- smoke / formal 可复现。

**需要查文档**

- 项目是否已有统一 seed 工具；
- 是否采用局部 RNG，避免污染全局随机状态。

---

### 8.4 Statistics

**用途**

- 轨线均值；
- 标准差；
- 状态范围摘要；
- 诊断表。

**需要查文档**

- 基础统计函数维度参数；
- 与矩阵维度约定的一致性。

---

### 8.5 JSON3.jl 或 TOML

**用途**

- 配置读取；
- manifest 保存；
- release index 保存。

**需要查文档**

- 当前项目已有配置格式；
- 字段类型映射；
- 嵌套对象读取方式；
- 写出格式是否稳定。

建议优先沿用 ODEs_dataset 已经采用的配置格式，不为本系统单独引入新格式。

---

### 8.6 JLD2.jl / HDF5.jl / Arrow.jl

**用途**

- 保存 raw trajectories；
- 保存 processed trajectories；
- 保存窗口样本；
- 保存大数组与表格索引。

**需要查文档**

- 当前项目标准数据格式；
- 多维数组读写；
- 元数据保存方式；
- 跨版本兼容性；
- 大文件增量写入是否需要。

---

### 8.7 CSV.jl / DataFrames.jl

**用途**

- 保存诊断表；
- 保存 split summary；
- 保存 trajectory summary。

**需要查文档**

- 当前项目是否已经使用 DataFrames；
- CSV 写出字段类型；
- 浮点精度格式。

---

### 8.8 Plots.jl 或 CairoMakie.jl

**用途**

- 相图；
- 时间序列；
- 守恒量漂移曲线；
- 轨道族覆盖图。

**需要查文档**

- 当前项目绘图库约定；
- 保存 PNG / PDF 的方式；
- 多轨线图的图例和透明度设置；
- 是否需要统一论文风格。

---

## 9. Debugging and inspection plan

### 9.1 运行时打印信息

smoke 运行应打印：

```text
system_id
state_dim
parameter values
number of trajectories
trajectory length
dt
tspan
observation_id
raw trajectory size
processed trajectory size
one-step sample count
rollout window count
min(x), min(y)
max(x), max(y)
max absolute invariant drift
max relative invariant drift
output paths
```

正式轨道族运行应额外打印：

```text
number of orbit-family trajectories
train / val / test trajectory counts
train / val / test one-step sample counts
train / val / test rollout window counts
min and max initial invariant values
median invariant drift
worst trajectory by invariant drift
worst trajectory by positivity margin
```

---

### 9.2 必查数值量

对每条轨线 $q$ 检查：

$$

\min_m x_m^{(q)}>0,
\qquad
\min_m y_m^{(q)}>0.

$$

守恒量漂移：

$$

\max_m |H_m^{(q)}-H_1^{(q)}|.

$$

相对守恒量漂移：

$$

\frac{\max_m |H_m^{(q)}-H_1^{(q)}|}
{|H_1^{(q)}|+\varepsilon}.

$$

状态范围：

$$

\min_m x_m,\quad \max_m x_m,
\quad
\min_m y_m,\quad \max_m y_m.

$$

正平衡点：

$$

(x_\ast,y_\ast)=
\left(
\frac{\gamma}{\delta},
\frac{\alpha}{\beta}
\right).

$$

轨道覆盖：

$$

H(\mathbf x_0^{(1)}),\dots,H(\mathbf x_0^{(R)}).

$$

---

### 9.3 必出图像

smoke：

- $x(t),y(t)$ 时间序列；
- $(x,y)$ 相图；
- $H(t)-H(0)$ 漂移曲线。

正式轨道族：

- 多轨线相图；
- 不同轨线的守恒量漂移曲线；
- 初始守恒量分布；
- 状态范围图。

---

### 9.4 判断结果是否合理

合理现象：

- 状态始终在正象限；
- 相图为围绕正平衡点的闭合轨道族；
- 捕食者变量 $y(t)$ 相对猎物变量 $x(t)$ 存在相位滞后；
- 守恒量漂移小；
- 不同初值产生不同振幅的闭合轨道；
- train / val / test 是按轨线分开的。

异常现象：

- 出现负状态；
- 相图螺旋收敛或发散很明显；
- 守恒量漂移持续单调变大；
- formal 轨道族都集中在同一条轨道附近；
- split 后窗口数量不匹配；
- one-step 样本跨越了不同轨线边界。

---

## 10. Expected outputs

### 10.1 smoke 输出

smoke 完成后应得到：

- raw trajectory 文件；
- processed trajectory 文件；
- one-step sample 文件；
- rollout window 文件；
- manifest；
- smoke diagnostics table；
- smoke phase portrait；
- smoke time series；
- smoke invariant drift plot；
- smoke log。

核心判断：

$$

\mathbf X,\mathbf Z\in\mathbb R^{2\times(M+1)\times R_{\text{smoke}}}

$$

维度正确，且守恒量漂移在可接受范围内。

---

### 10.2 正式轨道族输出

正式生成后应得到：

- fixed-parameter orbit-family raw trajectories；
- full-state clean observed trajectories；
- trajectory-level split；
- one-step samples；
- rollout windows；
- statistics windows；
- manifest；
- release candidate index；
- orbit-family diagnostics table；
- split summary table；
- orbit-family plots；
- generation log。

核心判断：

$$

R_{\text{formal}}>R_{\text{smoke}},

$$

并且

$$

\{H(\mathbf x_0^{(q)})\}_{q=1}^R

$$

覆盖多个不同能级。

---

## 11. Failure points and debugging strategies

### 11.1 状态变成负数

**可能原因**

- 初值太靠近坐标轴；
- solver 容差太松；
- 时间步长或保存间隔过粗；
- 轨线振幅过大。

**策略**

- 收紧初值范围；
- 提高积分精度；
- 检查是否需要正性保护；
- 在 formal 配置中排除过近坐标轴的轨道。

---

### 11.2 守恒量漂移过大

**可能原因**

- 积分器误差；
- 时间区间太长；
- solver 不适合保持该系统几何结构；
- 轨线靠近 $x=0$ 或 $y=0$，导致 $\log$ 项敏感。

**策略**

- 缩短 smoke 时间区间做对照；
- 收紧 `abstol` / `reltol`；
- 比较不同 solver；
- 输出最差轨线编号和对应初值；
- 检查 $\min x,\min y$。

---

### 11.3 轨道族覆盖不足

**可能原因**

- 初值采样范围太窄；
- 初值全部围绕正平衡点太近；
- 守恒量分布过集中。

**策略**

- 用 $H(\mathbf x_0)$ 分布检查覆盖度；
- 按正平衡点附近的不同半径采样；
- 设定最小和最大振幅约束；
- 避免过大轨道靠近坐标轴。

---

### 11.4 数据维度错乱

**可能原因**

- Julia 数组维度顺序混淆；
- 时间维和轨线维交换；
- one-step 样本拼接方向不一致。

**策略**

- manifest 中固定写明：

```text
state_dim × time_index × trajectory_index
```

- 每次保存前打印 size；
- 每次加载后再次检查 size；
- unit test 中固定小数组维度预期。

---

### 11.5 split 泄漏

**可能原因**

- 先构造窗口再随机切分；
- 同一轨线窗口进入不同 split；
- split 文件只保存样本编号，没有保存轨线编号。

**策略**

- split 必须先作用于 trajectory IDs；
- 窗口构造必须在 split 内部完成；
- split summary 中保存 trajectory IDs；
- regression test 检查 train / val / test 轨线集合互斥。

---

### 11.6 manifest 不完整

**可能原因**

- 只保存数据，没有保存生成参数；
- solver、seed、观测模式缺失；
- window 与 split 配置没有写入。

**策略**

manifest 至少记录：

```text
system_id
system_family
benchmark_layer
parameters
initial_condition_policy
state_dim
observation_id
observation_dim
dt
tspan
trajectory_length
number_of_trajectories
solver_name
solver_tolerances
seed
split_id
window_ids
task_ids
data_paths
diagnostic_paths
generation_time
```

---

## 12. Stop before code

以上是 Lotka–Volterra 系统接入 ODEs_dataset 的详细代码工程计划书。

我在这里停止，不写 Julia 代码。下一步需要你单独发出实现请求后，再进入代码实现阶段。