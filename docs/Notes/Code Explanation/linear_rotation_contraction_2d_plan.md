下面给出 **Step 2：旋转–收缩线性系统的代码工程计划书**。这是实现规划，不包含 Julia 代码。

本计划严格按 `ODEs_dataset` 的协议来组织：数据集工程应被视为“协议库 + 数据工厂 + 评测基座”，其固定流水线是  
$$

(\mathbf f,\boldsymbol{\mu},\mathbf x_0,\tau)
\rightarrow
\{\mathbf x_m\}
\rightarrow
\{\mathbf z_m\}
\rightarrow
\text{split}
\rightarrow
\text{window}
\rightarrow
\text{task}
\rightarrow
\text{metric report}.

$$
同时，动力系统与观测链必须解耦，`configs/` 只保存声明式配置，`src/` 保存可复用源码，`experiments/` 只放实验入口，`data/raw`、`data/processed`、`data/manifests` 分离保存。fileciteturn7file0

# 1. Confirmed task summary

本次任务是在 `ODEs_dataset` 中新增内部单元测试系统：

```text
system_id = linear_rotation_contraction_2d
family    = unit_internal
```

数学系统为

$$

\dot{\mathbf x}
=
\mathbf A\mathbf x,
\qquad
\mathbf x\in\mathbb R^2,

$$

其中

$$

\mathbf A
=
\begin{bmatrix}
-\gamma & -\omega\\
\omega & -\gamma
\end{bmatrix}.

$$

默认参数：

$$

\gamma=0.15,
\qquad
\omega=2\pi,
\qquad
\tau=0.01.

$$

离散推进使用解析矩阵：

$$

\mathbf F^\tau
=
e^{-\gamma\tau}
\begin{bmatrix}
\cos(\omega\tau) & -\sin(\omega\tau)\\
\sin(\omega\tau) & \cos(\omega\tau)
\end{bmatrix}.

$$

本系统主要测试：

1. 二维实状态中的复共轭谱；
2. 收缩率是否等于 \(e^{-\gamma\tau}\)；
3. 单步旋转角是否等于 \(\omega\tau\)；
4. DMD / EDMD / Koopman 方法后续能否恢复  
   $$

   \lambda_\pm=e^{(-\gamma\pm i\omega)\tau}.
   
$$

该系统属于内部单元测试层。项目系统对象规划中也建议长期保留“线性对角、旋转–收缩、Jordan / 非正规”三类内部系统，用于暴露谱结构 bug，而不是作为公开 leaderboard 主系统。fileciteturn7file1

# 2. Task decomposition

本次实现分为 9 个子任务。

## 2.1 新增系统配置

目的：用配置文件声明系统参数、初值策略、时间步长、轨线长度、随机种子和精确推进方式。

输入：数学规划中的 \(\gamma,\omega,\tau,M,R\)。

输出：`SystemSpec` 配置文件。

依赖：无。

核心表达式：

$$

\mathbf A(\gamma,\omega)
=
\begin{bmatrix}
-\gamma & -\omega\\
\omega & -\gamma
\end{bmatrix},
\qquad
\mathbf F^\tau=e^{\mathbf A\tau}.

$$

诊断检查：

- `state_dim = 2`；
- \(\gamma>0\)；
- \(\omega\neq 0\)；
- `dt > 0`；
- `trajectory_length = M` 为正整数；
- 初值半径区间合法。

---

## 2.2 新增动力系统模块

目的：在 `src/dynamics/` 中实现旋转–收缩线性系统的数学对象。

输入：`SystemSpec` 中的参数。

输出：

- 连续矩阵 \(\mathbf A\in\mathbb R^{2\times2}\)；
- 离散推进矩阵 \(\mathbf F^\tau\in\mathbb R^{2\times2}\)；
- 真值连续谱 \(\nu_\pm\)；
- 真值离散谱 \(\lambda_\pm\)。

依赖：2.1。

核心表达式：

$$

\nu_\pm=-\gamma\pm i\omega,
\qquad
\lambda_\pm=e^{\nu_\pm\tau}.

$$

诊断检查：

$$

|\lambda_\pm|=e^{-\gamma\tau},
\qquad
\arg(\lambda_\pm)=\pm\omega\tau.

$$

---

## 2.3 新增解析轨线生成流程

目的：不用数值 ODE solver，优先用闭式离散推进生成轨线，避免把积分误差混入单元测试。

输入：

$$

\mathbf x_0^{(q)}\in\mathbb R^2,
\qquad
q=1,\dots,R.

$$

输出：

$$

\mathbf X^{(q)}
=
[\mathbf x_1^{(q)},\dots,\mathbf x_{M+1}^{(q)}]
\in\mathbb R^{2\times(M+1)}.

$$

依赖：2.1、2.2。

核心表达式：

$$

\mathbf x_{m+1}^{(q)}
=
\mathbf F^\tau \mathbf x_m^{(q)}.

$$

诊断检查：

$$

