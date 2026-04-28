# 数学设定

## 观测链与数据对象

本文档中的数据对象不默认直接等同于动力系统状态 $\mathbf{x}$。我们统一把从真实状态到算法输入的过程写成观测链
$$
\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z},
$$

其中
$$
\mathbf{x}\in\mathcal{X},\qquad
\mathbf{u}\in\mathcal{U},\qquad
\mathbf{s}\in\mathbb{K}^{rN_x},\qquad
\mathbf{z}\in\mathcal{Z}.
$$

这里 $\mathbf{x}$ 表示动力系统状态，$\mathbf{u}$ 表示物理观测对象，$\mathbf{s}$ 表示采样后的有限维数值表示，$\mathbf{z}$ 表示最终进入数据集与算法接口的标准化表示。具体地，
$$
U:\mathcal{X}\to\mathcal{U},\qquad \mathbf{u}=U(\mathbf{x}),
$$

$$
S:\mathcal{U}\to\mathbb{K}^{rN_x},\qquad \mathbf{s}=S(\mathbf{u}),
$$

$$
Z:\mathbb{K}^{rN_x}\to\mathcal{Z},\qquad \mathbf{z}=Z(\mathbf{s}).
$$

因此离散快照统一记为
$$
\mathbf{z}_m:=Z\circ S\circ U(\mathbf{x}_m)\in\mathcal{Z}.
$$

在这里，$U$ 负责把完整状态映射为可观测物理量，$S$ 负责把连续或抽象观测对象映射为有限维采样向量，$Z$ 负责把采样结果整理为算法统一使用的输入表示。对于低维 ODE，最简单的情形是
$$
U=\mathcal{I}_{\mathcal X},\qquad
S=\mathcal{I},\qquad
Z=\mathcal{I},
$$

此时 $\mathbf{z}=\mathbf{x}$。

## 状态、轨线与存储约定

状态变量统一记为
$$
\mathbf{x}\in\mathcal{X},
$$

学习器输入变量统一记为
$$
\mathbf{z}\in\mathcal{Z}.
$$

连续时间动力系统写为
$$
\dot{\mathbf{x}}=\mathbf{f}(\mathbf{x}),
$$

其以采样步长 $\tau>0$ 得到的离散轨线写为
$$
\mathbf{x}_{m+1}=\mathbf{F}^\tau(\mathbf{x}_m),
\qquad m=1,2,\dots .
$$

若一条轨线长度为 $M+1$，则状态数据矩阵与观测数据矩阵按列优先存储为
$$
\mathbf{X}
=
\begin{bmatrix}
\mathbf{x}_1&\cdots&\mathbf{x}_{M+1}
\end{bmatrix},
\qquad
\mathbf{Z}
=
\begin{bmatrix}
\mathbf{z}_1&\cdots&\mathbf{z}_{M+1}
\end{bmatrix}.
$$

其中下标 $m$ 始终表示时间快照索引；若需要区分不同轨线，则额外引入轨线编号 $q$，写作
$$
\mathbf{x}_m^{(q)},\qquad \mathbf{z}_m^{(q)}.
$$

除非特别说明，单步样本默认指相邻快照对
$$
(\mathbf{z}_m,\mathbf{z}_{m+1}),
$$

多步窗口默认指从起点 $s$ 出发的连续片段
$$
(\mathbf{z}_s,\mathbf{z}_{s+1},\dots,\mathbf{z}_{s+L}).
$$



## 记号约定

粗体小写字母表示列向量，如 $\mathbf{x},\mathbf{a}$；粗体大写字母表示矩阵，如 $\mathbf{A}$；算子与映射记为花体字母，如 $\mathcal{F}^\tau,\mathcal{A},\mathcal{D}$。标量域统一记为
$$
\mathbb{K}\in\{\mathbb{R},\mathbb{C}\}.
$$

