# Step 2：线性阻尼振子 / 谐振子数据集代码工程计划书

本计划只做工程设计，不写 Julia 代码。  
本次任务遵循 ODEs_dataset 的“配置 → 轨线生成 → 观测处理 → 数据保存 → 切分与窗口 → 任务与评测”流水线；工程指南要求动力系统、观测链、切分协议、窗口协议彼此解耦，并区分 `raw`、`processed`、`manifest` 三类数据产物。fileciteturn7file0  
系统对象指南中，线性阻尼振子 / 谐振子属于 `v1_core` 的第一个主测试系统，是所有方法的解析谱基线。fileciteturn7file1

---

## 1. Confirmed task summary

### 目标

构建 `v1_core` 第 1 个主要测试数据集：

$$

\texttt{linear\_oscillator}

$$

包含两个生成入口：

1. **smoke 脚本**
   - 系统：无阻尼谐振子；
   - 参数：$\gamma=0,\ \omega_0>0$；
   - 观测：全状态；
   - 目的：最小端到端生成测试，检查系统、观测、存盘、manifest、图表和基本诊断是否全部贯通。

2. **正式脚本**
   - 系统：欠阻尼线性振子；
   - 参数：$0<\gamma<\omega_0$；
   - 观测：全状态；
   - 目的：生成 `v1_core` 正式主数据版本，用于后续预测、系统辨识、Koopman 谱分析、rollout 和重构任务。

### 数学系统

状态为

$$

\mathbf x(t)=
\begin{bmatrix}
q(t)\\
v(t)
\end{bmatrix}
\in\mathbb R^2,

$$

动力学为

$$

\dot{\mathbf x}
=
\mathbf A(\gamma,\omega_0)\mathbf x,
\qquad
\mathbf A=
\begin{bmatrix}
0 & 1\\
-\omega_0^2 & -2\gamma
\end{bmatrix}.

$$

全状态观测为

$$

\mathbf z_m=\mathbf x_m
=
\begin{bmatrix}
q_m\\
v_m
\end{bmatrix}
\in\mathbb R^2.

$$

因此本任务中

$$

d_x=2,\qquad d_z=2.

$$

---

## 2. Task decomposition

### 总体分解

1. 定义线性振子系统配置。
2. 定义全状态观测配置。
3. 定义轨线级切分配置。
4. 定义一步与多步窗口配置。
5. 定义 benchmark 任务配置。
6. 实现或补充系统动力学模块。
7. 实现或复用全状态观测模块。
8. 实现数据生成主流程。
9. 实现轨线级 split 与窗口派生。
10. 实现线性振子的专属诊断。
11. 编写 smoke 入口脚本。
12. 编写正式数据生成入口脚本。
13. 保存 raw / processed / manifest。
14. 保存 plots / tables / logs。
15. 增加单元测试、集成测试和回归测试。

---

## 3. Sub-task specification