\max_{q,m}
\left\|
\mathbf x_{m+1}^{(q)}-\mathbf F^\tau\mathbf x_m^{(q)}
\right\|_2

$$

应接近机器精度量级。

---

## 2.4 新增观测配置

目的：通过 `ObservationSpec` 将状态轨线转换为算法输入轨线。数据集指南要求动力系统与观测链解耦，算法输入统一记为 \(\mathbf z_m\)，而不默认等于状态 \(\mathbf x_m\)。fileciteturn7file0

第一版保留两个观测：

### clean full-state

$$

\mathbf z_m=\mathbf x_m.

$$

### noisy full-state

$$

\mathbf z_m=\mathbf x_m+\boldsymbol\varepsilon_m,
\qquad
\boldsymbol\varepsilon_m\sim\mathcal N(0,\sigma^2\mathbf I_2).

$$

输入：`RawTrajectory`。

输出：`ObservedTrajectory`。

依赖：2.3。

诊断检查：

- clean 模式下 \(\mathbf Z=\mathbf X\)；
- noisy 模式下 `observation_matrix` 与 `state_matrix` 维度一致；
- 噪声均值、标准差接近配置值；
- 噪声 seed 可复现。

---

## 2.5 新增 split 配置

目的：实现 `Split-I` 初值泛化。数据集规范要求先按整条轨线切分，再在各自集合内部生成窗口，不能把同一条轨线的相邻窗口打散到 train/test。fileciteturn7file0

输入：轨线编号集合

$$

\mathcal R=\{1,\dots,R\}.

$$

输出：

$$

\mathcal R_{\rm train},
\quad
\mathcal R_{\rm val},
\quad
\mathcal R_{\rm test}.

$$

默认比例：

$$

70\%/15\%/15\%.

$$

依赖：2.3、2.4。

诊断检查：

- 三个集合互不相交；
- 并集等于全部轨线编号；
- 切分单位是 `trajectory_id`，不是窗口编号；
- 同一条轨线不会同时出现在 train 和 test。

---

## 2.6 新增 window 配置

目的：从观测轨线内部生成标准窗口对象。

窗口一：one-step

$$

(\mathbf z_m,\mathbf z_{m+1}).

$$

窗口二：rollout

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

建议 horizon：

$$

L\in\{10,50,100\}.

$$

其中 \(L=100\) 对应默认参数下约一个完整周期。

输入：

$$

\mathbf Z^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

输出：

- `OneStepSample`；
- `RolloutWindowSample`。

依赖：2.5。

诊断检查：

- one-step 样本数为每条轨线 \(M\)；
- rollout horizon \(L\) 的起点数为 \(M+1-L\)；
- 每个窗口只来自单条轨线；
- train/val/test 内部分别生成窗口，不跨 split。

---

## 2.7 新增 benchmark task 配置

目的：让本系统同时服务三类最小任务：

```text
one_step_forecast
multi_step_rollout
spectrum_recovery_diagnostic
```

输入：

- one-step window；
- rollout window；
- 系统真值谱元信息。

输出：任务配置文件与 smoke benchmark 配置。

依赖：2.6。

诊断检查：

- 每个 task 引用的 `window_id` 存在；
- 每个 task 引用的 `metric_id` 存在；
- 谱诊断 task 能读取真值 \(\lambda_\pm\)。

---

## 2.8 新增诊断与报告

目的：生成系统级 sanity check，不训练任何模型。

核心诊断：

### 半径收缩

$$

r_m=\|\mathbf x_m\|_2,
\qquad
\frac{r_{m+1}}{r_m}
\approx
e^{-\gamma\tau}.

$$

### 角度增量

$$

\Delta\theta_m
=
\operatorname{unwrap}(\theta_{m+1}-\theta_m)
\approx
\omega\tau.

$$

### 离散谱

$$

\operatorname{eig}(\mathbf F^\tau)
\approx
\{e^{(-\gamma+i\omega)\tau},e^{(-\gamma-i\omega)\tau}\}.

$$

### rollout 精度

$$

\mathbf x_{m+\ell}
\approx
(\mathbf F^\tau)^\ell \mathbf x_m.

$$

输出：

- 诊断表；
- 轨线相图；
- 半径衰减图；
- 离散谱图；
- smoke 日志。

依赖：2.1–2.7。

---

## 2.9 新增测试

目的：保证以后修改生成器、观测链、split/window 协议时，不破坏该内部系统。

测试层次：

1. unit test：检查 \(\mathbf A,\mathbf F^\tau,\lambda_\pm\)；
2. integration test：检查完整生成流水线；
3. regression test：固定 seed 下比较参考 manifest 与诊断统计。

依赖：全部前置任务。

# 3. Directory and file plan

下面列出本次计划涉及的文件。路径均以项目根目录 `ODEs_dataset/` 为基准。

## 3.1 配置文件

### `configs/systems/unit_internal/linear_rotation_contraction_2d.json`

角色：系统配置。

