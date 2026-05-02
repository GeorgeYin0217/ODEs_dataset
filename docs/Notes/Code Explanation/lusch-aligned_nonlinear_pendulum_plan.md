## Step 2：详细任务计划书 / implementation blueprint

### 1. Confirmed task summary

本次任务是在 `ODEs_dataset` 中新增一个 **Lusch 2018 对齐的非线性摆数据集对象**。系统固定为无阻尼、无外力、未线性化的 Hamiltonian pendulum，

$$

\dot x_1=x_2,\qquad \dot x_2=-\sin(x_1),

$$

并采用与贴出参数一致的采样设置

$$

\tau=0.02,\qquad t\in[0,1],\qquad T=51,

$$

初值区域为

$$

x_1(0)\in[-3.1,3.1],\qquad x_2(0)\in[-2,2],\qquad
H(\mathbf x_0)=\frac12x_2(0)^2-\cos x_1(0)<0.99.

$$

该对象的目标不是构造一个普通二维周期数据集，而是为后续 LKB2018 variable-$\mathbf K$ / continuous-spectrum 分支提供一个标准、干净、可复现实验底座，因为该摆系统的频率随能量连续变化，正是连续谱辅助网络设计的核心验证对象。fileciteturn5file0

在 ODEs_dataset 的总体系中，该对象应归入 `v1_plus` 的“摆系统家族 / pendulum family”，因为工程指南明确把“摆系统家族”放在扩展挑战集合，并要求新增系统至少提交 `SystemSpec`、`ObservationSpec`、`SplitSpec`、`TaskSpec`、smoke test 和 manifest 示例。fileciteturn4file0

---

### 2. Task decomposition

本任务分成 8 个子任务：

1. **系统注册与命名冻结**  
   确定 `system_id`、家族层级、难度档与文档登记。

2. **动力系统对象接入**  
   将摆方程、Hamiltonian、初值合法域与离散采样约定写入 `SystemSpec` 和动力系统模块。

3. **观测对象接入**  
   第一版仅接入全状态、恒等观测、无噪声版本。

4. **轨线生成与质量控制**  
   按能量约束采样初值，积分生成轨线，计算能量漂移与接受率诊断。

5. **split 构造**  
   先按轨线切分，再在各子集内部构造窗口，避免窗口泄漏。该规则是工程指南的硬约束。fileciteturn4file0

6. **window / task 构造**  
   生成 one-step、short rollout、medium rollout 与表示评测所需窗口对象。

7. **smoke 与 regression 测试**  
   用 small 配置跑通最小流水线，并冻结回归参考量。

8. **release 与报告产物组织**  
   将 raw / processed / manifests / plots / tables 放入工程规定目录，并补充 spec 文档登记。工程指南要求 raw、processed、manifest 分离保存。fileciteturn4file0

---

### 3. Sub-task specification

#### Sub-task A：系统注册与命名冻结
- **purpose**  
  固定新增对象在项目中的身份，避免后续同一系统重复命名。
- **input**  
  已确认的数学设定；工程指南中的系统注册分层。
- **output**  
  `system_id = nonlinear_pendulum_lusch2018`，归属 `family = pendulum_family`，层级为 `v1_plus`。fileciteturn4file0
- **dependency**  
  无。
- **relevant math**  
  $$

  \dot{\mathbf x}=\mathbf f(\mathbf x),\qquad
  \mathbf x\in\mathbb R^2.
  
$$
- **diagnostic checks**  
  名称唯一；与已有 simple pendulum / driven pendulum 不冲突；文档登记一致。

#### Sub-task B：SystemSpec 与动力学对象
- **purpose**  
  将摆系统的动力学与积分配置写成标准对象协议。
- **input**  
  系统方程、$\tau$、$T$、初值域、能量约束。
- **output**  
  完整 `SystemSpec` 与系统右端函数模块。
- **dependency**  
  A。