数值线性代数中，转置记为 ${}^\top$，共轭转置记为 ${}^*$，伪逆记为 ${}^\dagger$。向量的 Euclid 范数记为 $\|\cdot\|_2$，矩阵的 Frobenius 范数显式记为
$$
\|\mathbf{A}\|_{\mathrm F}
:=
\left(\sum_{i,j}|A_{ij}|^2\right)^{1/2}.
$$

若本文出现单位算子，则记为 $\mathcal{I}$。

# ODEs_dataset 项目规范文档
## 面向通用动力系统算法评测的 ODE 测试数据集工程指南

## 0. 文档定位

本文档规定 **ODEs_dataset** 的工程目标、目录结构、配置对象、数据协议、切分协议、窗口协议、评测协议与版本发布规则。

本文档服务的是一个**通用 ODE benchmark 工程**，其目标是为下列研究任务提供统一数据基座：

- 短期预测与长期传播；
- 系统辨识与模型近似；
- 表示学习与降维；
- 算子近似与谱分析；
- 参数泛化与观测泛化；
- 噪声鲁棒性与部分观测恢复；
- 长期统计性质与吸引子结构比较。

因此，**ODEs_dataset 应被视为“协议库 + 数据工厂 + 评测基座”，而不是简单的样本文件集合**。

---

## 1. 总目标

### 1.1 核心目标

构建一个长期可维护、可版本化、可扩展的 ODE benchmark 工程，使其能够稳定支持以下数据流水线：

$$
(\mathbf f,\boldsymbol{\mu},\mathbf x_0,\tau)
\Longrightarrow
\{\mathbf x_m\}_{m=1}^{M+1}
\Longrightarrow
\{\mathbf z_m\}_{m=1}^{M+1}
\Longrightarrow
\text{split}
\Longrightarrow
\text{window}
\Longrightarrow
\text{benchmark task}
\Longrightarrow
\text{metric report}.
$$


其中：

- $\mathbf x_m\in\mathcal X$ 为状态轨线；
- $\mathbf z_m\in\mathcal Z$ 为观测链处理后的量化样本；
- `split` 决定训练/验证/测试的划分；
- `window` 决定任务样本的构造方式；
- `benchmark task` 决定算法要解决的问题；
- `metric report` 给出统一的比较结果。

### 1.2 适用范围

本数据集项目当前只覆盖 **ODE 系统**，不包含 PDE、DDE、SDE 与控制输入系统的正式 benchmark。

但工程接口应为未来扩展预留空间，使得后续可以平滑加入：

- 受控 ODE；
- 随机扰动 ODE；
- 刚性系统；
- 网络耦合系统；
- 更高维动力系统。

### 1.3 不应写入数据集定义的内容

下列内容不属于数据集协议本身，不应嵌入数据生成标准：

- 某一特定算法的 latent 结构；
- 某一特定损失函数；
- 某一特定网络架构；
- 某一特定算子近似形式；
- 某一特定谱先验；
- 某一特定 decoder 结构。

这些对象都应属于“下游算法”或“实验配置”，而不是数据集定义。

---

## 2. 设计原则

### 2.1 协议先于系统

新增系统只能通过补充配置进入，不允许因为接入新系统而修改既有核心接口。

### 2.2 动力系统与观测链解耦

动力系统模块只负责生成状态轨线：
$$
\{\mathbf x_m\}_{m=1}^{M+1}.
$$


观测、采样、量化、归一化、加噪全部由独立观测链模块处理：
$$
\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z}.
$$

这一抽象应当固定为通用数据层的基本接口。fileciteturn11file7

### 2.3 切分协议独立

train / val / test 的定义必须由独立配置对象描述，而不能散落在训练脚本中。

### 2.4 窗口任务独立

一步样本、多步 rollout 窗口、长期统计窗口等应由统一窗口协议构造，而不是在实验中临时切片。

### 2.5 原始数据与处理数据分离

- `raw`：数值积分得到的原始状态轨线；
- `processed`：施加观测链与标准处理后的样本；
- `manifest`：数据生成元信息与版本说明。

### 2.6 数据、任务、评测三层分离