内容职责：

- `system_id`；
- `family = unit_internal`；
- `state_dim = 2`；
- 参数名 `gamma`, `omega`；
- 默认参数；
- 初值采样策略；
- `dt`；
- `trajectory_length`；
- `num_trajectories`；
- `solver_name = exact_discrete_linear`；
- seed 策略；
- 真值谱是否写入 manifest。

---

### `configs/observations/unit_internal/full_state_identity_clean.json`

角色：全状态无噪声观测配置。

数学含义：

$$

U=\mathcal I,
\qquad
S=\mathcal I,
\qquad
Z=\mathcal I,
\qquad
\mathbf z_m=\mathbf x_m.

$$

---

### `configs/observations/unit_internal/full_state_identity_noise_1e-3.json`

角色：全状态低噪声观测配置。

数学含义：

$$

\mathbf z_m=\mathbf x_m+\boldsymbol\varepsilon_m.

$$

用于后续噪声鲁棒性 smoke test，但第一轮可以只跑 clean。

---

### `configs/splits/unit_internal/split_i_70_15_15_seed202604.json`

角色：初值泛化切分协议。

内容职责：

- `split_id`；
- `split_type = initial_condition`；
- `grouping_unit = trajectory`；
- train/val/test 比例；
- seed。

---

### `configs/windows/unit_internal/one_step_lag1.json`

角色：one-step 窗口协议。

数学对象：

$$

(\mathbf z_m,\mathbf z_{m+1}).

$$

---

### `configs/windows/unit_internal/rollout_h10_h50_h100.json`

角色：多 horizon rollout 窗口协议。

数学对象：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L}),
\qquad
L\in\{10,50,100\}.

$$

---

### `configs/tasks/unit_internal/task_rotation_contraction_one_step.json`

角色：一步预测任务配置。

输入：

$$

\mathbf z_m.

$$

目标：

$$

\mathbf z_{m+1}.

$$

指标：

$$

\mathcal E_{\rm 1step}.

$$

---

### `configs/tasks/unit_internal/task_rotation_contraction_rollout.json`

角色：多步 rollout 任务配置。

输入：

$$

\mathbf z_s.

$$

目标：

$$

(\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

指标：

$$

\mathcal E_{\rm roll}^{(L)}.

$$

---

### `configs/tasks/unit_internal/task_rotation_contraction_spectrum.json`

角色：谱恢复诊断任务配置。

目标谱：

$$

\lambda_\pm=e^{(-\gamma\pm i\omega)\tau}.

$$

该文件不训练模型，只定义后续算法评测时需要比较的真值谱对象。

---

### `configs/benchmarks/unit_internal/benchmark_rotation_contraction_smoke.json`

角色：一次完整 smoke benchmark 的组合配置。

它引用：

- system config；
- observation config；
- split config；
- window config；
- task config；
- 输出路径策略。

---

### `configs/releases/unit_internal_dev_rotation_contraction.json`

角色：开发期 release 索引。

记录本系统在 `unit_internal` 层的当前配置组合，方便后续纳入正式 release manifest。

---

## 3.2 源码文件

### `src/dynamics/linear_rotation_contraction_2d.jl`

角色：系统数学对象。

职责：

- 参数合法性检查；
- 构造 \(\mathbf A\)；
- 构造 \(\mathbf F^\tau\)；
- 给出连续谱；
- 给出离散谱；
- 支持解析单步推进；
- 支持解析轨线推进；
- 生成系统真值 metadata。

---

### `src/generators/exact_linear_trajectory_generator.jl`

角色：通用解析线性系统轨线生成器。

职责：

- 读取已经注册的线性系统对象；
- 根据初值策略采样 \(\mathbf x_0^{(q)}\)；
- 调用系统离散推进矩阵；
- 生成 `RawTrajectory`；
- 将结果交给观测链模块。

如果线性对角系统已经有类似文件，则本次不新增重复文件，而是在原有解析线性生成器中扩展对旋转–收缩系统的支持。

---

### `src/diagnostics/rotation_contraction_diagnostics.jl`

角色：本系统专属 sanity check。

职责：

- 半径衰减诊断；
- 角度增量诊断；
- 谱诊断；
- rollout 一致性诊断；
- 输出诊断表所需字段。

---

### `src/registries/system_registry.jl`

角色：系统注册表。

改动职责：

- 添加 `linear_rotation_contraction_2d`；
- 标记 `family = unit_internal`；
- 指向对应 `SystemSpec`；
- 指向对应 dynamics 构造逻辑。

---

### `src/manifests/system_truth_metadata.jl`

角色：生成系统真值元信息。

改动职责：

- 支持保存 \(\mathbf A\)、\(\mathbf F^\tau\)；
- 支持保存连续谱与离散谱；
- 支持保存 `contraction_factor`；
- 支持保存 `rotation_angle_per_step`。

如果现有 manifest 模块已经支持这些字段，则只需要扩展字段检查规则。

---

## 3.3 实验入口

### `experiments/smoke_tests/run_rotation_contraction_smoke.jl`

角色：最小端到端入口。

职责：

- 读取 smoke benchmark 配置；
- 生成 raw trajectory；
- 生成 observed trajectory；
- 生成 split；
- 生成 window summary；
- 运行系统诊断；
- 保存数据、manifest、表格、图像和日志。

该文件只组织流程，不写底层数学逻辑。工程指南明确要求 `experiments/` 保存实验入口脚本，不放核心函数。fileciteturn7file0

---

## 3.4 数据输出

### `data/raw/unit_internal/linear_rotation_contraction_2d/small/raw_trajectories.jld2`

角色：原始状态轨线。

存储对象：

$$

\mathbf X^{(q)}\in\mathbb R^{2\times(M+1)},
\qquad
q=1,\dots,R.

$$

---

### `data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/observed_trajectories.jld2`

角色：处理后观测轨线。

存储对象：

$$

\mathbf Z^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

clean 模式下应满足：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}.

