## Step 2：Lorenz ’96 详细代码工程计划书

### 1. Confirmed task summary

已确认任务对象为 `v1_core` 中的 **Lorenz ’96**。它在整个 ODE 基准中的角色是“高维混沌 / 复杂传播”对象，强调高维、平移对称、参数主导和长期统计可比性，而不是再做一个低维混沌例子。fileciteturn5file0

本次确认设定：

- 系统：标准 40 维 Lorenz ’96；
- 参数：固定 forcing $F=8$；
- 观测：全状态观测；
- 噪声：无噪声；
- 数据策略：burn-in 后保存吸引子轨线；
- 第一版目标：先完成系统接入、轨线生成、全状态观测处理、轨线级存盘、轨线级 split、窗口派生、基础任务和正式诊断；
- 第一版不做：参数泛化、部分观测、非线性观测、带噪版本。

整体工程必须服从 ODEs_dataset 的固定流水线：

$$

(\mathbf f,\boldsymbol{\mu},\mathbf x_0,\tau)
\Longrightarrow
\{\mathbf x_m\}
\Longrightarrow
\{\mathbf z_m\}
\Longrightarrow
\text{split}
\Longrightarrow
\text{window}
\Longrightarrow
\text{task}
\Longrightarrow
\text{metric}

$$

并且系统新增时至少提交 `SystemSpec`、`ObservationSpec`、`SplitSpec`、`TaskSpec`、一份 smoke test 和一份 manifest 示例。fileciteturn4file0

---

### 2. Task decomposition

建议把本次任务拆成 10 个子任务：

1. **Lorenz ’96 数学对象注册**
2. **动力系统右端与循环索引实现规划**
3. **初值采样与 burn-in 策略规划**
4. **状态轨线生成与原始数据存盘规划**
5. **全状态无噪声观测链配置**
6. **处理后轨线对象与元信息写入规划**
7. **轨线级 split 规划**
8. **一步 / rollout / statistics 三类窗口规划**
9. **正式诊断与可视化规划**
10. **release 冻结与回归测试规划**

拆分依据是项目规范中“系统配置 → 轨线生成 → 观测处理 → 数据保存 → 切分与窗口 → 任务与评测”的固定目录与流程。fileciteturn4file0

---

### 3. Sub-task specification

#### 子任务 A：Lorenz ’96 系统对象注册

**purpose**  
把 Lorenz ’96 作为 `v1_core` 的标准系统对象正式接入注册层。

**input**  
系统名称、系统家族、状态维度 $K=40$、参数名 `F`、默认参数 $F=8$、时间步长、保存长度、积分器容差、seed 策略。

**output**  
一份正式 `SystemSpec` 配置对象。

**dependency**  
无，是入口对象。

**relevant math**  
$$

\dot x_i=(x_{i+1}-x_{i-2})x_{i-1}-x_i+F,\qquad i=1,\dots,K

$$
带周期边界。

**diagnostic checks**  
- `state_dim == 40`
- `parameter_names == ["F"]`
- `default_parameters["F"] == 8`
- 注册层能正确返回 `system_id`
- `family`、`v1_core` 标签和说明文本一致

---

#### 子任务 B：动力系统右端与循环索引实现规划

**purpose**  
明确如何以数值稳定、可测试的方式表达 Lorenz ’96 的环形耦合。

**input**  
状态向量 $\mathbf x\in\mathbb R^{40}$、参数 $F=8$。

**output**  
右端计算模块规划与边界索引测试计划。

**dependency**  
依赖 `SystemSpec`。

**relevant math**  
对每个 $i$：
$$

\dot x_i=(x_{i+1}-x_{i-2})x_{i-1}-x_i+F

$$
其中下标按模 $40$ 循环。

**diagnostic checks**  
- 边界索引 $i=1,2,40$ 的项是否和手算一致
- 常量状态 $\mathbf x = F\mathbf 1$ 时右端是否符合预期
- 输出维度是否始终为 $(40,)$
- 不允许出现索引越界或隐式转置