- 数据层定义“有哪些轨线、有哪些观测”；
- 任务层定义“如何从轨线构造样本”；
- 评测层定义“怎样比较算法输出”。

这样才能保证同一组基础数据支撑多种算法问题。

---

## 3. 目录蓝图

推荐项目目录如下：

```text
ODEs_dataset/
  README.md
  Project.toml
  Manifest.toml

  docs/
	project guide/
	notes/
    spec/
      ODEs_dataset_spec.md
      system_registry.md
      split_registry.md
      task_registry.md
      metric_registry.md

  configs/
    systems/
    observations/
    splits/
    windows/
    tasks/
    benchmarks/
    releases/

  src/
    dynamics/
    observations/
    generators/
    datasets/
    splits/
    windows/
    tasks/
    diagnostics/
    manifests/
    io/
    registries/
    utils/

  data/
    raw/
    processed/
    manifests/
    releases/

  experiments/
    smoke_tests/
    baseline_forecasting/
    baseline_identification/
    baseline_representation/

  reports/
    tables/
    plots/
    logs/

  test/
    unit/
    integration/
    regression/
```

---

## 各目录职责

本项目的目录结构服务于一条固定的数据集流水线：

```text
系统配置 → 轨线生成 → 观测处理 → 数据保存 → 切分与窗口 → 任务与评测
```

因此，各目录职责应保持清晰分工，避免把系统定义、数据生成、实验脚本和评测结果混在一起。

---
### 顶层文件

- `README.md`：项目说明、运行方式、当前支持系统和数据生成流程。
- `Project.toml`：Julia 项目依赖。
- `Manifest.toml`：锁定依赖版本，保证数据生成和测试可复现。

### `docs/`

保存项目文档。

- `docs/project guide/`：工程计划、阶段目标、编码计划书。
- `docs/notes/`：研究笔记、数学推导、实验想法。
- `docs/spec/`：正式协议文档，例如系统、切分、任务、指标规范。

### `configs/`

保存声明式配置，不保存数据，不写复杂逻辑。

- `configs/systems/`：动力系统配置，如系统参数、初值范围、时间步长、轨线长度。
- `configs/observations/`：观测链配置，即从状态 `x` 到算法输入 `z` 的处理方式。
- `configs/splits/`：训练集、验证集、测试集切分协议。
- `configs/windows/`：一步样本、多步 rollout、统计窗口等窗口规则。
- `configs/tasks/`：benchmark 任务配置。
- `configs/benchmarks/`：一次完整 benchmark 使用哪些系统、观测、切分、窗口和任务。
- `configs/releases/`：正式版本发布清单。

这种分层对应项目文档中强调的原则：切分协议和窗口协议应独立于实验脚本，观测链也应与动力系统解耦。

### `src/`

保存可复用 Julia 源码。

- `src/dynamics/`：定义 ODE 系统本体和右端函数。
- `src/observations/`：实现观测链、加噪、归一化等操作。
- `src/generators/`：根据系统配置和观测配置生成轨线数据。
- `src/datasets/`：定义统一数据对象，如原始轨线、观测轨线、窗口样本。
- `src/splits/`：生成 train / val / test 索引。
- `src/windows/`：从轨线中构造一步样本、多步窗口和统计窗口。
- `src/tasks/`：定义标准 benchmark 任务。
- `src/diagnostics/`：计算数据检查量和评测指标。
- `src/manifests/`：生成和检查数据元信息。
- `src/io/`：统一处理数据读写和路径管理。
- `src/registries/`：管理系统、观测、任务、指标等注册信息。
- `src/utils/`：通用辅助函数。

### `data/`

保存生成出来的数据。

- `data/raw/`：数值积分得到的原始状态轨线。
- `data/processed/`：经过观测链处理后的标准数据。
- `data/manifests/`：数据生成元信息。
- `data/releases/`：正式发布版本的数据索引或冻结清单。

原始轨线和处理后数据应分开保存，这与项目规范中 `raw / processed / manifest` 分离的原则一致。

### `experiments/`