| 子任务 | purpose | input | output | dependency | 数学 / 数值表达 | diagnostic checks |
|---|---|---|---|---|---|---|
| 系统配置 | 声明线性振子参数、初值范围、采样步长、轨线长度 | `SystemSpec` 参数 | smoke 与正式系统配置 | 无 | $\dot x=A(\gamma,\omega_0)x$ | 检查 $\omega_0>0$，smoke 中 $\gamma=0$，正式中 $0<\gamma<\omega_0$ |
| 全状态观测配置 | 固定 $\mathbf z=\mathbf x$ | `ObservationSpec` | 观测配置 | 系统状态维数 | $U=I,\ S=I,\ Z=I$ | 检查 `output_dim = 2` |
| 初值采样 | 生成多条轨线初值 | 初值区域、随机种子、轨线数 | $\mathbf x_0^{(r)}$ | 系统配置 | $\mathbf x_0^{(r)}=(q_0^{(r)},v_0^{(r)})^\top$ | 排除近零初值；检查初值分布 |
| 参数采样 | 正式数据支持固定或小范围参数 | 参数区域、随机种子 | $\mu^{(r)}=(\gamma^{(r)},\omega_0^{(r)})$ | 系统配置 | smoke 固定 $\gamma=0$，正式固定或采样 $0<\gamma<\omega_0$ | 检查参数全部处于欠阻尼区 |
| 状态轨线生成 | 积分生成 raw 状态轨线 | 参数、初值、时间网格 | $\mathbf X^{(r)}\in\mathbb R^{2\times(M+1)}$ | 系统与采样 | $\mathbf x_{m+1}=F^\tau(\mathbf x_m)$ | 检查尺寸、NaN、Inf、振幅范围 |
| 观测轨线生成 | 将状态变为算法输入 | $\mathbf X^{(r)}$ | $\mathbf Z^{(r)}\in\mathbb R^{2\times(M+1)}$ | 状态轨线 | $\mathbf Z=\mathbf X$ | 检查 `Z == X` 在数值容差内成立 |
| split 生成 | 轨线级划分 train / val / test | 轨线 id、split 配置 | split index | 轨线生成 | $\mathcal R_{\rm train},\mathcal R_{\rm val},\mathcal R_{\rm test}$ | 检查三集合不交、覆盖全部轨线 |
| window 生成 | 生成 one-step 与 rollout 窗口 | split 后轨线 | window 样本索引 | split | one-step: $(z_m,z_{m+1})$；rollout: $(z_s,\dots,z_{s+L})$ | 检查窗口不跨轨线、不跨 split |
| 诊断计算 | 检查物理与谱正确性 | raw / processed 轨线 | 诊断表与图 | 数据已生成 | 能量 $E=\frac12v^2+\frac12\omega_0^2q^2$，谱 $\lambda_\pm$ | smoke 能量守恒；正式能量单调衰减 |
| smoke 入口 | 最小端到端测试 | smoke 配置 | 小数据、图、日志 | 所有核心模块 | $\gamma=0$ | 必须快速运行并通过核心断言 |
| 正式入口 | 生成 v1_core 主数据 | formal 配置 | 正式数据、manifest、报告 | smoke 通过后 | $0<\gamma<\omega_0$ | 检查数据规模、split、rollout、谱、能量 |

---

## 4. Directory and file plan

### 4.1 文档文件

| 路径 | 角色 |
|---|---|
| `docs/project guide/v1_core_linear_oscillator_plan.md` | 保存本次任务的工程计划书 |
| `docs/notes/file explanation/v1_core_linear_oscillator_outputs.md` | 实现后记录生成文件说明、运行方式、产物解释 |
| `docs/spec/system_registry.md` | 补充 `linear_oscillator` 的 `v1_core` 注册信息 |

---

### 4.2 配置文件

#### 系统配置

| 路径 | 角色 |
|---|---|
| `configs/systems/linear_oscillator_smoke_undamped.json` | smoke 系统配置，固定 $\gamma=0$，无阻尼谐振子 |
| `configs/systems/linear_oscillator_v1_core_damped.json` | 正式系统配置，固定或采样欠阻尼参数 $0<\gamma<\omega_0$ |

建议字段：

- `system_id = linear_oscillator`
- `family = v1_core`
- `variant = undamped_smoke` 或 `damped_v1_core`
- `state_dim = 2`
- `parameter_names = ["gamma", "omega0"]`
- `default_parameters`
- `parameter_domain`
- `initial_condition_domain`
- `dt`
- `tspan`
- `trajectory_length`
- `num_trajectories`
- `solver_name`
- `solver_abstol`
- `solver_reltol`
- `seed_policy`

#### 观测配置

| 路径 | 角色 |
|---|---|
| `configs/observations/full_state_2d_clean.json` | 全状态、无噪声、无降维观测配置 |

本次 smoke 与正式脚本均使用该观测配置：

$$

\mathbf z=\mathbf x,\qquad d_z=2.

$$

#### 切分配置