---

#### 子任务 C：初值采样与 burn-in 策略规划

**purpose**  
让轨线尽量来自吸引子附近，避免把明显的初始松弛段混入正式数据。

**input**  
初值域、随机种子、burn-in 时间长度或 burn-in 保存步数。

**output**  
`TrajectorySpec` 中的初值采样规则与 burn-in 规则。

**dependency**  
依赖 `SystemSpec`。

**relevant math**  
$$

\mathbf x_0 = F\mathbf 1 + \boldsymbol\epsilon

$$
其中 $\boldsymbol\epsilon$ 为小扰动。  
先积分到
$$

\widetilde{\mathbf x}_0

$$
再从 $\widetilde{\mathbf x}_0$ 保存正式轨线。

**diagnostic checks**  
- burn-in 前后均值和方差是否趋于稳定
- 不同轨线是否能进入同一统计稳态族
- 初值扰动尺度是否过小导致轨线过于相似
- 初值扰动尺度是否过大导致异常瞬态过长

---

#### 子任务 D：状态轨线生成与 raw 存盘规划

**purpose**  
得到只含状态的 `RawTrajectory` 对象，并与处理后数据解耦。

**input**  
`SystemSpec`、`TrajectorySpec`、采样步长 $\tau$、正式长度 $M+1$。

**output**  
状态矩阵
$$

\mathbf X^{(q)}\in\mathbb R^{40\times (M+1)}

$$
以及时间向量 `times`。

**dependency**  
依赖右端和 burn-in 规划。

**relevant math**  
$$

\mathbf x_{m+1}=\mathbf F^\tau(\mathbf x_m)

$$

**diagnostic checks**  
- `size(X) == (40, M+1)`
- `length(times) == M+1`
- 列表示快照，行表示变量
- raw 数据不混入观测层字段
- 各轨线 `trajectory_id` 唯一

---

#### 子任务 E：全状态无噪声观测链配置

**purpose**  
为第一版挂接最简单、最稳定的 `ObservationSpec`。

**input**  
状态轨线 $\mathbf X$。

**output**  
观测轨线
$$

\mathbf Z=\mathbf X

$$
及对应 `ObservationSpec`。

**dependency**  
依赖 raw 轨线生成。

**relevant math**  
$$

U=\mathcal I,\quad S=\mathcal I,\quad Z=\mathcal I,\quad \mathbf z_m=\mathbf x_m

$$

**diagnostic checks**  
- `output_dim == 40`
- `noise_model == none`
- `noise_level == 0`
- `observation_matrix` 与 `state_matrix` 数值一致
- 仍然保留观测链对象，而不是跳过该层

---

#### 子任务 F：processed 轨线与 manifest 写入规划

**purpose**  
生成 `ObservedTrajectory` 与 manifest，使数据可追踪、可冻结、可复现。

**input**  
`RawTrajectory`、`ObservationSpec`、系统配置、求解器元信息、seed 信息。

**output**  
`ObservedTrajectory`、单轨线 manifest、批次级 manifest、release manifest 示例。

**dependency**  
依赖 raw 轨线和观测配置。

**relevant math**  
$$

\mathbf Z=
\begin{bmatrix}
\mathbf z_1 & \cdots & \mathbf z_{M+1}
\end{bmatrix}\in\mathbb R^{40\times(M+1)}

$$

**diagnostic checks**  
- raw / processed / manifest 分离存放
- manifest 内系统参数、dt、burn-in、solver、公差、seed 完整
- `system_id`、`observation_id`、`trajectory_id` 可回溯
- 文件名与对象字段一致

---

#### 子任务 G：轨线级 split 规划

**purpose**  
构造 Lorenz ’96 第一版官方 split。

**input**  
轨线集合 $\{\mathbf Z^{(q)}\}_{q=1}^R$。

**output**  
至少一份 `SplitSpec`，建议先做 `Split-I`：固定参数、未见初值泛化。

**dependency**  
依赖批量轨线生成完成。

**relevant math**  
轨线编号集合划分为
$$