保存实验入口脚本，不放核心函数。

- `experiments/smoke_tests/`：最小可运行测试，例如线性对角系统。
- `experiments/baseline_forecasting/`：预测类 baseline。
- `experiments/baseline_identification/`：系统辨识类 baseline。
- `experiments/baseline_representation/`：表示学习类 baseline。

### `reports/`

保存实验输出。

- `reports/tables/`：误差表、数据规模表、评测表。
- `reports/plots/`：轨线图、相图、误差曲线等。
- `reports/logs/`：运行日志和调试记录。

### `test/`

保存自动化测试。

- `test/unit/`：单个函数或模块的测试。
- `test/integration/`：小型端到端流程测试。
- `test/regression/`：固定配置下的回归测试，防止后续修改破坏已有结果。
- 
## 5. 核心配置对象清单

下面给出数据集必须存在的一级配置对象。

---

### 5.1 `SystemSpec`

描述一个动力系统家族。

#### 必填字段

- `system_id`
- `family`
- `state_dim`
- `parameter_names`
- `parameter_domain`
- `default_parameters`
- `initial_condition_domain`
- `dt`
- `tspan`
- `trajectory_length`
- `solver_name`
- `solver_abstol`
- `solver_reltol`
- `seed_policy`

#### 数学含义

`SystemSpec` 对应
$$
\dot{\mathbf x}=\mathbf f(\mathbf x;\boldsymbol{\mu}),
\qquad
\mathbf x(0)=\mathbf x_0,
\qquad
\mathbf x_{m+1}=\mathbf F^\tau(\mathbf x_m).
$$


#### 设计要求

- 系统定义与积分策略必须解耦；
- 参数既可取单点，也可取参数网格；
- 初值应由统一策略采样，而不是写死在脚本中。

---

### 5.2 `ObservationSpec`

描述观测链 $U,S,Z$。

#### 必填字段

- `observation_id`
- `mode`
- `input_space_name`
- `sensor_matrix` 或 `sensor_map_id`
- `noise_model`
- `noise_level`
- `normalization_policy`
- `quantization_policy`
- `output_dim`

#### 数学含义

它实现
$$
\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z}.
$$


#### 设计要求

- 对同一 `SystemSpec`，必须允许挂接多个 `ObservationSpec`；
- 下游 benchmark 只依赖 $\mathbf z_m$，不直接绑定 $\mathbf x_m$；
- 观测模式至少支持：
  - 全状态；
  - 部分状态；
  - 线性混合；
  - 非线性传感器；
  - 带噪观测。

---

### 5.3 `TrajectorySpec`

描述单条轨线的生成实例。

#### 必填字段

- `system_id`
- `parameter_instance`
- `initial_condition_instance`
- `dt`
- `trajectory_length`
- `seed`

#### 输出对象

- 状态轨线 $\{\mathbf x_m\}_{m=1}^{M+1}$
- 观测轨线 $\{\mathbf z_m\}_{m=1}^{M+1}$

---

### 5.4 `SplitSpec`

描述数据切分协议。

#### 必填字段

- `split_id`
- `split_type`
- `train_ratio`
- `val_ratio`
- `test_ratio`
- `grouping_unit`
- `seed`

#### 推荐类型

- `initial_condition`
- `parameter`
- `observation`
- `noise_level`
- `time_extrapolation`

#### 设计要求

默认切分单位必须是**整条轨线**，而不是窗口或单点样本。

---

### 5.5 `WindowSpec`

描述窗口样本的构造方式。

#### 类型 A：一步样本

对应
$$
(\mathbf z_m,\mathbf z_{m+1}).
$$


字段：

- `window_type = one_step`
- `lag = 1`

#### 类型 B：多步 rollout 窗口

对应
$$
(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).
$$


字段：

- `window_type = rollout`
- `horizon = L`

#### 类型 C：统计窗口

对应长度为 $L$ 的局部统计段，用于估计长期统计量或局部时间平均。

字段：

- `window_type = statistics`
- `horizon = L`