| 路径 | 角色 |
|---|---|
| `configs/splits/linear_oscillator_smoke_split_i.json` | smoke 的小规模轨线级 Split-I |
| `configs/splits/linear_oscillator_v1_core_split_i.json` | 正式数据的初值泛化 split |
| `configs/splits/linear_oscillator_v1_core_split_p.json` | 可预留的参数泛化 split，正式第一版可先不启用 |

本次主线建议先启用 Split-I：

$$

\text{train / val / test}
=
70\% / 15\% / 15\%.

$$

如果 smoke 轨线很少，可使用：

$$

80\% / 10\% / 10\%.

$$

#### 窗口配置

| 路径 | 角色 |
|---|---|
| `configs/windows/linear_oscillator_smoke_windows.json` | smoke 的 one-step 与短 rollout 窗口 |
| `configs/windows/linear_oscillator_v1_core_windows.json` | 正式 one-step、短中长 rollout、统计窗口配置 |

窗口类型：

- one-step；
- rollout short；
- rollout medium；
- rollout long；
- statistics window。

#### 任务配置

| 路径 | 角色 |
|---|---|
| `configs/tasks/linear_oscillator_forecasting_tasks.json` | 一步预测与多步 rollout 任务 |
| `configs/tasks/linear_oscillator_reconstruction_tasks.json` | 全状态观测下的状态 / 观测重构任务 |

#### benchmark 配置

| 路径 | 角色 |
|---|---|
| `configs/benchmarks/smoke_linear_oscillator_undamped_full_state.json` | smoke 入口使用的完整配置组合 |
| `configs/benchmarks/v1_core_linear_oscillator_damped_full_state.json` | 正式入口使用的完整配置组合 |

#### release 配置

| 路径 | 角色 |
|---|---|
| `configs/releases/linear_oscillator_v1_core_release_preview.json` | 正式数据发布前的冻结清单 |
| `configs/releases/linear_oscillator_v1_core_release_1_0.json` | 正式发布时的版本冻结清单 |

---

### 4.3 源码文件

| 路径 | 角色 |
|---|---|
| `src/dynamics/linear_oscillator.jl` | 定义线性振子系统本体、状态矩阵、右端项、解析谱、能量表达 |
| `src/observations/full_state_observation.jl` | 实现全状态观测链 $\mathbf z=\mathbf x$ |
| `src/generators/linear_oscillator_dataset_generator.jl` | 组织线性振子数据生成流程 |
| `src/datasets/trajectory_objects.jl` | 定义或补充 RawTrajectory、ObservedTrajectory、窗口对象的数据协议 |
| `src/splits/trajectory_splitter.jl` | 按轨线 id 生成 train / val / test split |
| `src/windows/window_builder.jl` | 从 split 后轨线生成 one-step、rollout、statistics 窗口 |
| `src/diagnostics/linear_oscillator_diagnostics.jl` | 线性振子专属诊断：能量、谱、相位、幅值衰减 |
| `src/manifests/manifest_writer.jl` | 写入系统、观测、split、window、solver、seed、数据尺寸元信息 |
| `src/io/dataset_paths.jl` | 统一管理 raw / processed / manifest / reports 路径 |
| `src/registries/system_registry.jl` | 注册 `linear_oscillator` 到 `v1_core` |

---

### 4.4 入口脚本

| 路径 | 角色 |
|---|---|
| `experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl` | smoke 入口；使用无阻尼谐振子、全状态观测 |
| `experiments/benchmark_generation/generate_linear_oscillator_damped_full_state.jl` | 正式数据生成入口；使用欠阻尼振子、全状态观测 |

说明：`benchmark_generation/` 是建议新增在 `experiments/` 下的正式数据生成入口目录。它只组织运行，不保存核心逻辑；核心逻辑仍在 `src/generators/`。

---

### 4.5 数据产物路径

#### smoke 数据