\mathcal R_{\text{train}},\mathcal R_{\text{val}},\mathcal R_{\text{test}}

$$

**diagnostic checks**  
- 切分单位是整条轨线，不是窗口
- train / val / test 轨线编号无重叠
- 比例符合预设
- 同一轨线不会跨 split
- 为未来 `Split-P` 预留 forcing $F$ 维度

---

#### 子任务 H：窗口对象规划

**purpose**  
把同一套轨线支持到三个标准任务层：one-step、rollout、statistics。

**input**  
已 split 的 `ObservedTrajectory`。

**output**  
`OneStepSample`、`RolloutWindowSample`、`StatisticsWindowSample`。

**dependency**  
依赖 split 完成。

**relevant math**  
一步样本：
$$

(\mathbf z_m,\mathbf z_{m+1})

$$

rollout 窗口：
$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L})

$$

statistics 窗口：
$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1})

$$

**diagnostic checks**  
- one-step 数量是否为每条轨线 $M$
- rollout 窗口数量是否为每条轨线 $M+1-L$
- statistics 窗口索引是否闭区间/半开区间一致
- 所有窗口只在各自 split 内部派生

---

#### 子任务 I：正式诊断与可视化规划

**purpose**  
验证 Lorenz ’96 数据不是“能跑就行”，而是具备可信的高维混沌统计结构。

**input**  
raw / processed 轨线与窗口对象。

**output**  
表格、图像、日志。

**dependency**  
依赖 processed 数据与窗口完成。

**relevant math**  
建议至少检查：

- 分量均值
$$

\mu_i=\frac1{M+1}\sum_{m=1}^{M+1}x_i(t_m)

$$

- 分量方差
$$

\sigma_i^2=\frac1M\sum_{m=1}^{M+1}(x_i(t_m)-\mu_i)^2

$$

- 空间平均能量型量
$$

E_m=\frac1{40}\sum_{i=1}^{40}x_i(t_m)^2

$$

- 协方差矩阵
$$

\mathbf C=\frac1M\sum_m(\mathbf x_m-\bar{\mathbf x})(\mathbf x_m-\bar{\mathbf x})^\top

$$

**diagnostic checks**  
- 代表坐标时间序列是否表现为混沌波动
- 空间—时间热图是否显示沿环传播的结构
- 各分量均值和方差是否大体接近，符合平移对称直觉
- 长轨线统计量在不同轨线之间是否相近
- 不以三维相图作为主诊断

---

#### 子任务 J：release 与测试规划

**purpose**  
把 Lorenz ’96 纳入正式可回归对象。

**input**  
系统配置、轨线生成结果、split、窗口、diagnostics、manifest。

**output**  
release 清单、smoke 脚本、integration / regression 测试对象。

**dependency**  
依赖前述所有任务。

**relevant math**  
无新增公式，重点是协议冻结。

**diagnostic checks**  
- smoke 版本可在短时间内跑通
- formal 版本输出全套产物
- 修改后回归测试能发现轨线数量、窗口数量和统计偏移异常
- 能稳定复现同一 release

---

### 4. Directory and file plan

以下路径按 `ODEs_dataset` 工程目录组织。目录划分和职责应保持“系统配置、观测配置、split、window、task、release、src 模块、data、experiments、reports、tests”分离。fileciteturn4file0

#### 文档与登记

- `docs/notes/mathematical explanation/lorenz96_math_note.md`  
  本对象的数学说明书。

- `docs/notes/code explanation/lorenz96_code_plan.md`  
  本次 Step 2 计划书。

- `docs/spec/object_registry.md`  
  追加一条 Lorenz ’96 接入登记。

- `docs/spec/project_task_list.md`  
  追加一条 Lorenz ’96 任务记录。

#### 配置层

- `configs/systems/lorenz96_k40_f8.json`  
  系统配置：`state_dim=40`、`F=8`、积分与保存参数、burn-in 参数、初值域。

- `configs/observations/lorenz96_fullstate_clean.json`  
  全状态、无噪声、恒等观测链配置。