$$

---

### `data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/splits.json`

角色：轨线级 train/val/test 切分索引。

---

### `data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/windows_summary.json`

角色：窗口数量与索引范围摘要。

不建议第一版保存所有窗口实体，优先保存窗口构造规则和摘要；除非后续训练接口需要 materialized windows。

---

### `data/manifests/unit_internal/linear_rotation_contraction_2d/full_state_clean_small_manifest.json`

角色：完整生成元信息。

必须包含：

```text
system_id
family
state_dim
gamma
omega
dt
trajectory_length
num_trajectories
initial_condition_policy
observation_id
split_id
window_ids
task_ids
continuous_matrix_A
discrete_matrix_F
continuous_eigenvalues
discrete_eigenvalues
contraction_factor
rotation_angle_per_step
seed
generator_commit_hash_or_local_placeholder
created_at
```

---

### `data/releases/unit_internal/dev_rotation_contraction_index.json`

角色：开发期数据索引。

记录 raw、processed、manifest 的相对路径。

---

## 3.5 报告输出

### `reports/unit_internal/linear_rotation_contraction_2d/tables/rotation_contraction_smoke_diagnostics.csv`

角色：系统诊断表。

建议列：

```text
system_id
observation_id
gamma
omega
dt
rho_true
rho_empirical_mean
rho_empirical_max_abs_error
theta_step_true
theta_step_empirical_mean
theta_step_max_abs_error
rollout_residual_max
spectrum_abs_error_max
num_trajectories
trajectory_length
```

---

### `reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_phase_portrait.png`

角色：相图。

内容：若干条轨线在 \((x_1,x_2)\) 平面中的衰减螺旋。

---

### `reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_radius_decay.png`

角色：半径衰减图。

内容：经验 \(r_m\) 与理论 \(r_0 e^{-\gamma t_m}\) 对比。

---

### `reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_angle_increment.png`

角色：角度增量图。

内容：经验 \(\Delta\theta_m\) 与理论 \(\omega\tau\) 对比。

---

### `reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_discrete_spectrum.png`

角色：离散谱图。

内容：\(\lambda_\pm\) 在复平面中的位置，以及单位圆参考。

---

### `reports/unit_internal/linear_rotation_contraction_2d/logs/rotation_contraction_smoke.log`

角色：smoke test 日志。

记录：

- 配置路径；
- 输出路径；
- 数据维度；
- 诊断摘要；
- 是否通过阈值检查。

---

## 3.6 测试文件

### `test/unit/test_linear_rotation_contraction_2d.jl`

角色：动力系统对象单元测试。

检查：

- \(\mathbf A\) 维度为 \(2\times2\)；
- \(\mathbf F^\tau\) 维度为 \(2\times2\)；
- \(\operatorname{eig}(\mathbf A)\) 等于 \(-\gamma\pm i\omega\)；
- \(\operatorname{eig}(\mathbf F^\tau)\) 等于 \(e^{(-\gamma\pm i\omega)\tau}\)；
- \(\mathbf F^\tau{}^\top \mathbf F^\tau\approx \rho^2\mathbf I\)。

---

### `test/integration/test_rotation_contraction_generation_pipeline.jl`

角色：小型端到端集成测试。

检查：

- 能从配置生成 raw；
- 能生成 observed；
- 能生成 split；
- 能生成 window summary；
- 能生成 manifest；
- 所有对象维度一致。

---

### `test/regression/test_rotation_contraction_reference_outputs.jl`

角色：固定 seed 回归测试。

检查：

- 轨线数不变；
- split 大小不变；
- one-step 样本数不变；
- rollout 样本数不变；
- 半径衰减误差不超过阈值；
- 角度增量误差不超过阈值；
- 谱误差不超过阈值。

---

### `test/reference_outputs/unit_internal/linear_rotation_contraction_2d/reference_manifest_small.json`

角色：小型参考 manifest。

用于 regression test 比较关键字段。

---