- **relevant math**  
  $$

  \dot x_1=x_2,\qquad \dot x_2=-\sin(x_1),
  \qquad
  H(\mathbf x)=\frac12x_2^2-\cos x_1.
  
$$
- **diagnostic checks**  
  `state_dim = 2`；`trajectory_length = 51`；合法域筛选确实实施；离散快照矩阵维度为 $2\times 51$。

#### Sub-task C：ObservationSpec 接入
- **purpose**  
  定义第一版观测链。
- **input**  
  状态轨线 $\mathbf X$。
- **output**  
  全状态无噪声观测对象 `ObservedTrajectory`。
- **dependency**  
  B。
- **relevant math**  
  $$

  U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,
  \qquad \mathbf z_m=\mathbf x_m.
  
$$
- **diagnostic checks**  
  `output_dim = 2`；`observation_matrix == state_matrix`；raw / processed 一致但分别存档。

#### Sub-task D：轨线生成与采样控制
- **purpose**  
  从矩形候选域中采样合法初值，生成轨线，并记录采样与积分质量。
- **input**  
  `SystemSpec`，轨线条数 $R$，随机种子。
- **output**  
  `RawTrajectory` 集合与采样统计表。
- **dependency**  
  B。
- **relevant math**  
  候选采样：
  $$

  x_1^{\rm raw}\sim\mathrm{Unif}[-3.1,3.1],\qquad
  x_2^{\rm raw}\sim\mathrm{Unif}[-2,2].
  
$$
  接受条件：
  $$

  H(\mathbf x_0)<0.99.
  
$$
- **diagnostic checks**  
  接受率；初值能量分布；最大能量漂移
  $$

  \Delta H_{\max}^{(q)}=\max_m |H(\mathbf x_m^{(q)})-H(\mathbf x_0^{(q)})|.
  
$$

#### Sub-task E：split 生成
- **purpose**  
  生成官方轨线级 `Split-I`。
- **input**  
  全部轨线 ID。
- **output**  
  train / val / test 轨线索引。
- **dependency**  
  D。
- **relevant math**  
  轨线集合分解：
  $$

  \mathcal R=\mathcal R_{\rm train}\cup \mathcal R_{\rm val}\cup \mathcal R_{\rm test},
  \qquad
  \mathcal R_i\cap\mathcal R_j=\varnothing.
  
$$
- **diagnostic checks**  
  先切轨线再派生窗口；不存在同轨线窗口泄漏。fileciteturn4file0

#### Sub-task F：window 与 task 派生
- **purpose**  
  派生 one-step 与 rollout 窗口，并绑定 benchmark task。
- **input**  
  `ObservedTrajectory` 与 `SplitSpec`。
- **output**  
  `OneStepSample`、`RolloutWindowSample`、表示评测窗口索引。
- **dependency**  
  E。
- **relevant math**  
  one-step：
  $$

  (\mathbf z_m,\mathbf z_{m+1});
  
$$
  rollout：
  $$

  (\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).
  
$$
- **diagnostic checks**  
  horizon 不越界；每个子集窗口计数正确；$L$ 与 $T=51$ 一致。

#### Sub-task G：pendulum 专属诊断
- **purpose**  
  生成该系统真正有辨识意义的诊断，而不只是一组通用误差。
- **input**  
  raw / processed / split / window 对象。
- **output**  
  能量分布图、相图、时间序列、能量漂移表。
- **dependency**  
  D–F。
- **relevant math**  
  $$

  H(\mathbf x)=\frac12x_2^2-\cos x_1.
  
$$
- **diagnostic checks**  
  低能、中能、高能样本都存在；轨线不跨 separatrix；不要退化成小振幅近线性样本。该点在 Lusch 对齐说明中被特别强调。fileciteturn5file0

#### Sub-task H：smoke、integration、regression 与 release
- **purpose**  
  保证新增对象进入长期可维护状态。
- **input**  
  全部上游对象。
- **output**  
  smoke 结果、回归参考值、manifest 示例、spec 更新。