- `configs/splits/lorenz96_split_i_default.json`  
  初值泛化切分配置，轨线级 70/15/15 或 80/10/10。

- `configs/windows/lorenz96_one_step.json`  
  一步样本窗口。

- `configs/windows/lorenz96_rollout_short.json`  
  短期 rollout 窗口。

- `configs/windows/lorenz96_rollout_long.json`  
  长期 rollout 窗口。

- `configs/windows/lorenz96_statistics.json`  
  长期统计窗口。

- `configs/tasks/lorenz96_one_step_forecast.json`  
  一步预测任务定义。

- `configs/tasks/lorenz96_multi_step_rollout.json`  
  多步 rollout 任务定义。

- `configs/tasks/lorenz96_long_time_statistics.json`  
  长期统计任务定义。

- `configs/benchmarks/lorenz96_v1_core_default.json`  
  把系统、观测、split、window、task 组合为一个完整 benchmark。

- `configs/releases/lorenz96_v1_core_release.json`  
  冻结发布配置。

#### 源码层

- `src/dynamics/lorenz96.jl`  
  Lorenz ’96 右端、系统元信息、循环索引辅助逻辑。

- `src/generators/generate_lorenz96.jl`  
  根据系统配置生成单条/多条轨线的生成器规划入口。

- `src/diagnostics/lorenz96_diagnostics.jl`  
  Lorenz ’96 特有的数据检查量和图表逻辑。

- `src/manifests/lorenz96_manifest.jl`  
  Lorenz ’96 相关 manifest 组织与校验。

- `src/registries/register_lorenz96.jl`  
  系统注册、默认 observation/split/task 注册。

#### 实验入口

- `experiments/smoke_tests/run_lorenz96_smoke.jl`  
  最小可运行测试。

- `experiments/baseline_forecasting/run_lorenz96_generate_formal.jl`  
  正式生成入口。

- `experiments/baseline_forecasting/run_lorenz96_diagnostics.jl`  
  正式诊断入口。

#### 数据与产物

- `data/raw/lorenz96/`  
  raw 状态轨线。

- `data/processed/lorenz96/`  
  观测链处理后轨线。

- `data/manifests/lorenz96/`  
  单轨线和批量 manifest。

- `data/releases/lorenz96/`  
  release 索引与冻结清单。

- `reports/tables/lorenz96/`  
  统计表、规模表、split 表。

- `reports/plots/lorenz96/`  
  时间序列图、空间—时间热图、均值/方差图、协方差图。

- `reports/logs/lorenz96/`  
  运行日志、诊断日志、异常记录。

#### 测试层

- `test/unit/test_lorenz96_rhs.jl`
- `test/unit/test_lorenz96_observation_identity.jl`
- `test/integration/test_lorenz96_smoke_pipeline.jl`
- `test/regression/test_lorenz96_reference_counts.jl`

---

### 5. Module / component responsibilities

#### `src/dynamics/`
负责 Lorenz ’96 数学本体，不负责文件写入、不负责 split、不负责图像输出。

#### `src/observations/`
复用已有通用恒等观测逻辑，不在系统模块里硬编码“$\mathbf z=\mathbf x$”。

#### `src/generators/`
负责把系统配置、观测配置和初值策略串起来，生成 raw 和 processed 轨线。

#### `src/datasets/`
负责 `RawTrajectory`、`ObservedTrajectory` 等统一对象组织，不混入系统特例。

#### `src/splits/`
负责整条轨线级切分，不允许从窗口层直接打乱。

#### `src/windows/`
负责 one-step、rollout、statistics 窗口派生。

#### `src/tasks/`
负责把窗口和指标绑定成标准任务对象。

#### `src/diagnostics/`
负责 Lorenz ’96 的统计检查和可视化，不负责修改原始数据。

#### `src/manifests/`
负责写入与验证 release 级复现元信息。

#### `src/io/`
负责路径管理、数据读写和命名一致性。