| 路径 | 内容 |
|---|---|
| `data/raw/v1_core/linear_oscillator/smoke_undamped_full_state/` | smoke raw 状态轨线 |
| `data/processed/v1_core/linear_oscillator/smoke_undamped_full_state/` | smoke 全状态观测数据 |
| `data/manifests/v1_core/linear_oscillator/smoke_undamped_full_state/` | smoke manifest |
| `reports/v1_core/linear_oscillator/plots/smoke_undamped_full_state/` | smoke 图表 |
| `reports/v1_core/linear_oscillator/tables/smoke_undamped_full_state/` | smoke 诊断表 |
| `reports/v1_core/linear_oscillator/logs/smoke_undamped_full_state/` | smoke 日志 |

#### 正式数据

| 路径 | 内容 |
|---|---|
| `data/raw/v1_core/linear_oscillator/damped_full_state/` | 正式 raw 状态轨线 |
| `data/processed/v1_core/linear_oscillator/damped_full_state/` | 正式全状态观测数据 |
| `data/manifests/v1_core/linear_oscillator/damped_full_state/` | 正式 manifest |
| `data/releases/v1_core/linear_oscillator/damped_full_state/` | 正式 release 清单 |
| `reports/v1_core/linear_oscillator/plots/damped_full_state/` | 正式图表 |
| `reports/v1_core/linear_oscillator/tables/damped_full_state/` | 正式诊断表 |
| `reports/v1_core/linear_oscillator/logs/damped_full_state/` | 正式日志 |

---

### 4.6 测试文件

| 路径 | 角色 |
|---|---|
| `test/unit/test_linear_oscillator_dynamics.jl` | 检查状态矩阵、谱、能量公式、参数合法性 |
| `test/unit/test_full_state_observation.jl` | 检查全状态观测维度与数值一致性 |
| `test/unit/test_linear_oscillator_windows.jl` | 检查 one-step 与 rollout 窗口索引 |
| `test/integration/test_smoke_linear_oscillator_undamped.jl` | 端到端 smoke 集成测试 |
| `test/regression/test_linear_oscillator_v1_core_counts.jl` | 固定配置下检查轨线数、样本数、split 数、窗口数不意外变化 |

---

## 5. Module / component responsibilities

### `src/dynamics/`

负责数学系统本体：

$$

\dot{\mathbf x}=A\mathbf x.

$$

职责：

- 参数合法性检查；
- 状态矩阵 $A(\gamma,\omega_0)$；
- ODE 右端；
- 解析连续谱；
- 解析离散谱；
- 能量表达。

不负责：

- 初值采样；
- split；
- 存盘；
- 观测加噪；
- 任务构造。

---

### `src/observations/`

本次只需要全状态观测：

$$

\mathbf z=\mathbf x.

$$

职责：

- 接收 $\mathbf X\in\mathbb R^{2\times(M+1)}$；
- 返回 $\mathbf Z\in\mathbb R^{2\times(M+1)}$；
- 记录 `observation_id`、`mode`、`output_dim`；
- 支持未来扩展到部分观测、线性混合、带噪观测。

---

### `src/generators/`

职责：

- 读取 benchmark 配置；
- 调用 dynamics 生成 raw；
- 调用 observations 生成 processed；
- 调用 split 与 window 模块派生任务索引；
- 调用 diagnostics；
- 调用 manifest 与 io 保存结果。

不应在入口脚本中写核心生成逻辑。

---

### `src/splits/`

职责：

- 以整条轨线为单位切分；
- 生成 train / val / test 的 trajectory id；
- 禁止窗口级随机打乱。

---

### `src/windows/`

职责：

给定一条观测轨线

$$

\mathbf Z^{(r)}\in\mathbb R^{2\times(M+1)},

$$

生成：

- one-step 样本；
- rollout 样本；
- statistics 样本。

---

### `src/diagnostics/`

线性振子专属检查：

- 能量曲线；
- 相图；
- 时间序列；
- 连续谱；
- 离散谱；
- 数值积分与解析传播误差；
- split 和 window 统计。

---

### `src/manifests/`

职责：

