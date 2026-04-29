## Step 2：Lorenz ’63 详细代码工程计划书

### 1. Confirmed task summary

本次任务是在 **ODEs_dataset** 中新增经典 **Lorenz ’63** 系统，作为 `v1_core` 混沌系统 benchmark。系统指南中已将 Lorenz ’63 定位为测试耗散混沌、短期可预报性、长期失相、谱稳定性与统计保持能力的核心系统。fileciteturn7file1

已确认设定：

- 系统：标准 Lorenz ’63；
- 参数：

$$

\sigma=10,\qquad \rho=28,\qquad \beta=\frac83.

$$

- 状态维数：

$$

d_x=3.

$$

- 观测方式：全状态观测；

$$

\mathbf z_m=\mathbf x_m,\qquad d_z=3.

$$

- 不做参数泛化；
- 采用多初值轨道族；
- 数值积分时先经过 burn-in，再保存吸引子上的正式轨线；
- 必须输出三维相空间轨线图；
- 数据切分按整条轨线进行，不能先切窗口再随机划分；项目指南明确要求先按轨线切分，再在各 split 内部构造窗口。fileciteturn7file1

数学系统为：

$$

\begin{aligned}
\dot x &= \sigma(y-x),\\
\dot y &= x(\rho-z)-y,\\
\dot z &= xy-\beta z.
\end{aligned}

$$

数据流水线为：

$$

(\mathbf f,\boldsymbol\mu,\mathbf x_0,\tau)
\Longrightarrow
\mathbf X
\Longrightarrow
\mathbf Z
\Longrightarrow
\text{splits}
\Longrightarrow
\text{windows}
\Longrightarrow
\text{diagnostics}
\Longrightarrow
\text{reports}.

$$

其中 ODEs_dataset 负责数据生成、观测、切分、窗口与诊断；Koopman Learning 工程只负责后续模型训练和评测，不应重新承担数据生成职责。这个边界与项目目录指南中“数据集配置负责数据怎么生成，Koopman Learning 配置负责模型怎么训练、评测、保存”的原则一致。fileciteturn7file2

---

### 2. Task decomposition

#### 2.1 系统注册与配置

定义 Lorenz ’63 的系统配置、观测配置、split 配置、window 配置和 benchmark 配置。

#### 2.2 动力系统本体

新增 Lorenz ’63 的右端函数、参数校验、平衡点诊断信息和 Jacobian 诊断信息。

#### 2.3 初值族与 burn-in 轨线生成

从初值区域采样多条轨线。每条轨线先积分 burn-in 时间段，再保存正式时间段。

#### 2.4 全状态观测处理

第一版观测链为恒等映射：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.

$$

因此：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

项目规范中低维 ODE 的最简单观测情形正是 $\mathbf z=\mathbf x$。fileciteturn7file0

#### 2.5 轨线级 split

按轨线编号生成 train / val / test，不允许窗口级随机切分。

#### 2.6 窗口派生

从各 split 内部生成：

- one-step 样本；
- short rollout 窗口；
- medium rollout 窗口；
- statistics window。

#### 2.7 Lorenz 专属诊断

计算：

- 状态范围；
- 是否存在 NaN / Inf；
- burn-in 后是否进入吸引子区域；
- 三维吸引子轨线图；
- $xy$、$xz$、$yz$ 投影图；
- 坐标时间序列；
- 均值、方差、协方差；
- 双翼切换粗诊断；
- 短期轨线分离诊断。

#### 2.8 数据、图表、日志与 manifest 保存

保存 raw、processed、split、manifest、diagnostic table、plots 和 logs。项目指南要求 raw、processed、manifest 分离保存，这一点需要严格遵守。fileciteturn7file0

---

### 3. Sub-task specification

#### Sub-task A：新增系统配置

**目的**  
用声明式配置固定 Lorenz ’63 的参数、初值范围、时间步长、轨线长度、burn-in、solver 容差和随机种子。

**输入**

- 系统名称：`lorenz63`
- 参数：

$$

(\sigma,\rho,\beta)=(10,28,8/3)

$$

- 初值采样区域：

$$

\mathcal X_0\subset\mathbb R^3

$$

- 采样步长 $\tau$
- burn-in 时间 $T_{\mathrm{burn}}$
- 保存时间 $T_{\mathrm{keep}}$
- 轨线数 $R$

**输出**

- `SystemSpec`
- smoke 配置
- standard 配置

**依赖**  
无。

**数学表达**

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\sigma,\rho,\beta),
\qquad
\mathbf x_0^{(q)}\sim \mathcal P_0.

$$

**诊断检查**