### `test/reference_outputs/unit_internal/linear_rotation_contraction_2d/reference_diagnostics_small.json`

角色：小型参考诊断结果。

用于比较核心统计量是否发生非预期变化。

# 4. Module / component responsibilities

## `configs/systems/`

只描述系统参数和生成规模，不写逻辑。

本系统对应：

$$

(\gamma,\omega,\tau,M,R,\text{initial condition policy}).

$$

---

## `src/dynamics/`

负责系统数学定义。

本系统对应：

$$

\mathbf A,\quad
\mathbf F^\tau,\quad
\nu_\pm,\quad
\lambda_\pm.

$$

---

## `src/generators/`

负责从配置生成轨线。

对本系统，应优先使用解析推进：

$$

\mathbf x_{m+1}=\mathbf F^\tau\mathbf x_m.

$$

---

## `src/observations/`

负责从 \(\mathbf X\) 得到 \(\mathbf Z\)。

第一版：

$$

\mathbf z_m=\mathbf x_m.

$$

第二版：

$$

\mathbf z_m=\mathbf x_m+\boldsymbol\varepsilon_m.

$$

---

## `src/splits/`

负责轨线级切分。

切分对象是 `trajectory_id`，不是单点样本或窗口。

---

## `src/windows/`

负责在 split 内部生成 one-step 和 rollout 窗口。

---

## `src/tasks/`

负责把窗口绑定到 benchmark 任务。

本系统第一版任务：

```text
one_step_forecast
multi_step_rollout
spectrum_recovery_diagnostic
```

---

## `src/diagnostics/`

负责系统 sanity check 和指标表。

本系统专属诊断：

- 半径衰减；
- 角度增量；
- 真值谱；
- rollout 残差。

---

## `src/manifests/`

负责写入完整元信息，保证数据可复现。

---

## `experiments/smoke_tests/`

负责最小可运行流程，不写核心数学函数。

---

## `reports/`

负责给人看的图、表、日志。

---

## `test/`

负责自动化测试。

其中本系统属于内部测试层，未来每次改协议层、生成器、观测链、split/window 逻辑时，都应先跑它。

# 5. Planned `##` sections

下面只列计划中的 Julia 文件结构标题，不写代码。

## `src/dynamics/linear_rotation_contraction_2d.jl`

```text
## System identity and parameter conventions
## Parameter validation for contraction and rotation
## Continuous generator matrix construction
## Exact discrete propagator construction
## Continuous and discrete spectrum metadata
## Exact one-step state propagation
## Exact trajectory propagation
## Polar-coordinate diagnostic quantities
## Truth metadata assembly
```

---

## `src/generators/exact_linear_trajectory_generator.jl`

```text
## Generator scope and supported linear systems
## Configuration validation before generation
## Random seed and trajectory-id policy
## Initial-condition sampling dispatch
## Exact discrete propagation loop
## RawTrajectory assembly
## Observation-chain handoff
## Manifest handoff
```

---

## `src/diagnostics/rotation_contraction_diagnostics.jl`

```text
## Diagnostic scope and required inputs
## Radius contraction diagnostic
## Angle increment diagnostic with phase unwrapping
## Discrete spectrum diagnostic
## Exact rollout residual diagnostic
## Diagnostic threshold policy
## Diagnostic table assembly
## Plot payload assembly
```

---

## `src/registries/system_registry.jl`

```text
## Registry purpose and lookup contract
## Unit-internal system entries
## Core benchmark system entries
## System configuration path resolution
## System constructor dispatch
## Registry consistency checks
```

---

## `src/manifests/system_truth_metadata.jl`

```text
## Manifest field conventions
## Linear-system matrix metadata
## Continuous-spectrum metadata
## Discrete-spectrum metadata
## Observation metadata
## Split and window metadata
## Reproducibility metadata
## Manifest validation checks
```

---

## `experiments/smoke_tests/run_rotation_contraction_smoke.jl`

```text
## Smoke-test purpose and run identifier
## Load benchmark configuration
## Resolve system observation split window and task specs
## Generate raw trajectories
## Generate observed trajectories
## Generate trajectory-level splits
## Build window summaries
## Run rotation-contraction diagnostics
## Save data manifest tables plots and logs
## Print final smoke-test summary
```

---

## `test/unit/test_linear_rotation_contraction_2d.jl`

```text
## Unit-test configuration
## Parameter validation tests
## Continuous generator matrix tests
## Exact discrete propagator tests
## Continuous spectrum tests
## Discrete spectrum tests
## One-step propagation consistency tests
```

---

## `test/integration/test_rotation_contraction_generation_pipeline.jl`

```text
## Integration-test configuration
## Smoke configuration loading test
## Raw trajectory generation test
## Observed trajectory generation test
## Split generation test
## Window summary generation test
## Manifest generation test
## End-to-end dimension consistency test
```

---

## `test/regression/test_rotation_contraction_reference_outputs.jl`