- 保存系统配置快照；
- 保存观测配置快照；
- 保存 split / window / task 配置快照；
- 保存 solver 信息；
- 保存随机种子；
- 保存数据尺寸；
- 保存数据文件路径；
- 保存诊断摘要。

---

## 6. Planned `##` sections

### `src/dynamics/linear_oscillator.jl`

建议章节：

1. `## Linear oscillator parameter conventions`
2. `## Parameter validity checks for undamped and underdamped regimes`
3. `## Continuous-time state matrix construction`
4. `## ODE right-hand side definition`
5. `## Continuous spectrum and discrete spectrum metadata`
6. `## Analytic energy and damping diagnostics`
7. `## State dimension and variable-name metadata`

---

### `src/observations/full_state_observation.jl`

建议章节：

1. `## Full-state observation specification`
2. `## Identity state-to-observation map`
3. `## Observation dimension checks`
4. `## Noise and normalization policy placeholders`
5. `## Observation metadata construction`

---

### `src/generators/linear_oscillator_dataset_generator.jl`

建议章节：

1. `## Benchmark configuration loading`
2. `## System and observation consistency checks`
3. `## Random seed initialization and reproducibility metadata`
4. `## Parameter-instance generation`
5. `## Initial-condition generation`
6. `## Raw state trajectory generation`
7. `## Full-state observed trajectory construction`
8. `## Train-val-test split generation`
9. `## One-step and rollout window derivation`
10. `## Linear oscillator diagnostic evaluation`
11. `## Raw, processed, manifest, report saving`

---

### `src/datasets/trajectory_objects.jl`

建议章节：

1. `## Raw trajectory object fields`
2. `## Observed trajectory object fields`
3. `## One-step sample object fields`
4. `## Rollout window sample object fields`
5. `## Statistics window sample object fields`
6. `## Dataset object dimension validation`

---

### `src/splits/trajectory_splitter.jl`

建议章节：

1. `## Split configuration parsing`
2. `## Trajectory-level index shuffling`
3. `## Train-val-test trajectory partitioning`
4. `## Split disjointness validation`
5. `## Split summary metadata`

---

### `src/windows/window_builder.jl`

建议章节：

1. `## One-step window index construction`
2. `## Rollout window index construction`
3. `## Statistics window index construction`
4. `## Window boundary validation within trajectories`
5. `## Window count summary by split`

---

### `src/diagnostics/linear_oscillator_diagnostics.jl`

建议章节：

1. `## Time-series range diagnostics`
2. `## Phase-plane trajectory diagnostics`
3. `## Mechanical energy diagnostics`
4. `## Undamped energy-conservation checks`
5. `## Damped energy-decay checks`
6. `## Continuous and discrete spectrum diagnostics`
7. `## Analytic-vs-numeric rollout consistency checks`
8. `## Diagnostic table and plot metadata`

---

### `src/manifests/manifest_writer.jl`

建议章节：

1. `## Manifest schema for ODE datasets`
2. `## System configuration snapshot`
3. `## Observation configuration snapshot`
4. `## Split, window, and task configuration snapshot`
5. `## Solver and random seed metadata`
6. `## Dataset shape and file-path metadata`
7. `## Diagnostic summary metadata`

---

### `src/io/dataset_paths.jl`

建议章节：

1. `## Dataset root path resolution`
2. `## Raw data path construction`
3. `## Processed data path construction`
4. `## Manifest path construction`
5. `## Report path construction`
6. `## Path existence and overwrite-policy checks`

---

### `src/registries/system_registry.jl`

建议章节：

1. `## v1_core system registry entries`
2. `## Linear oscillator registry metadata`
3. `## Registry validation for system identifiers`

---

### `experiments/smoke_tests/smoke_linear_oscillator_undamped_full_state.jl`

建议章节：

1. `## Load smoke benchmark configuration`
2. `## Confirm undamped full-state setup`
3. `## Run minimal linear oscillator generation`
4. `## Run smoke diagnostics`
5. `## Save smoke data and reports`
6. `## Print smoke summary`