#### 类型 D：自定义窗口

允许未来扩展到特定任务，但不应破坏前三类的统一接口。

---

### 5.6 `TaskSpec`

描述一个标准 benchmark 任务。

#### 必填字段

- `task_id`
- `task_type`
- `window_id`
- `input_object_type`
- `target_object_type`
- `metric_ids`

#### 推荐任务类型

- `one_step_forecast`
- `multi_step_rollout`
- `state_reconstruction`
- `observation_reconstruction`
- `partial_observation_inference`
- `parameter_generalization`
- `long_time_statistics`
- `representation_evaluation`

---

### 5.7 `BenchmarkSpec`

描述某次 benchmark 要运行的完整任务集合。

#### 必填字段

- `benchmark_id`
- `system_ids`
- `observation_ids`
- `split_ids`
- `window_ids`
- `task_ids`
- `difficulty_level`
- `release_version`

---

### 5.8 `ReleaseManifest`

描述一次正式发布的数据版本。

#### 必填字段

- `dataset_version`
- `release_date`
- `system_registry_version`
- `observation_registry_version`
- `split_registry_version`
- `window_registry_version`
- `task_registry_version`
- `benchmark_registry_version`
- `generator_commit_hash`
- `notes`

---

## 6. 数据对象协议

为保证训练器与数据层完全解耦，必须统一数据对象格式。

### 6.1 原始轨线对象 `RawTrajectory`

字段：

- `trajectory_id`
- `system_id`
- `parameter_instance`
- `initial_condition_instance`
- `times`
- `state_matrix`

其中
$$
\mathbf X
=
\begin{bmatrix}
\mathbf x_1 & \cdots & \mathbf x_{M+1}
\end{bmatrix}
\in\mathbb K^{d_x\times (M+1)}.
$$


---

### 6.2 处理轨线对象 `ObservedTrajectory`

字段：

- `trajectory_id`
- `system_id`
- `observation_id`
- `parameter_instance`
- `initial_condition_instance`
- `state_matrix`
- `observation_matrix`

其中
$$
\mathbf Z
=
\begin{bmatrix}
\mathbf z_1 & \cdots & \mathbf z_{M+1}
\end{bmatrix}
\in\mathbb K^{d_z\times (M+1)}.
$$


---

### 6.3 一步样本对象 `OneStepSample`

字段：

- `trajectory_id`
- `index_m`
- `z_now = \mathbf z_m`
- `z_next = \mathbf z_{m+1}`

---

### 6.4 多步窗口对象 `RolloutWindowSample`

字段：

- `trajectory_id`
- `start_index = s`
- `horizon = L`
- `z_start = \mathbf z_s`
- `z_future = (\mathbf z_{s+1},\dots,\mathbf z_{s+L})`

---

### 6.5 统计窗口对象 `StatisticsWindowSample`

字段：

- `trajectory_id`
- `start_index = s`
- `horizon = L`
- `z_segment = (\mathbf z_s,\dots,\mathbf z_{s+L-1})`

它用于：
- 时间平均；
- 协方差估计；
- 频谱估计；
- 局部统计比较。

---

## 7. 系统注册规范

### 7.1 注册分层

系统应分三层注册：

#### A. `unit_internal`
内部单元测试系统，只用于协议与生成器回归测试：

- 线性对角系统；
- 旋转–收缩系统；
- Jordan / 非正规系统。

#### B. `v1_core`
公开 benchmark 主集合：

- 线性振子；
- Van der Pol；
- Duffing；
- Lotka–Volterra；
- FitzHugh–Nagumo；
- Lorenz ’63；
- Rössler；
- Lorenz ’96。

#### C. `v1_plus`
扩展挑战集合：

- Robertson；
- 摆系统家族；
- 多自由度弹簧链；
- 耦合振子网络。

### 7.2 新系统接入要求

新增系统必须同时提交：

- 一份 `SystemSpec`；
- 至少一份 `ObservationSpec`；
- 至少一份 `SplitSpec`；
- 至少一份 `TaskSpec`；
- 一份 smoke test；
- 一份 manifest 示例。