- `state_dim = 3`
- 参数名必须为 `sigma, rho, beta`
- 参数为固定单点，不是参数网格
- `trajectory_length` 与 $\tau,T_{\mathrm{keep}}$ 一致
- `burn_in_time` 与正式保存时间分离

---

#### Sub-task B：新增 Lorenz ’63 动力系统文件

**目的**  
在 `src/dynamics/` 中提供 Lorenz ’63 的系统本体、右端函数、参数校验和数学诊断对象。

**输入**

$$

\mathbf x=(x,y,z)^\top\in\mathbb R^3,
\qquad
\boldsymbol\mu=(\sigma,\rho,\beta).

$$

**输出**

$$

\mathbf f(\mathbf x;\boldsymbol\mu)
=
\begin{bmatrix}
\sigma(y-x)\\
x(\rho-z)-y\\
xy-\beta z
\end{bmatrix}.

$$

**依赖**  
依赖系统配置中的参数字段。

**相关数学表达**

Jacobian：

$$

D\mathbf f(\mathbf x)=
\begin{bmatrix}
-\sigma & \sigma & 0\\
\rho-z & -1 & -x\\
y & x & -\beta
\end{bmatrix}.

$$

散度：

$$

\nabla\cdot \mathbf f
=
-\sigma-1-\beta
=
-\frac{41}{3}.

$$

非零平衡点：

$$

\mathbf x_\ast^{(\pm)}
=
\left(
\pm \sqrt{\beta(\rho-1)},
\pm \sqrt{\beta(\rho-1)},
\rho-1
\right)^\top.

$$

标准参数下：

$$

\mathbf x_\ast^{(\pm)}
=
(\pm6\sqrt2,\pm6\sqrt2,27)^\top.

$$

**诊断检查**

- 输入状态必须长度为 3；
- 输出向量必须长度为 3；
- 参数必须为正；
- $\rho>1$ 时非零平衡点存在；
- 散度应为负，确认系统耗散。

---

#### Sub-task C：轨线生成与 burn-in

**目的**  
对每个初值先积分 burn-in 段，再保存吸引子上的正式轨线。

**输入**

- `SystemSpec`
- 初值集合：

$$

\{\mathbf x_0^{(q)}\}_{q=1}^R

$$

- burn-in 时间 $T_{\mathrm{burn}}$
- 保存时间 $T_{\mathrm{keep}}$
- 采样步长 $\tau$

**输出**

每条正式轨线：

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_0^{(q,\mathrm{keep})}&
\mathbf x_1^{(q,\mathrm{keep})}&
\cdots&
\mathbf x_M^{(q,\mathrm{keep})}
\end{bmatrix}
\in\mathbb R^{3\times(M+1)}.

$$

这里 $\mathbf x_0^{(q,\mathrm{keep})}$ 是 burn-in 后的状态，不是原始采样初值。

**依赖**

- Sub-task A
- Sub-task B

**相关数学表达**

先积分：

$$

\mathbf x_{\mathrm{burn}}^{(q)}
=
\Phi^{T_{\mathrm{burn}}}(\mathbf x_0^{(q)}).

$$

再保存：

$$

\mathbf x_m^{(q)}
=
\Phi^{m\tau}(\mathbf x_{\mathrm{burn}}^{(q)}),
\qquad
m=0,\dots,M.

$$

其中：

$$

M=\frac{T_{\mathrm{keep}}}{\tau}.

$$

**诊断检查**

- 每条轨线维度为 $3\times(M+1)$；
- 所有轨线长度一致；
- 无 NaN / Inf；
- burn-in 后状态没有异常远离吸引子；
- 坐标范围处于合理 Lorenz 吸引子尺度；
- 至少部分轨线覆盖双翼结构。

---

#### Sub-task D：全状态观测处理

**目的**  
生成 `ObservedTrajectory`，保持：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

**输入**

$$

\mathbf X^{(q)}\in\mathbb R^{3\times(M+1)}.

$$

**输出**

$$

\mathbf Z^{(q)}\in\mathbb R^{3\times(M+1)}.

$$

**依赖**

- Sub-task C
- observation 配置

**相关数学表达**

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I.

$$

**诊断检查**

- $d_z=d_x=3$；
- $\|\mathbf Z-\mathbf X\|_{\mathrm F}=0$；
- observation metadata 标记为 `full_state_identity`；
- 不添加噪声；
- 不做部分观测；
- 不改变 raw physical scale。

---

#### Sub-task E：轨线级 split

**目的**  
基于轨线编号做初值泛化切分。

**输入**

$$

\{1,2,\dots,R\}.

$$

**输出**

$$

\mathcal Q_{\mathrm{train}},
\qquad
\mathcal Q_{\mathrm{val}},
\qquad
\mathcal Q_{\mathrm{test}}.