#### `src/registries/`
负责让 Lorenz ’96 作为 `v1_core` 正式可见。项目规范明确 Lorenz ’96 属于 `v1_core` 主集合。fileciteturn4file0

---

### 6. Planned `##` sections

下面给出每个计划 Julia 文件内部应有的 `##` 段落标题。只列结构，不写代码。

#### `src/dynamics/lorenz96.jl`

- `## Lorenz96 system metadata`
- `## State dimension and forcing parameter validation`
- `## Cyclic index convention`
- `## Lorenz96 right-hand side`
- `## Equilibrium and reference-state helpers`
- `## Sanity checks for boundary indices`

#### `src/generators/generate_lorenz96.jl`

- `## Load Lorenz96 system specification`
- `## Sample initial conditions around forced background state`
- `## Integrate burn-in segment`
- `## Integrate production trajectory`
- `## Assemble RawTrajectory object`
- `## Apply observation pipeline`
- `## Assemble ObservedTrajectory object`
- `## Write raw processed and manifest outputs`

#### `src/diagnostics/lorenz96_diagnostics.jl`

- `## Validate trajectory array shapes`
- `## Compute coordinate-wise summary statistics`
- `## Compute spatial mean variance and energy-like quantities`
- `## Compute covariance diagnostics`
- `## Build representative time-series plots`
- `## Build space-time heatmap plots`
- `## Summarize cross-trajectory statistical stability`
- `## Write diagnostics tables and logs`

#### `src/manifests/lorenz96_manifest.jl`

- `## Lorenz96 manifest schema`
- `## Capture solver sampling and burn-in metadata`
- `## Capture system observation split and window identifiers`
- `## Validate reproducibility-critical fields`
- `## Export release-ready manifest records`

#### `src/registries/register_lorenz96.jl`

- `## Register Lorenz96 system object`
- `## Register default clean full-state observation`
- `## Register default split and task bundles`
- `## Register Lorenz96 benchmark entry`

#### `experiments/smoke_tests/run_lorenz96_smoke.jl`

- `## Load smoke configuration`
- `## Generate a minimal Lorenz96 dataset sample`
- `## Run shape and manifest sanity checks`
- `## Run minimal diagnostics`
- `## Write smoke outputs and summary log`

#### `experiments/baseline_forecasting/run_lorenz96_generate_formal.jl`

- `## Load formal Lorenz96 benchmark configuration`
- `## Generate full trajectory ensemble`
- `## Build splits and windows`
- `## Save release candidates`
- `## Write generation summary`

#### `experiments/baseline_forecasting/run_lorenz96_diagnostics.jl`

- `## Load processed Lorenz96 release data`
- `## Run formal diagnostics suite`
- `## Save tables plots and logs`
- `## Validate release readiness`

---

### 7. Data flow and dimensions

#### 7.1 单条轨线

单条状态轨线：

$$

\mathbf X^{(q)}=
\begin{bmatrix}
\mathbf x_1^{(q)} & \cdots & \mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in\mathbb R^{40\times(M+1)}

$$

全状态观测下：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in\mathbb R^{40\times(M+1)}

$$

时间向量：

$$

\mathbf t^{(q)}\in\mathbb R^{M+1}

$$

#### 7.2 多轨线集合

若共有 $R$ 条轨线，则数据集合为

$$

\left\{\mathbf X^{(q)},\mathbf Z^{(q)}\right\}_{q=1}^{R}

$$

按轨线编号切分为：

$$

\mathcal R_{\text{train}},\quad
\mathcal R_{\text{val}},\quad
\mathcal R_{\text{test}}

$$

#### 7.3 一步样本

对第 $q$ 条轨线第 $m$ 个一步样本：

$$

\mathbf z_m^{(q)}\in\mathbb R^{40},\qquad
\mathbf z_{m+1}^{(q)}\in\mathbb R^{40}

$$

样本数每条轨线为 $M$。

#### 7.4 rollout 窗口

若 horizon 为 $L$，则窗口对象包含：