- **dependency**  
  全部完成。
- **relevant math**  
  数据流水线遵循
  $$

  (\mathbf f,\mathbf x_0,\tau)\to \mathbf X\to \mathbf Z\to \text{splits}\to \text{windows}\to \text{tasks}.
  
$$
- **diagnostic checks**  
  small 配置几分钟内完成；回归量稳定；文件路径与 manifest 一致。fileciteturn4file0

---

### 4. Directory and file plan

下面列出本任务**建议新增或更新**的文件。路径全部映射到 `ODEs_dataset` 工程目录。目录蓝图与 `SystemSpec / ObservationSpec / SplitSpec / WindowSpec / TaskSpec / ReleaseManifest` 的分层，直接遵循 ODEs_dataset 工程指南。fileciteturn4file0

#### 文档与注册
- `docs/notes/mathematical explanation/nonlinear_pendulum_lusch2018_math.md`  
  已确认的数学说明书归档。
- `docs/notes/code explanation/nonlinear_pendulum_lusch2018_task_plan.md`  
  本次详细任务计划书归档。
- `docs/spec/object_registry.md`  
  更新：登记新增系统、日期、配置名、状态。
- `docs/spec/project_task_list.md`  
  更新：增加“Lusch-aligned nonlinear pendulum”任务条目。

#### 配置文件
- `configs/systems/v1_plus/nonlinear_pendulum_lusch2018_small.json`  
  small 难度，主要用于 smoke / regression。
- `configs/systems/v1_plus/nonlinear_pendulum_lusch2018_medium.json`  
  medium 难度，默认正式版本。
- `configs/systems/v1_plus/nonlinear_pendulum_lusch2018_large.json`  
  large 难度，压力测试与后续大规模算法对比。
- `configs/observations/pendulum_fullstate_identity_clean.json`  
  第一版观测链：全状态、恒等映射、无噪声。
- `configs/splits/pendulum_split_i_default.json`  
  轨线级 `Split-I`。
- `configs/windows/pendulum_one_step_lag1.json`  
  one-step 窗口。
- `configs/windows/pendulum_rollout_short_h10.json`  
  short rollout，建议 $L=10$。
- `configs/windows/pendulum_rollout_medium_h25.json`  
  medium rollout，建议 $L=25$。
- `configs/tasks/pendulum_one_step_forecast.json`  
  one-step 预测任务。
- `configs/tasks/pendulum_multi_step_rollout_short.json`  
  short rollout 任务。
- `configs/tasks/pendulum_multi_step_rollout_medium.json`  
  medium rollout 任务。
- `configs/tasks/pendulum_state_reconstruction.json`  
  状态/观测重构任务。
- `configs/tasks/pendulum_representation_evaluation.json`  
  表示评测任务，服务后续 latent-circle / energy-shell 对比。
- `configs/benchmarks/v1_plus/nonlinear_pendulum_lusch2018_baseline.json`  
  将 system / observation / split / windows / tasks 绑定成完整基准。
- `configs/releases/odes_dataset_v1_plus_pendulum_lusch2018_release.json`  
  发布清单条目。

#### 源码文件
- `src/dynamics/nonlinear_pendulum_lusch2018.jl`  
  定义系统右端、Hamiltonian、合法初值判定。
- `src/generators/generate_nonlinear_pendulum_lusch2018.jl`  
  按配置生成轨线与采样统计。
- `src/diagnostics/pendulum_family_diagnostics.jl`  
  计算能量漂移、接受率、能量分布、样本覆盖。
- `src/registries/register_pendulum_family.jl`  
  注册 system / observation / task ID。
- `src/manifests/pendulum_manifest_fields.jl`  
  pendulum 额外元数据字段组织；若已有通用 manifest 模块，则改为更新已有文件。
- `src/io/pendulum_report_writers.jl`  
  写出 pendulum 专属表格与图路径清单；若已有通用 writer，则改为更新已有文件。