$$

**依赖**

- Sub-task C
- Sub-task D

**相关数学表达**

$$

\mathcal Q_{\mathrm{train}}
\cap
\mathcal Q_{\mathrm{val}}
=
\varnothing,

$$

$$

\mathcal Q_{\mathrm{train}}
\cap
\mathcal Q_{\mathrm{test}}
=
\varnothing,

$$

$$

\mathcal Q_{\mathrm{val}}
\cap
\mathcal Q_{\mathrm{test}}
=
\varnothing.

$$

**诊断检查**

- split 单位必须是 trajectory；
- train / val / test 不共享轨线；
- split 比例接近配置值；
- 每个 split 中轨线数量非零；
- split 文件记录随机种子。

---

#### Sub-task F：窗口构造

**目的**  
从各 split 内部生成标准任务窗口。

**输入**

$$

\mathbf Z^{(q)}\in\mathbb R^{3\times(M+1)}.

$$

**输出**

one-step 样本：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
\mathbf z_m\in\mathbb R^3.

$$

rollout 窗口：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}),
\qquad
\in\mathbb R^{3\times(L+1)}.

$$

statistics window：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L_{\mathrm{stat}}-1})
\in\mathbb R^{3\times L_{\mathrm{stat}}}.

$$

**依赖**

- Sub-task E

**相关数学表达**

可用窗口起点满足：

$$

0\le s\le M-L.

$$

**诊断检查**

- 每个窗口不跨轨线；
- 每个窗口不跨 split；
- rollout horizon 不超过轨线长度；
- one-step 样本数量为每条轨线 $M$ 个；
- rollout 样本数量为每条轨线 $M-L+1$ 个。

---

#### Sub-task G：Lorenz 诊断与三维相图输出

**目的**  
验证生成数据确实是 Lorenz 吸引子上的混沌轨线，并输出三维相空间轨线图。

**输入**

$$

\{\mathbf X^{(q)},\mathbf Z^{(q)}\}_{q=1}^R.

$$

**输出**

- 三维相空间轨线图；
- $xy,xz,yz$ 投影图；
- 坐标时间序列图；
- 状态范围表；
- 均值 / 方差 / 协方差表；
- finite-value 检查表；
- split 样本数量表。

**依赖**

- Sub-task C
- Sub-task D
- Sub-task E
- Sub-task F

**相关数学表达**

状态范围：

$$

x_{\min},x_{\max},
\qquad
y_{\min},y_{\max},
\qquad
z_{\min},z_{\max}.

$$

均值：

$$

\bar{\mathbf z}
=
\frac{1}{N}
\sum_{q,m}
\mathbf z_m^{(q)}.

$$

协方差：

$$

\mathbf C_z
=
\frac{1}{N-1}
\sum_{q,m}
(\mathbf z_m^{(q)}-\bar{\mathbf z})
(\mathbf z_m^{(q)}-\bar{\mathbf z})^\top.

$$

短期分离诊断可比较相近初值轨线：

$$

d_m
=
\|\mathbf x_m^{(q_1)}-\mathbf x_m^{(q_2)}\|_2.

$$

**诊断检查**

- 三维图应呈现典型双翼吸引子；
- $z$ 坐标应主要位于正值区域；
- 所有图对应 burn-in 后数据；
- 图中不混入被丢弃的 transient；
- 图表路径写入 manifest。

---

### 4. Directory and file plan

以下路径均以 `ODEs_dataset/` 为项目根目录。

#### 4.1 文档文件

| 路径 | 作用 |
|---|---|
| `docs/notes/mathematical explanation/lorenz63_math.md` | 保存 Lorenz ’63 数学说明书。 |
| `docs/notes/code explanation/lorenz63_task_plan.md` | 保存本次 Step 2 任务计划书。 |
| `docs/notes/file explanation/lorenz63_file_explanation.md` | 实现完成后说明新增文件、运行方式、输出位置。 |
| `docs/spec/object_registry.md` | 增加一条 Lorenz ’63 开发记录，说明新增对象、日期、版本和用途。 |
| `docs/spec/project_task_list.md` | 标记 Lorenz ’63 系统接入任务状态。 |

#### 4.2 配置文件