---

### `experiments/benchmark_generation/generate_linear_oscillator_damped_full_state.jl`

建议章节：

1. `## Load v1_core benchmark configuration`
2. `## Confirm underdamped full-state setup`
3. `## Run formal trajectory generation`
4. `## Build official splits and windows`
5. `## Run formal diagnostics`
6. `## Save v1_core data release artifacts`
7. `## Print formal generation summary`

---

## 7. Data flow and dimensions

### 7.1 单条轨线

对第 $r$ 条轨线：

$$

\mathbf x_0^{(r)}\in\mathbb R^2.

$$

状态轨线：

$$

\mathbf X^{(r)}
=
\begin{bmatrix}
\mathbf x_1^{(r)} & \cdots & \mathbf x_{M+1}^{(r)}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

全状态观测：

$$

\mathbf Z^{(r)}
=
\mathbf X^{(r)}
\in\mathbb R^{2\times(M+1)}.

$$

### 7.2 多条轨线

若共有 $R$ 条轨线，则数据集合为：

$$

\left\{
\mathbf X^{(r)},\mathbf Z^{(r)}
\right\}_{r=1}^{R}.

$$

可以逻辑上理解为三维数组：

$$

\mathcal X\in\mathbb R^{R\times 2\times(M+1)},
\qquad
\mathcal Z\in\mathbb R^{R\times 2\times(M+1)}.

$$

实际存储可以按轨线对象逐条保存，也可以批量保存，但 manifest 必须记录维度。

### 7.3 one-step 样本

对每条长度 $M+1$ 的轨线：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
m=1,\dots,M.

$$

每条轨线 one-step 样本数为：

$$

M.

$$

若某个 split 中有 $R_{\rm split}$ 条轨线，则 one-step 样本数为：

$$

R_{\rm split}M.

$$

### 7.4 rollout 窗口

horizon 为 $L$ 时，一个窗口为：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

每条轨线可用起点数为：

$$

M+1-L.

$$

每个窗口的数据维度为：

$$

2\times(L+1).

$$

若 split 中有 $R_{\rm split}$ 条轨线，则 rollout 窗口数为：

$$

R_{\rm split}(M+1-L).

$$

### 7.5 smoke 建议规模

smoke 只检查流程，不追求统计覆盖。

建议：

$$

R_{\rm smoke}\in[4,12],
\qquad
M_{\rm smoke}\in[200,1000],
\qquad
L_{\rm smoke}\in[10,50].

$$

smoke 应该保证：

- 至少覆盖若干个完整周期；
- 文件数量少；
- 图表少；
- 运行日志清晰；
- 数据可手动检查。

### 7.6 正式数据建议规模

正式数据用于 v1_core 主基准。

建议：

$$

R_{\rm formal}\in[100,1000],
\qquad
M_{\rm formal}\in[1000,10000],

$$

并提供 short / medium / long rollout：

$$

L_{\rm short}<L_{\rm medium}<L_{\rm long}.

$$

正式欠阻尼参数应满足：

$$

0<\gamma<\omega_0.

$$

如果第一版暂不做参数泛化，可以固定：

$$

\gamma=0.05,\qquad \omega_0=1.0.

$$

如果第一版希望轻量支持参数泛化，可以采样：

$$

\gamma\in[\gamma_{\min},\gamma_{\max}],
\qquad
\omega_0\in[\omega_{\min},\omega_{\max}],
\qquad
\gamma_{\max}<\omega_{\min}.

$$

---

## 8. Package and documentation plan

正式实现前需要查官方文档，不应凭记忆假设 API。