#### 实验入口
- `experiments/smoke_tests/smoke_nonlinear_pendulum_lusch2018.jl`  
  small 配置 smoke。
- `experiments/baseline_forecasting/build_nonlinear_pendulum_lusch2018_release.jl`  
  medium / large 正式生成入口。
- `experiments/baseline_representation/diagnose_nonlinear_pendulum_lusch2018.jl`  
  生成相图、能量分布、样本覆盖诊断。

#### 测试文件
- `test/unit/test_nonlinear_pendulum_lusch2018_system.jl`
- `test/unit/test_pendulum_energy_filter.jl`
- `test/integration/test_nonlinear_pendulum_lusch2018_pipeline.jl`
- `test/regression/test_nonlinear_pendulum_lusch2018_regression.jl`

#### 生成数据与产物路径
- `data/raw/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/`
- `data/manifests/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/`
- `data/releases/v1_plus/nonlinear_pendulum_lusch2018/`
- `reports/tables/nonlinear_pendulum_lusch2018/`
- `reports/plots/nonlinear_pendulum_lusch2018/`
- `reports/logs/nonlinear_pendulum_lusch2018/`

---

### 5. Module / component responsibilities

- `src/dynamics/`  
  只负责
  $$

  \dot x_1=x_2,\quad \dot x_2=-\sin x_1
  
$$
  与 Hamiltonian
  $$

  H(\mathbf x)=\frac12x_2^2-\cos x_1
  
$$
  的数学定义，不负责 split、window 或文件保存。

- `src/generators/`  
  负责候选初值采样、能量过滤、数值积分、快照保存、轨线对象构造。

- `src/observations/`  
  第一版只挂接恒等观测，后续若加入角度子观测、线性混合或噪声观测，再在此扩展。工程指南要求动力系统与观测链解耦。fileciteturn4file0

- `src/datasets/`  
  负责 `RawTrajectory`、`ObservedTrajectory` 等数据对象与字段一致性。

- `src/splits/`  
  负责轨线级 `Split-I` 索引。

- `src/windows/`  
  负责 one-step 与 rollout 派生，不允许跨轨线。

- `src/tasks/`  
  负责把窗口对象映射到 forecast / reconstruction / representation 任务。

- `src/diagnostics/`  
  负责 pendulum 家族特有检查：能量守恒、样本覆盖、是否靠近 separatrix、是否退化成小振幅线性化样本。

- `src/manifests/`  
  负责记录系统参数、采样种子、求解器、公差、接受率、split 与 window 配置。

- `src/io/`  
  负责表格、图像、日志与 manifest 的路径组织与写出。

- `src/registries/`  
  负责把 `nonlinear_pendulum_lusch2018` 正式加入系统注册表，层级标记为 `v1_plus`。fileciteturn4file0

---

### 6. Planned `##` sections

下面只列 **Julia 文件** 的拟定 `##` 分节标题。

#### `src/dynamics/nonlinear_pendulum_lusch2018.jl`
- `## System identity and parameter policy`
- `## State variables and dimensional conventions`
- `## Vector field for the Lusch-aligned nonlinear pendulum`
- `## Hamiltonian energy function`
- `## Initial-condition admissibility test`
- `## Time-grid and trajectory-length conventions`

#### `src/generators/generate_nonlinear_pendulum_lusch2018.jl`
- `## Input configuration parsing`
- `## Candidate initial-condition sampling`
- `## Energy-based rejection filtering`
- `## Trajectory integration and snapshot extraction`
- `## RawTrajectory assembly`
- `## ObservedTrajectory assembly`
- `## Sampling statistics and acceptance-rate summary`

#### `src/diagnostics/pendulum_family_diagnostics.jl`
- `## Energy drift diagnostics`
- `## Initial-energy distribution diagnostics`
- `## Phase-portrait coverage diagnostics`
- `## Small-amplitude degeneracy checks`
- `## Separatrix proximity checks`
- `## Pendulum summary table construction`