| 路径 | 作用 |
|---|---|
| `configs/systems/lorenz63_smoke.json` | smoke 级系统配置，小轨线数、短保存时间，用于快速检查。 |
| `configs/systems/lorenz63_standard.json` | 正式系统配置，标准参数、多初值、burn-in 后保存吸引子轨线。 |
| `configs/observations/lorenz63_full_state_identity.json` | 全状态恒等观测配置，声明 $\mathbf z=\mathbf x$。 |
| `configs/splits/lorenz63_split_initial_condition.json` | 初值泛化 split 配置，按整条轨线切 train / val / test。 |
| `configs/windows/lorenz63_one_step.json` | one-step 样本窗口配置。 |
| `configs/windows/lorenz63_rollout_short.json` | 短期 rollout 窗口配置，用于混沌短期预测。 |
| `configs/windows/lorenz63_rollout_medium.json` | 中期 rollout 窗口配置，用于误差增长分析。 |
| `configs/windows/lorenz63_statistics_window.json` | 统计窗口配置，用于长期统计诊断。 |
| `configs/tasks/lorenz63_one_step_forecast.json` | 一步预测任务配置。 |
| `configs/tasks/lorenz63_multi_step_rollout.json` | 多步 rollout 任务配置。 |
| `configs/tasks/lorenz63_long_time_statistics.json` | 长期统计任务配置。 |
| `configs/benchmarks/lorenz63_v1_core_smoke.json` | Lorenz ’63 smoke benchmark 组合配置。 |
| `configs/benchmarks/lorenz63_v1_core_standard.json` | Lorenz ’63 正式 benchmark 组合配置。 |
| `configs/releases/lorenz63_v1_core_release.json` | Lorenz ’63 加入 v1_core 的 release 清单。 |

#### 4.3 源码文件

| 路径 | 作用 |
|---|---|
| `src/dynamics/lorenz63.jl` | 定义 Lorenz ’63 系统本体、参数、右端函数、Jacobian 诊断和平衡点信息。 |
| `src/generators/lorenz63_generator.jl` | 根据配置生成 burn-in 后的 raw / processed 轨线。 |
| `src/diagnostics/lorenz63_diagnostics.jl` | 计算 Lorenz 专属数值诊断、统计诊断和 split / window 诊断。 |
| `src/diagnostics/lorenz63_plots.jl` | 组织三维相空间图、二维投影图、时间序列图的数据与导出逻辑。 |
| `src/registries/register_lorenz63.jl` | 将 Lorenz ’63 注册到系统表、任务表和 benchmark 表中。 |
| `src/manifests/lorenz63_manifest.jl` | 生成 Lorenz ’63 数据生成 manifest 和 release metadata。 |

#### 4.4 实验入口文件

| 路径 | 作用 |
|---|---|
| `experiments/smoke_tests/run_lorenz63_smoke.jl` | 最小端到端检查：系统积分、burn-in、全观测、split、窗口、三维图输出。 |
| `experiments/smoke_tests/inspect_lorenz63_standard_config.jl` | 不生成大数据，只检查正式配置、路径、样本数和诊断项是否完整。 |

正式数据生成不建议把核心逻辑写进实验脚本，而应由 `src/generators/lorenz63_generator.jl` 和正式配置驱动；实验入口只负责调用项目已有 runner。

#### 4.5 测试文件

| 路径 | 作用 |
|---|---|
| `test/unit/test_lorenz63_dynamics.jl` | 测试右端函数维度、参数校验、散度和平衡点诊断。 |
| `test/unit/test_lorenz63_observation.jl` | 测试全状态观测是否满足 $\mathbf Z=\mathbf X$。 |
| `test/integration/test_lorenz63_generation_smoke.jl` | 测试 smoke 端到端数据生成、split、window、manifest 和图表输出。 |
| `test/regression/test_lorenz63_smoke_regression.jl` | 固定 seed 下检查 smoke 数据规模、状态范围、图表路径和诊断表不发生非预期变化。 |

#### 4.6 数据输出文件

| 路径 | 作用 |
|---|---|
| `data/raw/v1_core/lorenz63/smoke/lorenz63_raw.jld2` | smoke 原始状态轨线。 |
| `data/raw/v1_core/lorenz63/standard/lorenz63_raw.jld2` | 正式原始状态轨线。 |
| `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_observed.jld2` | smoke 全状态观测轨线。 |
| `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_observed.jld2` | 正式全状态观测轨线。 |
| `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_split_I.json` | smoke 初值泛化 split 索引。 |
| `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_split_I.json` | 正式初值泛化 split 索引。 |
| `data/manifests/v1_core/lorenz63/smoke/lorenz63_manifest.json` | smoke 数据生成 manifest。 |
| `data/manifests/v1_core/lorenz63/standard/lorenz63_manifest.json` | 正式数据生成 manifest。 |
| `data/releases/v1_core/lorenz63/lorenz63_release_index.json` | release 索引，记录 raw、processed、split、manifest、reports 路径。 |

#### 4.7 报告输出文件