- `z_start`：$\mathbf z_s^{(q)}\in\mathbb R^{40}$
- `z_future`：长度为 $L$ 的未来序列

也可组织成矩阵：

$$

\mathbf Z^{(q)}_{s:s+L}
\in \mathbb R^{40\times(L+1)}

$$

每条轨线可产生

$$

M+1-L

$$

个 rollout 起点。

#### 7.5 statistics 窗口

统计窗口段为

$$

\mathbf Z^{(q)}_{s:s+L-1}\in\mathbb R^{40\times L}

$$

用于均值、协方差、频谱或时间平均的局部统计估计。

#### 7.6 诊断量维度

- 坐标均值向量：$\bar{\mathbf x}\in\mathbb R^{40}$
- 坐标方差向量：$\boldsymbol\sigma^2\in\mathbb R^{40}$
- 协方差矩阵：$\mathbf C\in\mathbb R^{40\times40}$
- 能量型时间序列：$\mathbf E\in\mathbb R^{M+1}$

---

### 8. Package and documentation plan

这里只列包方向与文档检查项，不预设具体 API。

#### `OrdinaryDiffEq.jl` / `DifferentialEquations.jl`

**why**  
Lorenz ’96 连续时间 ODE 数值积分。

**expected functionality**  
- ODE 问题定义
- 自适应或固定步积分
- 按给定采样时刻保存状态
- 容差控制

**must check in official docs**  
- 保存步长与内部积分步长的区别
- burn-in 分段积分是否可复用终点状态
- 高维系统保存输出的内存策略
- solver 选择与混沌系统精度控制

#### `LinearAlgebra`

**why**  
协方差、范数、矩阵检查。

**expected functionality**  
- 矩阵乘法
- 对称矩阵处理
- 特征值或奇异值基础分析

**must check**  
无特殊陌生 API，但要确认数组布局和转置约定。

#### `Statistics`

**why**  
均值、方差、协方差等统计量。

**expected functionality**  
- 沿指定维度计算 summary statistics

**must check**  
- 沿时间维还是状态维计算
- 返回形状是否与预期一致

#### `Random`

**why**  
初值扰动、split 随机种子、可复现性。

**must check**  
- 随机种子在多轨线生成中的传播方式

#### `JLD2.jl` 或等价数据格式包

**why**  
保存 raw / processed / manifest 对象。

**expected functionality**  
- 数组、字典、结构化元信息持久化

**must check**  
- 复现性字段如何稳定保存
- 大矩阵写入性能
- 路径组织是否便于 release 管理

#### 绘图库，如 `Plots.jl` 或 `Makie.jl`

**why**  
正式诊断图。

**expected functionality**  
- 时间序列图
- 热图
- 统计图
- 批量保存图像

**must check**  
- 热图维度方向
- 批量图像输出与文件命名
- 大尺寸图像保存性能

---

### 9. Debugging and inspection plan

Lorenz ’96 第一版最应强制检查的量如下。

#### 数组与对象层

- 每条轨线 `state_matrix` 形状是否为 `(40, M+1)`
- `observation_matrix` 是否同形
- `times` 长度是否为 `M+1`
- 各对象的 `system_id`、`observation_id`、`trajectory_id` 是否一致

#### 右端函数层

- 对随机状态向量的输出长度是否为 40
- 边界索引项是否通过手算例子
- 周期索引是否不依赖临时拼接造成额外分配

#### burn-in 与统计层

- burn-in 前后前几维时间序列是否明显改变
- burn-in 后各轨线均值、方差是否在合理范围
- 不同轨线间统计量差异是否异常大

#### split 与窗口层

- train / val / test 轨线数
- 每个 split 内 one-step 样本数
- 每个 split 内 rollout 窗口数
- statistics 窗口数与 horizon 是否匹配

#### 诊断图层

- 代表分量时间序列图
- 空间—时间热图
- 坐标均值柱状图或折线图
- 坐标方差图
- 协方差热图
- 每轨线平均能量随时间图

#### 日志层