#### `src/registries/register_pendulum_family.jl`
- `## Registered system identifiers`
- `## Registered observation identifiers`
- `## Registered split identifiers`
- `## Registered task identifiers`
- `## Registry validation hooks`

#### `src/manifests/pendulum_manifest_fields.jl`
- `## Required manifest keys for pendulum-family systems`
- `## Solver metadata fields`
- `## Sampling and acceptance metadata fields`
- `## Split and window metadata fields`
- `## Version-freeze fields`

#### `src/io/pendulum_report_writers.jl`
- `## Output path construction`
- `## Table export definitions`
- `## Plot export definitions`
- `## Log export definitions`
- `## Manifest export definitions`

#### `experiments/smoke_tests/smoke_nonlinear_pendulum_lusch2018.jl`
- `## Smoke configuration selection`
- `## System and observation loading`
- `## Trajectory generation`
- `## Split and window generation`
- `## Core diagnostics execution`
- `## Smoke summary output`

#### `experiments/baseline_forecasting/build_nonlinear_pendulum_lusch2018_release.jl`
- `## Release configuration selection`
- `## Reproducibility and seed control`
- `## Full trajectory generation`
- `## Processed dataset materialization`
- `## Split materialization`
- `## Window materialization`
- `## Manifest and release summary writing`

#### `experiments/baseline_representation/diagnose_nonlinear_pendulum_lusch2018.jl`
- `## Diagnostic dataset loading`
- `## Energy-shell selection`
- `## Phase portrait visualization`
- `## Time-series visualization`
- `## Energy-distribution visualization`
- `## Diagnostic report writing`

#### `test/unit/test_nonlinear_pendulum_lusch2018_system.jl`
- `## Vector-field consistency tests`
- `## Hamiltonian formula tests`
- `## State-dimension and output-shape tests`

#### `test/unit/test_pendulum_energy_filter.jl`
- `## Acceptance-condition tests`
- `## Boundary-case tests near H equals 0.99`
- `## Rejection-sampler consistency tests`

#### `test/integration/test_nonlinear_pendulum_lusch2018_pipeline.jl`
- `## End-to-end generation test`
- `## Raw and processed object consistency test`
- `## Split and window consistency test`
- `## Manifest completeness test`

#### `test/regression/test_nonlinear_pendulum_lusch2018_regression.jl`
- `## Frozen small-configuration reference checks`
- `## Trajectory-count regression checks`
- `## Energy-drift regression checks`
- `## Split-size regression checks`

---

### 7. Data flow and dimensions

第一版建议固定三档规模：

$$

R_{\rm small}=64,\qquad
R_{\rm medium}=512,\qquad
R_{\rm large}=2048.

$$

系统维数固定为

$$

d_x=2,\qquad d_z=2.

$$

每条轨线长度固定为

$$

T=51.

$$

于是单条 raw 轨线对象为

$$

\mathbf X^{(q)}\in\mathbb R^{2\times 51},
\qquad q=1,\dots,R.

$$

在全状态恒等观测下，

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}\in\mathbb R^{2\times 51}.

$$

#### one-step 样本
对单条轨线，可生成

$$

T-1=50

$$

个 one-step 样本：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad m=0,\dots,49.

$$

因此总样本数约为

$$

N_{\rm 1step}\approx 50R.

$$

#### short rollout 窗口
若 horizon 取

$$

L_{\rm short}=10,

$$

则单条轨线可生成

$$

51-(10+1)+1=41

$$

个窗口，每个窗口形状可记为：

$$

\mathbf z_{\rm start}\in\mathbb R^2,\qquad
\mathbf z_{\rm future}\in\mathbb R^{2\times 10}.

$$

#### medium rollout 窗口
若 horizon 取

$$

L_{\rm medium}=25,

$$

则单条轨线可生成

$$

51-(25+1)+1=26

$$

个窗口，每个窗口目标为

$$