```text
## Regression-test configuration
## Reference manifest loading
## Current manifest comparison
## Reference diagnostic loading
## Current diagnostic comparison
## Split and window count comparison
## Regression tolerance checks
```

# 6. Data flow and dimensions

设：

$$

R=\text{num\_trajectories},
\qquad
M=\text{trajectory\_length},
\qquad
d_x=2,
\qquad
d_z=2.

$$

## 6.1 参数流

配置给出：

$$

\gamma,\omega,\tau,M,R.

$$

动力系统模块生成：

$$

\mathbf A\in\mathbb R^{2\times2},
\qquad
\mathbf F^\tau\in\mathbb R^{2\times2}.

$$

真值谱：

$$

\nu_\pm\in\mathbb C,
\qquad
\lambda_\pm\in\mathbb C.

$$

---

## 6.2 初值流

对第 \(q\) 条轨线：

$$

\mathbf x_0^{(q)}
=
r_0^{(q)}
\begin{bmatrix}
\cos\theta_0^{(q)}\\
\sin\theta_0^{(q)}
\end{bmatrix}
\in\mathbb R^2.

$$

推荐：

$$

r_0^{(q)}\sim \mathrm{Uniform}(0.5,2.0),
\qquad
\theta_0^{(q)}\sim \mathrm{Uniform}(0,2\pi).

$$

---

## 6.3 raw trajectory

每条轨线：

$$

\mathbf X^{(q)}
=
[\mathbf x_0^{(q)},\mathbf x_1^{(q)},\dots,\mathbf x_M^{(q)}]
\in\mathbb R^{2\times(M+1)}.

$$

所有轨线可以理解为集合：

$$

\{\mathbf X^{(q)}\}_{q=1}^R.

$$

若实现时使用三维数组，则约定为：

$$

\mathbf X_{\rm all}\in\mathbb R^{2\times(M+1)\times R}.

$$

必须在 manifest 中明确维度顺序，避免 Julia 列主序和批量维度混淆。

---

## 6.4 observed trajectory

clean 模式：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

noisy 模式：

$$

\mathbf Z^{(q)}
=
\mathbf X^{(q)}+\mathbf E^{(q)},
\qquad
\mathbf E^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

---

## 6.5 split

轨线编号：

$$

\mathcal R=\{1,\dots,R\}.

$$

切分：

$$

\mathcal R_{\rm train},
\quad
\mathcal R_{\rm val},
\quad
\mathcal R_{\rm test}.

$$

对应数量：

$$

R_{\rm train}+R_{\rm val}+R_{\rm test}=R.

$$

---

## 6.6 one-step windows

对每条轨线有 \(M\) 个 one-step 样本：

$$

(\mathbf z_m^{(q)},\mathbf z_{m+1}^{(q)}),
\qquad
m=0,\dots,M-1.

$$

其中：

$$

\mathbf z_m^{(q)}\in\mathbb R^2.

$$

---

## 6.7 rollout windows

对 horizon \(L\)，每条轨线有：

$$

M+1-L

$$

个 rollout 起点。

窗口对象：

$$

\mathbf Z_{s:s+L}^{(q)}
=
[\mathbf z_s^{(q)},\dots,\mathbf z_{s+L}^{(q)}]
\in\mathbb R^{2\times(L+1)}.

$$

输入端：

$$

\mathbf z_s^{(q)}\in\mathbb R^2.

$$

目标端：

$$

[\mathbf z_{s+1}^{(q)},\dots,\mathbf z_{s+L}^{(q)}]
\in\mathbb R^{2\times L}.

$$

# 7. Package and documentation plan

本节只列包方向，不假设具体 API。

## `LinearAlgebra`

用途：

- 构造矩阵；
- 特征值检查；
- 范数；
- 矩阵乘法；
- 谱诊断。

需要查文档：

- `eigvals` 对实矩阵返回复数特征值的行为；
- 数值排序是否需要自行处理；
- 浮点容差策略。

---

## `Random`

用途：

- 初值采样；
- 噪声采样；
- split shuffle；
- seed 复现。

需要查文档：

- 局部 RNG 的推荐写法；
- 避免污染全局随机状态的方式。

---

## `JSON3.jl` 或同类 JSON 包

用途：

- 读取 `.json` 配置；
- 写入 manifest；
- 写入 release index；
- 写入 window summary。

需要查文档：

- 数组、嵌套对象、浮点数、复数元信息的序列化方式；
- 是否需要自定义结构转换。

注意：复数谱不建议直接裸存复数对象，manifest 中更稳妥地保存为：

```text
real
imag
abs
angle
```

---

## `JLD2.jl` 或 `HDF5.jl`

用途：

- 保存 raw trajectories；
- 保存 observed trajectories；
- 保存可能的大型数组。

需要查文档：

- 文件内 group / dataset 命名；
- 数组维度保存与读取一致性；
- metadata 是否单独放 JSON 更稳妥。

---

## `CSV.jl` 与 `DataFrames.jl`

用途：