---

## 8. 数据生成流水线规范

数据生成必须按固定流水线执行：

### Step 1. 系统采样

采样参数 $\boldsymbol{\mu}$ 与初值 $\mathbf x_0$。

### Step 2. 状态轨线生成

数值积分得到
$$
\{\mathbf x_m\}_{m=1}^{M+1}.
$$


### Step 3. 观测链处理

施加 $U,S,Z$ 得到
$$
\{\mathbf z_m\}_{m=1}^{M+1}.
$$


### Step 4. 轨线级存盘

保存 `RawTrajectory` 与 `ObservedTrajectory`。

### Step 5. split 生成

按 `SplitSpec` 生成轨线级划分。

### Step 6. 窗口派生

从各子集内部生成：
- 一步样本；
- rollout 窗口；
- 统计窗口。

### Step 7. 任务实例化

把窗口对象映射为 benchmark 任务对象。

### Step 8. manifest 写入

保存完整元数据，确保结果可复现。

---

## 9. 切分协议规范

### 9.1 基本规则

切分必须满足：

1. 先按轨线切；
2. 再在各自集合内部生成窗口；
3. 禁止把同一条轨线的相邻窗口分散到 train 与 test。

### 9.2 官方 split 定义

#### `Split-I`
参数固定，测试集使用未见初值。

#### `Split-P`
训练参数集与测试参数集分离。

#### `Split-O`
动力系统固定，但测试集使用未见观测方式。

#### `Split-N`
动力系统与观测结构固定，但噪声级别改变。

#### `Split-T`
时间外推切分，即训练使用较短时间窗，测试使用更长时间窗或更靠后的轨线段。

### 9.3 推荐比例

默认：
$$
70\% / 15\% / 15\%.
$$


小样本系统可用：
$$
80\% / 10\% / 10\%.
$$


---

## 10. 任务协议规范

### 10.1 一步预测任务

输入：
$$
\mathbf z_m.
$$


目标：
$$
\mathbf z_{m+1}.
$$


适用于：
- 一步预测器；
- 局部线性近似；
- 一步系统辨识。

---

### 10.2 多步 rollout 任务

输入：
$$
\mathbf z_s.
$$


目标：
$$
(\mathbf z_{s+1},\dots,\mathbf z_{s+L}).
$$


适用于：
- 长期传播；
- 稳定性分析；
- 误差累积比较。

---

### 10.3 状态或观测重构任务

输入：
- 全观测或部分观测 $\mathbf z_m$。

目标：
- $\mathbf x_m$ 或 $\mathbf z_m$。

适用于：
- 自编码器类方法；
- 部分观测恢复；
- 表示学习。

---

### 10.4 参数泛化任务

输入：
- 训练参数范围内的轨线；
- 未见参数范围内的测试轨线。

目标：
- 比较模型在参数变化下的稳定性与外推能力。

---

### 10.5 长期统计任务

输入：
- 长轨线或统计窗口。

目标：
- 比较时间平均、边际分布、协方差、功率谱等统计量。

适用于：
- 混沌系统；
- 吸引子统计；
- 稳态分布近似。

---

### 10.6 观测恢复任务

输入：
- 部分观测、线性混合观测或非线性观测。

目标：
- 恢复完整状态或标准观测表示。

适用于：
- 传感器设计；
- 不完全观测场景；
- 逆问题风格任务。

---

## 11. 指标协议规范

### 11.1 一步误差

定义为
$$
\mathcal E_{\mathrm{1step}}
=
\frac1M\sum_m
\|\widehat{\mathbf z}_{m+1}-\mathbf z_{m+1}\|_2^2.
$$


### 11.2 多步 rollout 误差

定义为
$$
\mathcal E_{\mathrm{roll}}^{(L)}
=
\frac1S\sum_s
\frac1L\sum_{\ell=1}^L
\|\widehat{\mathbf z}_{s+\ell\mid s}-\mathbf z_{s+\ell}\|_2^2.
$$