\mathbf z_{\rm future}\in\mathbb R^{2\times 25}.

$$

#### split 后的数据流
先切轨线，再派生窗口：

$$

\{\mathbf X^{(q)}\}_{q=1}^R
\to
\{\mathbf Z^{(q)}\}_{q=1}^R
\to
(\mathcal R_{\rm train},\mathcal R_{\rm val},\mathcal R_{\rm test})
\to
\text{one-step / rollout samples}.

$$

small 推荐：

$$

80\%/10\%/10\%,

$$

medium / large 推荐：

$$

70\%/15\%/15\%.

$$

这样与工程指南的推荐比例一致。fileciteturn4file0

---

### 8. Package and documentation plan

这里只列包方向与需要核对的文档点，不预设 API。

- **DifferentialEquations.jl**  
  用于 ODE 数值积分。需要查官方文档确认：固定保存时刻、短时间 Hamiltonian 系统的合适求解器、误差容限、批量轨线生成策略。

- **Random**  
  用于种子与 rejection sampling。需要确认可复现采样策略与并行场景下的随机数管理。

- **LinearAlgebra**  
  用于范数、矩阵维度与误差量计算。

- **Statistics**  
  用于均值、方差、能量分布与 split 后统计摘要。

- **JSON3.jl 或 TOML**  
  用于读取 `SystemSpec / ObservationSpec / SplitSpec / WindowSpec / TaskSpec / BenchmarkSpec / ReleaseManifest` 类配置。需要查文档确认序列化策略。

- **JLD2.jl / HDF5.jl**  
  用于 `RawTrajectory`、`ObservedTrajectory` 与 manifest 持久化。需要确认矩阵、元信息与批量对象的安全写出格式。

- **DataFrames.jl + CSV.jl**  
  用于诊断表、split 表、统计摘要表输出。

- **Plots.jl 或 Makie.jl**  
  用于相图、时间序列图、能量分布图、能量漂移图。需要查文档确认批量保存与无交互模式。

重点文档检查顺序应是：先求解器与保存时刻，再配置读写，再数据持久化，再绘图输出。

---

### 9. Debugging and inspection plan

本任务的调试主线应围绕“动力学正确、采样正确、数据协议正确”三类检查，而不是先看漂亮图。

建议每次正式运行都打印或保存以下量：

#### 尺寸与对象协议
- 轨线条数 $R$
- `state_dim`
- `output_dim`
- 单条 `state_matrix` 尺寸
- 单条 `observation_matrix` 尺寸
- train / val / test 轨线数
- 各类窗口总数

#### 采样与能量
- rejection sampling 接受率
- 初值能量最小值、最大值、均值
- 初值能量分布分桶统计
- 靠近 separatrix 的样本比例，例如
  $$

  0.9 \le H(\mathbf x_0)<0.99
  
$$

#### 数值积分质量
- 每条轨线的 $\Delta H_{\max}^{(q)}$
- 全数据集的最大能量漂移
- 能量漂移均值与分位数
- 是否出现
  $$

  \max_m H(\mathbf x_m)\ge 1
  
$$
  的异常轨线

#### 图形检查
- 低能 / 中能 / 高能三类轨线的相图
- 单条典型轨线的 $(x_1(t),x_2(t))$ 时间序列
- 初值能量直方图
- 能量漂移箱线图或分布图

#### 回归冻结量
- small 配置下总轨线条数
- small 配置下接受率
- small 配置下最大能量漂移
- small 配置下 one-step / rollout 样本数

---

### 10. Expected outputs

本任务应产出以下文件族。

#### 数据对象
- `data/raw/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/...`
- `data/processed/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/...`

#### manifest 与发布信息
- `data/manifests/v1_plus/nonlinear_pendulum_lusch2018/<difficulty>/manifest.json`
- `data/releases/v1_plus/nonlinear_pendulum_lusch2018/release_index.json`