| 路径 | 作用 |
|---|---|
| `reports/v1_core/lorenz63_standard/plots/smoke/lorenz63_phase3d.png` | smoke 三维相空间轨线图。 |
| `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_phase3d.png` | 正式三维相空间轨线图。 |
| `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xy.png` | $xy$ 投影图。 |
| `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xz.png` | $xz$ 投影图。 |
| `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_yz.png` | $yz$ 投影图。 |
| `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_timeseries_xyz.png` | $x,y,z$ 时间序列图。 |
| `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_state_ranges.csv` | 状态范围表。 |
| `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_statistics.csv` | 均值、方差、协方差摘要。 |
| `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_split_window_counts.csv` | split 与窗口样本数量表。 |
| `reports/v1_core/lorenz63_standard/logs/smoke/run_lorenz63_smoke.log` | smoke 运行日志。 |
| `reports/v1_core/lorenz63_standard/logs/standard/generate_lorenz63_standard.log` | 正式生成日志。 |

---

### 5. Module / component responsibilities

#### `configs/systems/`

负责声明 Lorenz ’63 的数学参数、初值范围、时间设置、burn-in 和 solver 设置。

#### `configs/observations/`

负责声明全状态观测：

$$

\mathbf z=\mathbf x.

$$

#### `configs/splits/`

负责声明初值泛化 split：

$$

\mathcal Q_{\mathrm{train}},
\mathcal Q_{\mathrm{val}},
\mathcal Q_{\mathrm{test}}.

$$

#### `configs/windows/`

负责声明 one-step、rollout 和 statistics window。

#### `src/dynamics/`

只定义系统本体：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x).

$$

不负责保存数据、不负责绘图、不负责 split。

#### `src/generators/`

负责从配置生成轨线：

$$

\mathbf x_0
\rightarrow
\text{burn-in}
\rightarrow
\mathbf X
\rightarrow
\mathbf Z.

$$

#### `src/diagnostics/`

负责检查数据质量，包括范围、有限值、统计量和 Lorenz 吸引子形状。

#### `src/manifests/`

负责记录参数、时间步、轨线数、burn-in、保存路径、随机种子、solver 设置和诊断摘要。

#### `experiments/smoke_tests/`

只放最小入口，不放核心函数。

#### `reports/`

保存人工可读输出，尤其是三维相空间图和诊断表。

#### `test/`

保证 Lorenz 系统后续修改不会破坏维度、数据规模、split 协议和 smoke 输出。

---

### 6. Planned `##` sections

以下是计划中的 Julia 文件章节标题。这里只列结构，不写代码。

#### `src/dynamics/lorenz63.jl`

- `## Lorenz ’63 system identity and default parameters`
- `## Parameter validation rules`
- `## Lorenz ’63 vector field`
- `## Lorenz ’63 Jacobian for diagnostics`
- `## Equilibrium points under standard parameters`
- `## Dissipativity diagnostic metadata`
- `## System registration payload`

#### `src/generators/lorenz63_generator.jl`

- `## Load Lorenz ’63 generation configuration`
- `## Validate system, observation, split, and window compatibility`
- `## Build reproducible initial-condition ensemble`
- `## Integrate burn-in segments`
- `## Integrate retained attractor trajectories`
- `## Assemble raw trajectory objects`
- `## Apply full-state identity observation`
- `## Generate trajectory-level split indices`
- `## Generate one-step, rollout, and statistics windows`
- `## Save raw, processed, split, and manifest outputs`
- `## Return generation summary for diagnostics`

#### `src/diagnostics/lorenz63_diagnostics.jl`

- `## Finite-value and array-size checks`
- `## State range diagnostics`
- `## Burn-in acceptance diagnostics`
- `## Dissipativity metadata checks`
- `## Attractor statistics diagnostics`
- `## Split and window count diagnostics`
- `## Short-horizon separation diagnostics`
- `## Diagnostic table assembly`

#### `src/diagnostics/lorenz63_plots.jl`

- `## Select representative trajectories for plotting`
- `## Prepare three-dimensional phase-space trajectory data`
- `## Prepare two-dimensional projection data`
- `## Prepare coordinate time-series data`
- `## Export Lorenz ’63 attractor figures`
- `## Register plot paths in diagnostics summary`

#### `src/registries/register_lorenz63.jl`

- `## Register Lorenz ’63 as v1_core system`
- `## Register full-state observation option`
- `## Register initial-condition split option`
- `## Register Lorenz ’63 benchmark task bundle`
- `## Register release metadata entry`

#### `src/manifests/lorenz63_manifest.jl`

- `## Collect configuration metadata`
- `## Collect solver and sampling metadata`
- `## Collect burn-in and retained-trajectory metadata`
- `## Collect split and window metadata`
- `## Collect diagnostics and plot paths`
- `## Write Lorenz ’63 manifest object`