- 输出诊断表；
- 保存 smoke 结果；
- 后续汇总多个系统诊断。

需要查文档：

- 表格列类型；
- 浮点格式；
- CSV 写入行为。

---

## `Plots.jl`、`CairoMakie.jl` 或同类绘图库

用途：

- 相图；
- 半径衰减图；
- 角度增量图；
- 谱图。

需要查文档：

- headless 环境保存 PNG 的方式；
- 图像尺寸、字体、后端选择；
- 复平面散点图的绘制工作流。

---

## `Test`

用途：

- unit test；
- integration test；
- regression test。

需要查文档：

- 近似相等的容差表达；
- 测试集组织方式；
- 测试输出摘要。

---

## `DifferentialEquations.jl`

第一版不需要它，因为本系统应使用解析推进。

但若为了统一接口保留 solver 对照，可以以后加入：

$$

\max_m
\|\mathbf x_m^{\rm solver}-\mathbf x_m^{\rm exact}\|_2.

$$

在正式接入前必须查官方文档，不能凭记忆假设求解器 API。

# 8. Debugging and inspection plan

## 8.1 配置加载检查

打印或记录：

```text
system_id
family
state_dim
gamma
omega
dt
trajectory_length
num_trajectories
observation_id
split_id
window_ids
task_ids
seed
```

检查：

- 所有 ID 能在 registry 中解析；
- 所有路径存在；
- 所有数值参数合法。

---

## 8.2 矩阵检查

记录：

$$

\mathbf A,
\qquad
\mathbf F^\tau,
\qquad
\det(\mathbf F^\tau),
\qquad
\operatorname{tr}(\mathbf F^\tau).

$$

理论上：

$$

\det(\mathbf F^\tau)=e^{-2\gamma\tau},

$$

$$

\operatorname{tr}(\mathbf F^\tau)
=
2e^{-\gamma\tau}\cos(\omega\tau).

$$

---

## 8.3 谱检查

记录：

$$

\nu_\pm=-\gamma\pm i\omega,

$$

$$

\lambda_\pm=e^{(-\gamma\pm i\omega)\tau}.

$$

检查：

$$

\max_j
\left|
|\lambda_j|-e^{-\gamma\tau}
\right|

$$

和

$$

\max_j
\left|
|\arg(\lambda_j)|-\omega\tau
\right|.

$$

---

## 8.4 轨线维度检查

每条轨线：

```text
state_matrix size = 2 × (M+1)
observation_matrix size = 2 × (M+1)
times length = M+1
```

所有轨线：

```text
num_trajectories = R
```

---

## 8.5 半径衰减检查

对每条轨线：

$$

r_m^{(q)}=\|\mathbf x_m^{(q)}\|_2.

$$

检查：

$$

\frac{r_{m+1}^{(q)}}{r_m^{(q)}}
-
e^{-\gamma\tau}.

$$

保存：

```text
rho_true
rho_empirical_mean
rho_empirical_std
rho_empirical_max_abs_error
```

---

## 8.6 角度增量检查

对每条轨线：

$$

\theta_m^{(q)}=\operatorname{atan2}(x_{2,m}^{(q)},x_{1,m}^{(q)}).

$$

使用 unwrap 后检查：

$$

\theta_{m+1}^{(q)}-\theta_m^{(q)}
\approx
\omega\tau.

$$

保存：

```text
theta_step_true
theta_step_empirical_mean
theta_step_empirical_std
theta_step_max_abs_error
```

---

## 8.7 rollout 一致性检查

对若干起点 \(s\) 和 horizon \(L\)，检查：

$$

\mathbf x_{s+\ell}
-
(\mathbf F^\tau)^\ell \mathbf x_s.

$$

保存：

```text
rollout_horizon
rollout_residual_mean
rollout_residual_max
```

---

## 8.8 split 检查

保存：

```text
num_train_trajectories
num_val_trajectories
num_test_trajectories
train_ids
val_ids
test_ids
```

检查：

- 无重复；
- 无遗漏；
- 按轨线切分。

---

## 8.9 window 检查

保存：

```text
num_one_step_train
num_one_step_val
num_one_step_test
num_rollout_train_h10
num_rollout_val_h10
num_rollout_test_h10
num_rollout_train_h50
...
```

检查：

- 数量与公式一致；
- 所有窗口索引在合法范围内；
- rollout 不跨越轨线边界。

# 9. Expected outputs

第一轮 smoke 运行后应产生：

## 数据

```text
data/raw/unit_internal/linear_rotation_contraction_2d/small/raw_trajectories.jld2
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/observed_trajectories.jld2
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/splits.json
data/processed/unit_internal/linear_rotation_contraction_2d/full_state_clean/small/windows_summary.json
data/manifests/unit_internal/linear_rotation_contraction_2d/full_state_clean_small_manifest.json
data/releases/unit_internal/dev_rotation_contraction_index.json
```

## 表格