| 包方向 | 用途 | 需要查文档的点 |
|---|---|---|
| `DifferentialEquations.jl` / `OrdinaryDiffEq.jl` | 统一 ODE 积分接口 | ODE problem 构造、保存指定时间点、容差、算法选择、解对象访问方式 |
| `LinearAlgebra` | 矩阵、特征值、矩阵指数、范数 | 矩阵指数、特征分解、复特征值处理 |
| `Random` / `StableRNGs` | 可复现初值、参数、split 采样 | RNG 初始化、跨平台稳定性 |
| `JSON3.jl` 或 `TOML.jl` | 读取配置文件 | 嵌套配置、数值数组、字典字段访问 |
| `JLD2.jl` 或 `HDF5.jl` | 保存 raw / processed 数据 | 数组、字典、元信息保存与读取 |
| `CSV.jl` / `DataFrames.jl` | 保存诊断表、样本统计表 | 表格写入、列类型 |
| `Plots.jl` 或 `CairoMakie.jl` | 时间序列、相图、能量图、谱图 | 保存图片、布局、无显示环境运行 |

---

## 9. Debugging and inspection plan

### 9.1 每次运行必须打印 / 保存的尺寸

- `state_dim = 2`
- `observation_dim = 2`
- `num_trajectories = R`
- `trajectory_length = M + 1`
- `raw state shape = 2 × (M+1)`
- `processed observation shape = 2 × (M+1)`
- train / val / test 轨线数
- one-step 样本数
- rollout 窗口数
- 每种 horizon 的窗口数

### 9.2 smoke 必须检查

smoke 使用无阻尼系统：

$$

\gamma=0.

$$

核心检查：

1. 能量近似守恒：

$$

E_m=
\frac12 v_m^2+\frac12\omega_0^2q_m^2.

$$

要求：

$$

\max_m |E_m-E_1|

$$

足够小。

2. 连续谱为纯虚数：

$$

\lambda_\pm=\pm i\omega_0.

$$

3. 离散谱模长应接近 1：

$$

|\rho_\pm|=|e^{\tau\lambda_\pm}|=1.

$$

4. 相图应为闭合椭圆。
5. $\mathbf Z=\mathbf X$。
6. split 不重叠。
7. window 不跨轨线。

### 9.3 正式脚本必须检查

正式使用欠阻尼系统：

$$

0<\gamma<\omega_0.

$$

核心检查：

1. 连续谱：

$$

\lambda_\pm=-\gamma\pm i\sqrt{\omega_0^2-\gamma^2}.

$$

2. 离散谱模长：

$$

|\rho_\pm|=e^{-\gamma\tau}<1.

$$

3. 能量总体衰减。
4. 振幅包络近似按 $e^{-\gamma t}$ 衰减。
5. 相图为向内螺旋。
6. 数值轨线无 NaN / Inf。
7. 后半段轨线不应全部衰减到机器零附近。
8. split 和窗口统计与配置一致。

### 9.4 应保存的图

| 图 | smoke | 正式 |
|---|---:|---:|
| $q(t)$ 时间序列 | 是 | 是 |
| $v(t)$ 时间序列 | 是 | 是 |
| 相图 $q$-$v$ | 是 | 是 |
| 能量曲线 $E(t)$ | 是 | 是 |
| 连续谱图 | 是 | 是 |
| 离散谱图 | 是 | 是 |
| rollout 示例窗口图 | 可选 | 是 |
| 初值散点图 | 可选 | 是 |

### 9.5 应保存的表

| 表 | 内容 |
|---|---|
| `trajectory_summary.csv` | 每条轨线的参数、初值、最大范数、最小范数、能量范围 |
| `split_summary.csv` | train / val / test 轨线数与样本数 |
| `window_summary.csv` | 每种窗口类型、horizon、split 下的窗口数 |
| `spectrum_summary.csv` | 连续谱、离散谱、模长、角度 |
| `energy_summary.csv` | 初始能量、最终能量、最大能量漂移、是否单调衰减 |

---

## 10. Expected outputs

### 10.1 smoke 输出

smoke 运行后应产生：

1. 小规模 raw 状态轨线；
2. 小规模 processed 全状态观测轨线；
3. smoke split；
4. smoke one-step 与短 rollout 窗口；
5. manifest；
6. 时间序列图；
7. 相图；
8. 能量守恒图；
9. 谱图；
10. smoke 日志；
11. smoke 诊断表。