#### `experiments/smoke_tests/run_lorenz63_smoke.jl`

- `## Load smoke benchmark configuration`
- `## Run Lorenz ’63 smoke generation pipeline`
- `## Run smoke diagnostics`
- `## Export smoke phase-space figure`
- `## Print smoke summary`

#### `experiments/smoke_tests/inspect_lorenz63_standard_config.jl`

- `## Load standard Lorenz ’63 configuration bundle`
- `## Check consistency of system, observation, split, and window specs`
- `## Estimate output sizes before full generation`
- `## Check planned output paths`
- `## Print standard configuration inspection summary`

---

### 7. Data flow and dimensions

#### 7.1 Initial condition ensemble

初值集合：

$$

\mathbf X_0
=
\begin{bmatrix}
\mathbf x_0^{(1)}&
\mathbf x_0^{(2)}&
\cdots&
\mathbf x_0^{(R)}
\end{bmatrix}
\in\mathbb R^{3\times R}.

$$

每个初值：

$$

\mathbf x_0^{(q)}\in\mathbb R^3.

$$

#### 7.2 Burn-in

每条轨线先从原始初值积分到：

$$

\mathbf x_{\mathrm{burn}}^{(q)}
=
\Phi^{T_{\mathrm{burn}}}(\mathbf x_0^{(q)}).

$$

这些 burn-in 轨线默认不保存为正式 raw 数据。若为了调试保留，也只能保存在 manifest 或 diagnostic 中作为可选摘要，不进入正式 benchmark 样本。

#### 7.3 Retained raw trajectory

正式保存轨线：

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_0^{(q,\mathrm{keep})}&
\mathbf x_1^{(q,\mathrm{keep})}&
\cdots&
\mathbf x_M^{(q,\mathrm{keep})}
\end{bmatrix}
\in\mathbb R^{3\times(M+1)}.

$$

其中：

$$

M = T_{\mathrm{keep}}/\tau.

$$

所有轨线组合可以视为三阶数组：

$$

\mathcal X
\in
\mathbb R^{3\times(M+1)\times R}.

$$

但持久化时仍应保留 trajectory object，以便记录每条轨线的参数、初值、seed 和 metadata。

#### 7.4 Full-state observed trajectory

由于全状态观测：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

因此：

$$

\mathbf Z^{(q)}
\in
\mathbb R^{3\times(M+1)}.

$$

组合后：

$$

\mathcal Z
\in
\mathbb R^{3\times(M+1)\times R}.

$$

#### 7.5 One-step samples

对第 $q$ 条轨线：

$$

(\mathbf z_m^{(q)},\mathbf z_{m+1}^{(q)}),
\qquad
m=0,\dots,M-1.

$$

每条轨线 one-step 样本数：

$$

N_{\mathrm{1step}}^{(q)}=M.

$$

全部样本数：

$$

N_{\mathrm{1step}}=R M.

$$

每个输入 / 目标向量：

$$

\mathbf z_m,\mathbf z_{m+1}\in\mathbb R^3.

$$

#### 7.6 Rollout windows

给定 horizon $L$，窗口为：

$$

\mathbf W_s^{(q)}
=
\begin{bmatrix}
\mathbf z_s^{(q)}&
\mathbf z_{s+1}^{(q)}&
\cdots&
\mathbf z_{s+L}^{(q)}
\end{bmatrix}
\in\mathbb R^{3\times(L+1)}.

$$

每条轨线窗口数：

$$

N_{\mathrm{roll}}^{(q)}=M-L+1.

$$

#### 7.7 Statistics windows

统计窗口长度 $L_{\mathrm{stat}}$：

$$

\mathbf S_s^{(q)}
=
\begin{bmatrix}
\mathbf z_s^{(q)}&
\cdots&
\mathbf z_{s+L_{\mathrm{stat}}-1}^{(q)}
\end{bmatrix}
\in\mathbb R^{3\times L_{\mathrm{stat}}}.

$$

用于估计：

$$

\bar{\mathbf z},
\qquad
\mathbf C_z,
\qquad
\text{coordinate ranges},
\qquad
\text{projection distributions}.

$$

---

### 8. Package and documentation plan

以下只列包方向，不假设具体 API。

#### DifferentialEquations.jl / OrdinaryDiffEq.jl

**用途**

- 积分 Lorenz ’63 连续时间 ODE；
- 处理固定采样保存；
- 控制积分误差。

**需要查文档**

- 非刚性 ODE 推荐 solver；
- 如何在指定采样点保存解；
- 容差设置；
- 是否需要固定内部步长；
- 如何稳定记录 solver metadata。

#### Random / StableRNGs.jl

**用途**

- 初值采样；
- split 随机划分；
- smoke / standard 可复现。