- 系统参数 $K,F$
- dt、保存长度、burn-in 长度
- solver 名称、容差
- 轨线条数、split 比例、窗口 horizon
- 原始文件、处理文件、manifest、图像、表格输出路径

---

### 10. Expected outputs

按照项目规范，Lorenz ’96 第一版建议至少产生以下输出。

#### 数据对象

- `RawTrajectory` 集合
- `ObservedTrajectory` 集合
- 官方 split 索引
- one-step 窗口
- rollout 窗口
- statistics 窗口
- 单轨线与批次级 manifest
- release manifest

#### 表格

保存到 `reports/tables/lorenz96/`：

- `trajectory_inventory.csv`：轨线条数、长度、参数、seed
- `split_summary.csv`：train/val/test 轨线与窗口数量
- `coordinate_statistics.csv`：40 个分量的均值、方差、最小值、最大值
- `energy_statistics.csv`：能量型量统计
- `covariance_summary.csv`：协方差摘要或主对角信息

#### 图像

保存到 `reports/plots/lorenz96/`：

- `representative_coordinates_timeseries.png`
- `space_time_heatmap.png`
- `coordinate_mean_plot.png`
- `coordinate_variance_plot.png`
- `covariance_heatmap.png`
- `trajectory_energy_plot.png`

#### 日志

保存到 `reports/logs/lorenz96/`：

- smoke 运行日志
- formal 运行日志
- manifest 验证日志
- 诊断摘要日志

#### release

保存到 `data/releases/lorenz96/`：

- 冻结配置副本
- release manifest
- raw / processed 文件索引
- 版本说明

---

### 11. Failure points and debugging strategies

#### 失败点 1：循环边界写错

**symptom**  
轨线看似正常，但统计结构很怪；不同坐标均值/方差差异极大。

**strategy**  
- 单独测试 $i=1,2,40$ 三个边界项
- 对小维度人工手算状态做 RHS 对比
- 检查是否用了错误的前后邻居顺序

#### 失败点 2：矩阵维度方向颠倒

**symptom**  
后续窗口生成和统计都出现 shape mismatch。

**strategy**  
- 强制每条轨线打印 `size(X)`
- 统一采用“列是时间快照”的项目约定
- 所有统计函数明确说明沿哪一维求值

#### 失败点 3：burn-in 不足

**symptom**  
不同轨线的均值和方差严重依赖初值，正式统计不稳定。

**strategy**  
- 比较 burn-in 前后统计量
- 增加 burn-in 长度并复查
- 检查初值扰动是否过大

#### 失败点 4：采样步长不合适

**symptom**  
热图出现不自然的锯齿、时间序列过粗或数据量爆炸。

**strategy**  
- 分离“内部积分精度”和“外部保存间隔”
- 先用 smoke 版比较多组 dt
- 固定 small / medium / large 三档规模，不临时改动。Lorenz ’96 也应遵循系统对象文档中建议的三档难度组织。fileciteturn5file0

#### 失败点 5：不同轨线过于相似

**symptom**  
split 看似有很多轨线，但实际有效多样性不足。

**strategy**  
- 扩大初值扰动族
- 增加不同 seed
- 检查 burn-in 后是否所有轨线落到几乎相同的相位片段

#### 失败点 6：manifest 不完整

**symptom**  
后续无法复现 release。

**strategy**  
- 把 solver、公差、dt、burn-in、seed、config 路径列为必填
- release 前做 manifest 完整性检查
- 修改字段时同步更新回归测试

#### 失败点 7：把轨线级 split 错做成窗口级 split

**symptom**  
测试误差异常乐观，长期预测不可信。

**strategy**  
- 先生成 split，再派生窗口
- 检查同一 `trajectory_id` 不会出现在多个 split
- 对窗口对象回溯其来源轨线编号

---

### 12. Stop before code

以上是 Lorenz ’96 在 `ODEs_dataset` 中的详细代码工程计划书。这里到此为止，只做任务分解、文件规划、数据流、诊断和调试策略说明，不写代码。

等你下一步单独发出实现请求后，再进入具体 Julia 编码。