### 11.3 重构误差

若目标是恢复 $\mathbf x_m$ 或 $\mathbf z_m$，统一写为
$$
\mathcal E_{\mathrm{rec}}
=
\frac1M\sum_m
\|\widehat{\mathbf y}_m-\mathbf y_m\|_2^2,
$$

其中 $\mathbf y_m$ 表示目标对象。

### 11.4 长期统计误差

建议至少支持：

- 时间平均误差；
- 协方差误差；
- 功率谱差异；
- 边际分布差异；
- 吸引子几何统计差异。

### 11.5 鲁棒性指标

建议至少支持：

- 噪声级别变化下的性能曲线；
- 参数偏移下的性能曲线；
- 观测模式变化下的性能曲线；
- 随机种子方差。

### 11.6 运行代价指标

建议记录：

- 训练时间；
- 推理时间；
- 参数量；
- 内存占用；
- 数据吞吐量。

这些指标不属于数学质量本身，但属于工程 benchmark 的一部分。

---

## 12. 版本与发布规范

### 12.1 版本号

采用三级版本：

$$
\texttt{major.minor.patch}
$$


- `major`：协议对象变化；
- `minor`：新增系统 / split / 任务 / 观测；
- `patch`：修复 manifest 或生成瑕疵，不改变语义。

### 12.2 发布冻结原则

每次正式发布必须冻结：

- 系统列表；
- 参数范围；
- 观测模式；
- split 定义；
- 任务定义；
- 指标定义；
- 生成器 commit hash。

### 12.3 兼容性原则

新版本只能新增，不应破坏旧版本 benchmark 的可复现性。

---

## 13. 测试规范

### 13.1 单元测试

应覆盖：

- 动力系统生成接口；
- 观测链接口；
- split 生成一致性；
- 窗口对象长度与索引合法性；
- manifest 完整性。

### 13.2 集成测试

至少包含三个内部系统：

- 线性对角；
- 旋转–收缩；
- Jordan / 非正规。

每次修改协议层都必须先通过这三个系统的 smoke test。

### 13.3 回归测试

固定一组小规模 benchmark，比较：

- 轨线条数；
- 样本总数；
- split 大小；
- 核心指标统计是否发生非预期偏移。

---

## 14. 最小实施路线

项目启动时按以下顺序推进：

### Phase 0
先实现对象协议：

- `SystemSpec`
- `ObservationSpec`
- `SplitSpec`
- `WindowSpec`
- `TaskSpec`
- `ReleaseManifest`

### Phase 1
接入内部测试系统：

- 线性对角；
- 旋转–收缩；
- Jordan。

### Phase 2
实现三种观测模式：

- 全状态；
- 部分观测；
- 线性混合观测。

### Phase 3
实现三种 split：

- 初值泛化；
- 参数泛化；
- 观测泛化。

### Phase 4
实现三类任务：

- 一步预测；
- 多步 rollout；
- 重构 / 恢复。

### Phase 5
实现统一指标：

- 一步误差；
- rollout 误差；
- 重构误差；
- 长期统计误差；
- 运行代价指标。

### Phase 6
逐步接入 `v1_core` 系统并冻结 `ODEs_dataset-v1.0`。

---

## 15. 结语

**ODEs_dataset 的核心不是“收集若干 ODE 样本”，而是固定一条长期稳定的数据生成、任务构造与评测协议**：

$$
(\mathbf f,\boldsymbol{\mu},\mathbf x_0,\tau)
\Longrightarrow
\mathbf X
\Longrightarrow
\mathbf Z
\Longrightarrow
\text{splits}
\Longrightarrow
\text{windows}
\Longrightarrow
\text{tasks}
\Longrightarrow
\text{metrics}.
$$


只要这条链在工程上被固定住，你之后无论接入哪一种预测器、表示学习器、系统辨识方法、算子学习方法，乃至未来更复杂的扩展任务，都不需要重写数据集本身。