**需要查文档**

- 稳定随机数对象的初始化方式；
- 多阶段随机种子管理；
- 如何避免不同模块共享全局随机状态导致不可复现。

#### LinearAlgebra / Statistics

**用途**

- 范数、均值、方差、协方差；
- Jacobian 诊断；
- 数据范围检查。

**需要查文档**

- 主要是标准库，确认即可。

#### JLD2 / HDF5 / Arrow

**用途**

- 保存 raw trajectory；
- 保存 processed trajectory；
- 保存可能较大的数组对象。

**需要查文档**

- 项目当前采用哪一种作为主数据格式；
- 如何保存 metadata；
- 如何保证跨版本读取稳定；
- 如何保存多个 trajectory object。

#### JSON3.jl / JSON.jl

**用途**

- 读取配置；
- 写入 manifest；
- 写入 split index；
- 写入 release index。

**需要查文档**

- 项目当前配置解析采用哪个包；
- 字段顺序与 pretty print；
- 数值类型保存策略。

#### Plots.jl 或 Makie.jl

**用途**

- 输出三维 Lorenz 吸引子图；
- 输出二维投影；
- 输出时间序列图。

**需要查文档**

- 当前项目绘图后端偏好；
- 三维线图保存方式；
- 静态图片导出格式；
- 论文级图和 smoke 图是否使用同一后端。

#### Test

**用途**

- 单元测试；
- 集成测试；
- 回归测试。

**需要查文档**

- 项目现有 test runner 组织方式；
- 如何把 smoke 数据生成纳入 CI 或本地 regression。

---

### 9. Debugging and inspection plan

#### 9.1 配置检查

打印或保存：

- `system_id`
- `state_dim`
- `parameter_names`
- `default_parameters`
- `dt`
- `burn_in_time`
- `keep_time`
- `trajectory_length`
- `num_trajectories`
- `solver_name`
- `abstol`
- `reltol`
- `seed`

#### 9.2 轨线维度检查

对每条轨线检查：

$$

\mathrm{size}(\mathbf X^{(q)})=(3,M+1),

$$

$$

\mathrm{size}(\mathbf Z^{(q)})=(3,M+1).

$$

#### 9.3 全状态观测检查

检查：

$$

\|\mathbf Z^{(q)}-\mathbf X^{(q)}\|_{\mathrm F}=0.

$$

#### 9.4 有限值检查

对全部轨线检查：

$$

\mathrm{isfinite}(x_m^{(q)}),
\quad
\mathrm{isfinite}(y_m^{(q)}),
\quad
\mathrm{isfinite}(z_m^{(q)}).

$$

不允许出现：

- NaN；
- Inf；
- missing；
- 维度不一致。

#### 9.5 状态范围检查

保存：

$$

x_{\min},x_{\max},
\qquad
y_{\min},y_{\max},
\qquad
z_{\min},z_{\max}.

$$

用于判断轨线是否爆炸或没有进入典型 Lorenz 吸引子。

#### 9.6 Burn-in 检查

记录：

- 原始初值 $\mathbf x_0^{(q)}$；
- burn-in 后初始保存点 $\mathbf x_{\mathrm{burn}}^{(q)}$；
- burn-in 后状态范围；
- 是否存在仍明显偏离吸引子的轨线。

#### 9.7 Split 检查

保存：

- train 轨线数；
- val 轨线数；
- test 轨线数；
- 各集合轨线 ID；
- 是否互不相交。

#### 9.8 Window 检查

保存：

- one-step 样本数；
- short rollout 窗口数；
- medium rollout 窗口数；
- statistics window 数；
- 每个窗口的 shape；
- 最大起点索引是否满足 $s+L\le M$。

#### 9.9 三维图检查

必须输出：

$$

(x(t),y(t),z(t))

$$

三维轨线图。

检查：

- 图中使用的是 burn-in 后数据；
- 图中轨线数量不要过多导致不可读；
- smoke 图和 standard 图分别保存；
- standard 图应有典型双翼结构；
- 图路径写入 manifest。

#### 9.10 混沌短期分离检查

选择两条相近或普通不同初值轨线，计算：

$$

d_m
=
\|\mathbf x_m^{(q_1)}-\mathbf x_m^{(q_2)}\|_2.

$$

不把它作为严格数值测试，只作为混沌敏感性的 sanity check。

---

### 10. Expected outputs

#### 10.1 数据文件

- `data/raw/v1_core/lorenz63/smoke/lorenz63_raw.jld2`
- `data/raw/v1_core/lorenz63/standard/lorenz63_raw.jld2`
- `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_observed.jld2`
- `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_observed.jld2`

#### 10.2 Split 与 manifest