manifest 至少应记录：
- `system_id`
- `difficulty_level`
- `observation_id`
- `split_id`
- `window_ids`
- solver metadata
- seed
- acceptance rate
- energy drift summary
- generator commit hash

这些字段与 `ReleaseManifest` 的版本冻结思想保持一致。fileciteturn4file0

#### 表格
- `reports/tables/nonlinear_pendulum_lusch2018/initial_energy_summary.csv`
- `reports/tables/nonlinear_pendulum_lusch2018/energy_drift_summary.csv`
- `reports/tables/nonlinear_pendulum_lusch2018/split_window_summary.csv`

#### 图像
- `reports/plots/nonlinear_pendulum_lusch2018/phase_portrait_low_energy.png`
- `reports/plots/nonlinear_pendulum_lusch2018/phase_portrait_mid_energy.png`
- `reports/plots/nonlinear_pendulum_lusch2018/phase_portrait_high_energy.png`
- `reports/plots/nonlinear_pendulum_lusch2018/initial_energy_histogram.png`
- `reports/plots/nonlinear_pendulum_lusch2018/energy_drift_distribution.png`

#### 日志
- `reports/logs/nonlinear_pendulum_lusch2018/smoke_run.log`
- `reports/logs/nonlinear_pendulum_lusch2018/release_build.log`

#### 注册文档更新
- `docs/spec/object_registry.md`
- `docs/spec/project_task_list.md`

---

### 11. Failure points and debugging strategies

#### Failure 1：采样严重偏向小振幅区
- **symptom**  
  初值大多满足 $|x_1|\ll 1, |x_2|\ll 1$，数据看起来近似线性振子。
- **diagnosis**  
  查看初值能量直方图，若高能区样本很少，说明 rejection sampling 后的有效分布失衡。
- **strategy**  
  分层采样能量壳，或在 medium / large 配置中显式控制低能、中能、高能样本比例。

#### Failure 2：轨线跨越 separatrix
- **symptom**  
  某些轨线出现异常大角度翻转或
  $$

  H(\mathbf x_m)\ge 1.
  
$$
- **diagnosis**  
  检查能量漂移与高能初值分布。
- **strategy**  
  收紧公差；必要时把接受阈值从 $0.99$ 调低到更保守的调试值，但正式版本保持 Lusch 对齐阈值。fileciteturn5file0

#### Failure 3：raw / processed 对象字段不一致
- **symptom**  
  全状态观测下 `state_matrix` 与 `observation_matrix` 不一致，或尺寸转置错误。
- **diagnosis**  
  单元测试检查形状是否为 $2\times 51$，而不是 $51\times 2$。
- **strategy**  
  在对象构造处固定列快照约定，并在 integration test 中强制校验。工程指南已明确矩阵按列存储。fileciteturn4file0

#### Failure 4：window 越界或泄漏
- **symptom**  
  rollout 窗口数量错误，或 train / test 出现同轨线窗口。
- **diagnosis**  
  对每个 split 记录来源 `trajectory_id` 集合；检查是否交叉。
- **strategy**  
  强制执行“先切轨线，后切窗口”的流程。fileciteturn4file0

#### Failure 5：smoke 太慢
- **symptom**  
  small 配置都无法快速跑完。
- **diagnosis**  
  检查求解器、轨线条数、图像输出数量。
- **strategy**  
  small 只保存最必要图和表，限制 $R_{\rm small}$ 与日志体积。

#### Failure 6：后续下游算法评测不够用
- **symptom**  
  数据只适合 one-step，不适合 rollout 或 representation evaluation。
- **diagnosis**  
  检查是否只定义了 one-step window。
- **strategy**  
  在本任务里一次性把 one-step、short rollout、medium rollout 和 representation 任务都注册好，避免将来重做对象协议。

---

### 12. Stop before code

到此停止。  
本计划书已经把本次摆系统任务的子任务、路径、配置、模块职责、数据流、诊断与失败分析固定下来。现在不进入代码实现，等待你的单独编码请求。