核心判断：

$$

\mathbf Z=\mathbf X,
\qquad
E(t)\approx E(0),
\qquad
|\rho_\pm|\approx 1.

$$

### 10.2 正式输出

正式脚本运行后应产生：

1. `v1_core` 欠阻尼 raw 状态轨线；
2. `v1_core` 欠阻尼 processed 全状态观测轨线；
3. 官方 Split-I；
4. one-step、short / medium / long rollout、statistics windows；
5. 正式 manifest；
6. release preview；
7. 数据规模表；
8. 能量衰减诊断表；
9. 谱诊断表；
10. 轨线图、相图、能量图、谱图；
11. 日志文件。

核心判断：

$$

\mathbf Z=\mathbf X,
\qquad
0<\gamma<\omega_0,
\qquad
|\rho_\pm|=e^{-\gamma\tau}<1.

$$

---

## 11. Failure points and debugging strategies

### 11.1 维度错位

现象：

- `X` 被保存成 $(M+1)\times 2$；
- `Z` 与 `X` 方向不一致；
- window 切片把时间维和状态维混淆。

策略：

- 所有轨线统一检查：

$$

\mathbf X,\mathbf Z\in\mathbb R^{2\times(M+1)}.

$$

- 保存前、读入后都打印 shape。
- window 生成只沿时间索引切片。

---

### 11.2 smoke 能量不守恒

现象：

$$

E(t)

$$

显著漂移。

可能原因：

- solver 容差太松；
- 时间采样点不对；
- 速度分量顺序错；
- $\omega_0^2$ 写错；
- 阻尼参数没有真正设为 0。

策略：

- 检查 $\gamma=0$ 是否进入系统矩阵；
- 检查状态顺序是否为 $[q,v]$；
- 对比解析离散传播；
- 收紧容差；
- 缩短 smoke 时间窗排除长时间误差累积。

---

### 11.3 正式数据衰减过快

现象：

- 后半段轨线接近零；
- 训练样本信息量不足；
- 能量曲线过早贴近零。

可能原因：

- $\gamma$ 太大；
- 轨线太长；
- 初值幅值太小。

策略：

- 降低 $\gamma$；
- 缩短 $t_{\max}$；
- 设置初值最小范数；
- 检查每条轨线最终范数分布。

---

### 11.4 离散谱角度混叠

现象：

- 谱图角度与预期不一致；
- rollout 表现出错误周期。

原因：

$$

\omega_d\tau

$$

过大，采样过稀。

策略：

- 令每个振荡周期至少有足够采样点；
- 保存 `points_per_period` 诊断；
- 在配置中显式记录 $\tau/T_d$。

---

### 11.5 split 泄漏

现象：

- train / test 指标异常好；
- 相邻窗口跨 split。

原因：

- 先切窗口后切 split；
- 同一轨线进入多个集合。

策略：

- split 必须先按 trajectory id 做；
- window 只能在每个 split 内部生成；
- 保存 split disjointness 检查。

---

### 11.6 manifest 不完整

现象：

- 之后无法复现实验；
- 不知道数据来自哪个参数或随机种子；
- 不知道使用哪个观测配置。

策略：

manifest 必须包含：

- `system_id`
- `system_variant`
- `observation_id`
- `split_id`
- `window_id`
- `task_id`
- `dataset_version`
- `solver_name`
- `solver_abstol`
- `solver_reltol`
- `seed`
- `dt`
- `trajectory_length`
- `num_trajectories`
- `state_dim`
- `observation_dim`
- raw / processed 文件路径
- 诊断摘要

---

## 12. Stop before code

到这里为止，本次任务已经完成详细代码工程计划书。  
下一步应先确认文件命名、目录安排、smoke / 正式参数规模与配置格式，然后再单独进入实现请求。当前回复不包含任何 Julia 代码。