- `data/processed/v1_core/lorenz63/smoke/full_state/lorenz63_split_I.json`
- `data/processed/v1_core/lorenz63/standard/full_state/lorenz63_split_I.json`
- `data/manifests/v1_core/lorenz63/smoke/lorenz63_manifest.json`
- `data/manifests/v1_core/lorenz63/standard/lorenz63_manifest.json`
- `data/releases/v1_core/lorenz63/lorenz63_release_index.json`

#### 10.3 图像

- `reports/v1_core/lorenz63_standard/plots/smoke/lorenz63_phase3d.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_phase3d.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xy.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_xz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_projection_yz.png`
- `reports/v1_core/lorenz63_standard/plots/standard/lorenz63_timeseries_xyz.png`

#### 10.4 表格

- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_state_ranges.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_statistics.csv`
- `reports/v1_core/lorenz63_standard/tables/standard/lorenz63_split_window_counts.csv`

#### 10.5 日志

- `reports/v1_core/lorenz63_standard/logs/smoke/run_lorenz63_smoke.log`
- `reports/v1_core/lorenz63_standard/logs/standard/generate_lorenz63_standard.log`

---

### 11. Failure points and debugging strategies

#### Failure 1：轨线爆炸或出现 NaN

**可能原因**

- solver 容差过松；
- 初值区域过大；
- 保存步长过大；
- 参数读取错误。

**排查策略**

- 检查参数是否为 $(10,28,8/3)$；
- 检查每条轨线的最大范数；
- 缩小初值范围；
- 减小采样步长；
- 提高 solver 精度。

---

#### Failure 2：三维相图不像 Lorenz 双翼吸引子

**可能原因**

- burn-in 时间不足；
- 图中画的是 transient；
- 参数 $\rho$ 读取错误；
- 状态维度顺序错误；
- 保存的是 $(t,x,y)$ 而不是 $(x,y,z)$。

**排查策略**

- 单独检查 burn-in 后第一点；
- 输出 $x,y,z$ 范围；
- 画 $xy,xz,yz$ 投影；
- 确认状态矩阵为 $3\times(M+1)$；
- 检查参数 manifest。

---

#### Failure 3：全状态观测不等于 raw state

**可能原因**

- observation pipeline 意外做了归一化；
- 添加了默认噪声；
- 读写时转置；
- processed 文件覆盖了旧数据。

**排查策略**

- 检查：

$$

\|\mathbf Z-\mathbf X\|_{\mathrm F}.

$$

- 检查 observation config；
- 确认 `noise_level = 0`；
- 确认 `normalization_policy` 不改变当前版本数据；
- 检查 raw 与 processed 的 shape。

---

#### Failure 4：split 泄漏

**可能原因**

- 先生成窗口再随机切分；
- split 单位不是 trajectory；
- 同一 trajectory ID 出现在多个集合。

**排查策略**

- 检查 train / val / test trajectory ID 交集；
- 在 split table 中保存每个 ID；
- 回归测试固定 seed 下的 split 结果。

---

#### Failure 5：窗口数量不对

**可能原因**

- $M$、$L$ 定义不一致；
- 起点索引多取或少取；
- 使用了 $M+1$ 作为一步样本数；
- window 跨越轨线边界。

**排查策略**

对每条轨线检查：

$$

N_{\mathrm{1step}}=M,

$$

$$

N_{\mathrm{roll}}=M-L+1.

$$

并检查所有窗口的最后索引满足：

$$

s+L\le M.

$$

---

#### Failure 6：长期 rollout 指标被误解

**可能原因**

Lorenz 是混沌系统，长期逐点误差变大是动力学性质，不一定代表数据错误。

**排查策略**

- 把逐点长期误差与短期 forecast horizon 区分；
- 同时报告长期统计；
- 输出吸引子图、边际统计、协方差；
- 不把长期逐点重合当作 Lorenz 的主要成功标准。

---

#### Failure 7：数据集工程与学习工程混在一起

**可能原因**

- 在 ODEs_dataset 中保存模型 checkpoint；
- 在 KoopmanLearning 中重新生成 raw Lorenz 数据；
- benchmark 配置和训练配置混放。

**排查策略**

- ODEs_dataset 只保存 raw、processed、splits、windows、manifests、reports；
- KoopmanLearning 只通过 `data/external/` 或 release 路径读取 ODEs_dataset；
- 不在本任务中产生模型、算子、谱、checkpoint 等学习产物。

---

### 12. Stop before code

到这里为止，本次 Lorenz ’63 的数学设定与代码工程计划已经完整。下一步若进入实现，应从配置文件和 `src/dynamics/lorenz63.jl` 开始，但本轮不写任何 Julia 代码。