```text
reports/unit_internal/linear_rotation_contraction_2d/tables/rotation_contraction_smoke_diagnostics.csv
```

## 图像

```text
reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_phase_portrait.png
reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_radius_decay.png
reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_angle_increment.png
reports/unit_internal/linear_rotation_contraction_2d/plots/rotation_contraction_discrete_spectrum.png
```

## 日志

```text
reports/unit_internal/linear_rotation_contraction_2d/logs/rotation_contraction_smoke.log
```

## 测试参考输出

```text
test/reference_outputs/unit_internal/linear_rotation_contraction_2d/reference_manifest_small.json
test/reference_outputs/unit_internal/linear_rotation_contraction_2d/reference_diagnostics_small.json
```

# 10. Failure points and debugging strategies

## 10.1 旋转方向符号错误

风险：

$$

\mathbf A
=
\begin{bmatrix}
-\gamma & -\omega\\
\omega & -\gamma
\end{bmatrix}

$$

和

$$

\begin{bmatrix}
-\gamma & \omega\\
-\omega & -\gamma
\end{bmatrix}

$$

会产生相反旋转方向。

诊断：

- 检查 \(\theta_{m+1}-\theta_m\) 的符号；
- 检查 \(\arg(\lambda_\pm)\) 是否为 \(\pm\omega\tau\)。

---

## 10.2 角度 wrap 导致诊断错误

风险：直接相减 `atan2` 角度会在 \(-\pi,\pi\) 边界跳变。

诊断策略：

- 使用 unwrap 后再统计；
- 同时检查复数比值  
  $$

  \frac{x_{1,m+1}+ix_{2,m+1}}{x_{1,m}+ix_{2,m}}
  
$$
  的相位。

---

## 10.3 轨线索引 off-by-one

风险：`trajectory_length = M` 可能被误解为保存 \(M\) 个点，而协议中应保存 \(M+1\) 个快照。

诊断：

```text
times length = M+1
state_matrix second dimension = M+1
one_step count per trajectory = M
rollout count per trajectory = M+1-L
```

---

## 10.4 Julia 数组方向混淆

风险：把状态存成 `(M+1) × 2`，而协议要求按列存储：

$$

\mathbf X\in\mathbb R^{2\times(M+1)}.

$$

诊断：

- manifest 写入 `array_layout = state_dim_by_time`；
- 所有测试检查第一维等于 `state_dim = 2`。

---

## 10.5 初值太小导致角度不稳定

风险：若 \(\|\mathbf x_0\|\) 太小，角度计算对舍入误差敏感。

策略：

$$

r_0\in[0.5,2.0]

$$

不要从接近 0 的区域采样。

---

## 10.6 轨线太长导致全部塌到原点

风险：若 \(t_{\max}\) 太大，后半段半径过小，不利于角度和谱诊断。

策略：

- small 档建议 \(M=500,\tau=0.01,t_{\max}=5\)；
- medium 档可用 \(M=2000,t_{\max}=20\)；
- 若 \(\gamma\) 增大，应同步缩短 \(t_{\max}\)。

---

## 10.7 split 泄漏

风险：先切窗口再随机分，会使同一条轨线的相邻窗口同时出现在 train/test。

策略：

- split 只操作 `trajectory_id`；
- window 只在 split 内部生成；
- integration test 检查 train/test 的 `trajectory_id` 不相交。

---

## 10.8 noisy observation 破坏 exact diagnostic

风险：如果对 noisy \(\mathbf Z\) 做半径和角度真值检查，误差会变大。

策略：

- exact diagnostic 默认基于 raw \(\mathbf X\)；
- noisy observation 只额外报告噪声统计；
- 不把 noisy 误差当作系统生成错误。

---

## 10.9 复数谱排序不稳定

风险：`eigvals` 返回顺序不固定。

策略：

- 比较集合而不是比较固定位置；
- 用实部、虚部、模长、相位综合匹配；
- manifest 中保存 `lambda_plus` 与 `lambda_minus` 的显式真值。

# 11. Implementation order

建议按以下顺序实现，便于每一步都能测试：

1. 写 `configs/systems/unit_internal/linear_rotation_contraction_2d.json`；
2. 写 `src/dynamics/linear_rotation_contraction_2d.jl`；
3. 写或扩展解析线性轨线生成器；
4. 写 clean full-state observation 配置；
5. 写 smoke benchmark 配置；
6. 跑 raw + processed 生成；
7. 写 diagnostics；
8. 保存 manifest、表格、图像、日志；
9. 写 unit test；
10. 写 integration test；
11. 固定小型 reference output；
12. 写 regression test；
13. 再加入 noisy observation 版本。

# 12. Stop before code

到这里为止，这是一份代码工程计划书，不包含 Julia 实现。

下一步如果进入编码，应先从 `SystemSpec` 配置和 `src/dynamics/linear_rotation_contraction_2d.jl` 开始；在那之前，不建议直接写 smoke 脚本，因为必须先把系统数学对象和真值谱接口固定下来。