## 1. Confirmed task summary

本次任务是在 `ODEs_dataset` 中新增一个 **EDMDc 专用受控 Duffing 数据集任务**。  
确认的数学设定是：

- 动力系统采用受控 Duffing
  $$

  \ddot q+\delta \dot q+\alpha q+\beta q^3=b_u\,u(t)
  
$$
- 只扫描非线性强度参数 $\beta$，取 3 档；
- 输入为**随机开环输入**，不是反馈控制；
- 观测固定为**全状态观测**；
- 同时对**状态**与**输入**加噪；
- 每组数据保留
  $$

  \text{clean} + 3\ \text{档 noisy}
  
$$
  共 4 个噪声版本；
- 目标不是在数据集层实现 EDMDc 算法，而是按 ODEs_dataset 协议产出可供下游 EDMDc 直接消费的 `raw / processed / splits / windows / manifests / release` 对象。ODEs_dataset 的工程目标本来就是固定从系统、观测、split、window 到 benchmark task 的数据流水线，而不是把特定算法写进数据集定义。fileciteturn4file0

同时，这个新对象属于 `Duffing` 家族的受控扩展。Duffing 已在你当前的 ODEs 主集合里占有核心位置，因此这里最合理的做法是：**不新开一个完全脱节的体系，而是在 Duffing 注册树下新增 controlled / EDMDc 分支**。新系统接入时也应同时提交 `SystemSpec`、`ObservationSpec`、`SplitSpec`、`TaskSpec`、smoke test 和 manifest 示例。fileciteturn5file0

---

## 2. Task decomposition

建议把整个任务拆成 8 个子任务：

1. 固定受控 Duffing 的系统规格；
2. 固定随机开环输入规格；
3. 固定 clean / noisy 观测规格；
4. 定义面向 EDMDc 的数据对象扩展；
5. 定义 split 与 window；
6. 设计 smoke 与 formal 生成实验；
7. 设计 manifest / release 冻结；
8. 设计面向下游 EDMDc 的接口与诊断输出。

这样做符合 ODEs_dataset 的基本流水线：

$$

\text{系统配置}
\rightarrow
\text{轨线生成}
\rightarrow
\text{观测处理}
\rightarrow
\text{数据保存}
\rightarrow
\text{切分与窗口}
\rightarrow
\text{任务与评测}.

$$
fileciteturn4file0turn5file0

---

## 3. Sub-task specification

### Sub-task A：受控 Duffing `SystemSpec`

**Purpose**  
把受控 Duffing 的连续动力学与参数网格固定成可注册系统。

**Input**  
$$

(\delta,\alpha,\beta,b_u),\quad
\mathbf x_0\in\mathbb R^2,\quad
\tau,\quad
M,\quad
\{u_m\}_{m=1}^{M}.

$$

**Output**  
受控 Duffing 的 `SystemSpec`，以及 3 档 $\beta$ 参数实例。

**Dependency**  
无。

**Relevant math**  
$$

\dot x_1=x_2,\qquad
\dot x_2=-\delta x_2-\alpha x_1-\beta x_1^3+b_u u(t).

$$

**Diagnostic checks**  
检查：

- `state_dim = 2`
- 参数表里只有 $\beta$ 扫描，其他参数固定
- 输入增益 $b_u$ 非零
- 每档 $\beta$ 对应唯一 `parameter_instance_id`

---

### Sub-task B：开环输入规格

**Purpose**  
定义 EDMDc 可辨识的随机开环输入。

**Input**  
输入种子、输入幅值范围、持值长度、采样步长 $\tau$。

**Output**  
输入序列对象
$$

\mathbf U=
\begin{bmatrix}
u_1&\cdots&u_M
\end{bmatrix}\in\mathbb R^{1\times M}.

$$

**Dependency**  
A。

**Relevant math**  
采用 ZOH：
$$

u(t)=u_m,\qquad t\in[t_m,t_{m+1}).

$$

**Diagnostic checks**  

- 输入长度是否为 $M$，而不是 $M+1$
- 输入均值、方差、幅值上界
- 相邻区间是否存在足够变化
- 输入经验秩与激励强度是否过低

---

### Sub-task C：clean / noisy `ObservationSpec`

**Purpose**  
在全状态观测下，生成 clean 与三档 noisy 版本，并把噪声同时作用于状态与输入。

**Input**  
clean 轨线 $\mathbf X$、clean 输入 $\mathbf U$、噪声档位 $\eta$。

**Output**  
4 种观测版本：
$$

(\mathbf Z^{(0)},\mathbf U^{(0)}),\ 
(\mathbf Z^{(\eta_1)},\mathbf U^{(\eta_1)}),\ 
(\mathbf Z^{(\eta_2)},\mathbf U^{(\eta_2)}),\ 
(\mathbf Z^{(\eta_3)},\mathbf U^{(\eta_3)}).

$$

**Dependency**  
A, B。

**Relevant math**  
$$

\mathbf z_m^{(\eta)}=\mathbf x_m+\boldsymbol\varepsilon_{x,m}^{(\eta)},
\qquad
\tilde u_m^{(\eta)}=u_m+\varepsilon_{u,m}^{(\eta)}.

$$

**Diagnostic checks**

- clean 版本必须满足
  $$

  \mathbf Z^{(0)}=\mathbf X,\qquad \mathbf U^{(0)}=\mathbf U
  
$$
- 状态噪声与输入噪声分开记录
- 每个噪声档位的实际 RMS 接近目标档位
- 不允许 noisy 版本覆盖 clean 数据

---

### Sub-task D：EDMDc 友好的轨线数据对象

**Purpose**  
在现有 `RawTrajectory` / `ObservedTrajectory` 协议基础上，补足控制输入相关字段。

**Input**  
状态轨线、观测轨线、输入轨线、参数实例、噪声实例。

**Output**  
受控版本轨线对象：

- raw：$\mathbf X,\mathbf U$
- processed：$\mathbf Z,\widetilde{\mathbf U}$

**Dependency**  
A, B, C。

**Relevant math**  
状态快照与观测快照仍按列存储：
$$

\mathbf X\in\mathbb R^{2\times(M+1)},\qquad
\mathbf Z\in\mathbb R^{2\times(M+1)},\qquad
\mathbf U\in\mathbb R^{1\times M}.

$$

**Diagnostic checks**

- 状态列数是 $M+1$
- 输入列数是 $M$
- `trajectory_id`、`parameter_instance`、`observation_id`、`noise_level_id` 一致
- 不能把控制输入混进状态矩阵维度里

---

### Sub-task E：split 设计

**Purpose**  
保证 EDMDc 训练、验证、测试的轨线级切分。

**Input**  
全部轨线索引、$\beta$ 网格、噪声网格、输入种子与初值种子。

**Output**  
至少两类官方 split：

- `Split-I-control`：初值泛化；
- `Split-P-beta`：$\beta$ 泛化。

**Dependency**  
D。

**Relevant math**  
先分轨线编号：
$$

\mathcal R_{\text{train}},\ \mathcal R_{\text{val}},\ \mathcal R_{\text{test}},

$$
再在各自内部切窗口。

**Diagnostic checks**

- 绝不先切窗口再分 train/test
- 同一条轨线不得跨 split
- `Split-P-beta` 中训练与测试的 $\beta$ 集合分离
- clean/noisy 版本的 split 关系保持一致

这个“先按轨线切，再按窗口切”的原则是必须固定的。fileciteturn5file0turn5file13

---

### Sub-task F：window 与 task 设计

**Purpose**  
为 EDMDc 下游消费定义一步样本与 rollout 窗口。

**Input**  
轨线级 `ObservedTrajectory`。

**Output**  

1. `OneStepControlledSample`
$$

(\mathbf z_m,\tilde u_m,\mathbf z_{m+1})

$$

2. `RolloutControlledSample`
$$

(\mathbf z_s,\tilde u_s,\dots,\tilde u_{s+L-1},\mathbf z_{s+1},\dots,\mathbf z_{s+L})

$$

3. 可选 `StateOneStepControlledSample`
$$

(\mathbf x_m,u_m,\mathbf x_{m+1})

$$
用于 clean 基准回归。

**Dependency**  
E。

**Relevant math**  
EDMDc 一步回归对象：
$$

\boldsymbol\Psi_1
\approx
\begin{bmatrix}\mathbf K&\mathbf B\end{bmatrix}
\begin{bmatrix}\boldsymbol\Psi_0\\ \widetilde{\mathbf U}_0\end{bmatrix}.

$$

**Diagnostic checks**

- one-step 样本数应为每条轨线 $M$
- rollout horizon $L$ 时样本数应为 $M-L+1$
- 所有窗口都必须保持输入与状态时刻对齐

---

### Sub-task G：smoke / formal 生成实验

**Purpose**  
先验证协议和维度，再生成正式版本。

**Input**  
small 与 medium 两档数据配置。

**Output**  

- smoke：极小规模、单 $\beta$、clean + 1 档 noisy；
- formal：3 档 $\beta$ × 4 档噪声 × 多轨线。

**Dependency**  
F。

**Relevant math**  
仍遵循统一数据流水线，不在数据集层嵌入 EDMDc 训练。fileciteturn5file4

**Diagnostic checks**

- smoke 能快速产出完整 release 树
- formal 才启用完整参数网格
- smoke 与 formal 的对象协议完全一致，只是规模不同

---

### Sub-task H：manifest / release 冻结

**Purpose**  
把本次 controlled Duffing EDMDc 数据作为可复现 release 冻结。

**Input**  
系统配置、观测配置、split、windows、tasks、生成器元信息。

**Output**  
`ReleaseManifest` 与 release 索引。

**Dependency**  
G。

**Relevant math**  
冻结对象至少包括：

- system list
- parameter range
- observation modes
- split definitions
- task definitions
- metric definitions
- generator commit hash

**Diagnostic checks**

- 版本号按 `major.minor.patch`
- 新增系统/观测/任务应提升 `minor`
- 不覆盖旧版本 release

这与 ODEs_dataset 的版本与发布规则一致。fileciteturn5file3

---

## 4. Directory and file plan

下面按 **ODEs_dataset** 目录来规划，因为本任务本质上是数据集工程，不是下游 Koopman 训练工程。ODEs_dataset 的目录蓝图、职责分层、`configs/src/data/experiments/reports/test` 的职责已经明确固定。fileciteturn4file0turn5file9

### 文档

- `docs/notes/mathematical explanation/EDMDc_controlled_duffing_math.md`  
  本任务的数学说明书。

- `docs/notes/code explanation/EDMDc_controlled_duffing_plan.md`  
  本次详细任务计划书。

- `docs/notes/file explanation/EDMDc_controlled_duffing_files.md`  
  完成后补写的文件说明。

- `docs/spec/object_registry.md`  
  追加一条本次对象注册记录。

- `docs/spec/project_task_list.md`  
  追加本任务状态、版本、配置摘要。

### 配置

- `configs/systems/duffing_controlled_edmdc.json`  
  受控 Duffing 系统族配置；固定 $\delta,\alpha,b_u$，扫描 $\beta$。

- `configs/observations/duffing_controlled_fullstate_clean.json`  
  全状态 clean 观测配置。

- `configs/observations/duffing_controlled_fullstate_noise_s1.json`
- `configs/observations/duffing_controlled_fullstate_noise_s2.json`
- `configs/observations/duffing_controlled_fullstate_noise_s3.json`  
  三档状态+输入噪声配置。

- `configs/splits/duffing_controlled_split_I.json`  
  初值泛化 split。

- `configs/splits/duffing_controlled_split_P_beta.json`  
  $\beta$ 泛化 split。

- `configs/windows/duffing_controlled_one_step.json`  
  一步受控样本窗口。

- `configs/windows/duffing_controlled_rollout_short.json`  
  短 rollout 窗口。

- `configs/tasks/duffing_controlled_edmdc_one_step.json`  
  EDMDc 一步辨识任务。

- `configs/tasks/duffing_controlled_edmdc_rollout.json`  
  EDMDc 开环 rollout 任务。

- `configs/benchmarks/duffing_controlled_edmdc_smoke.json`
- `configs/benchmarks/duffing_controlled_edmdc_formal.json`

- `configs/releases/ODEs_dataset_controlled_duffing_edmdc_v1.json`  
  发布清单。

### 源码

- `src/dynamics/duffing_controlled.jl`  
  定义受控 Duffing 右端。

- `src/observations/controlled_noise_models.jl`  
  增加“状态噪声 + 输入噪声”观测处理。

- `src/generators/generate_controlled_duffing.jl`  
  生成受控 Duffing raw / processed 轨线。

- `src/datasets/controlled_trajectory_types.jl`  
  定义带输入字段的轨线数据对象。

- `src/splits/controlled_split_builders.jl`  
  构造轨线级 split。

- `src/windows/controlled_windows.jl`  
  构造一步和 rollout 受控窗口。

- `src/tasks/edmdc_tasks.jl`  
  定义 EDMDc 一步与 rollout 数据任务对象。

- `src/diagnostics/controlled_duffing_diagnostics.jl`  
  数据规模、噪声、输入激励、轨线稳定性诊断。

- `src/manifests/controlled_release_manifest.jl`  
  生成 release manifest。

- `src/io/controlled_dataset_io.jl`  
  统一存取 raw / processed / split / window / manifest。

- `src/registries/register_controlled_duffing.jl`  
  注册系统、观测、split、task、benchmark。

### 数据与发布

- `data/raw/duffing_controlled_edmdc/`
- `data/processed/duffing_controlled_edmdc/`
- `data/manifests/duffing_controlled_edmdc/`
- `data/releases/duffing_controlled_edmdc/`

其中建议按层级再分：

$$

\beta\text{-level} \rightarrow \text{noise-level} \rightarrow \text{split/version}.

$$

### 实验

- `experiments/smoke_tests/run_duffing_controlled_edmdc_smoke.jl`
- `experiments/baseline_identification/run_duffing_controlled_edmdc_formal.jl`

### 报告

- `reports/tables/duffing_controlled_edmdc_dataset_summary.csv`
- `reports/tables/duffing_controlled_edmdc_split_summary.csv`
- `reports/tables/duffing_controlled_edmdc_noise_summary.csv`

- `reports/plots/duffing_controlled_edmdc_example_trajectories.png`
- `reports/plots/duffing_controlled_edmdc_example_inputs.png`
- `reports/plots/duffing_controlled_edmdc_phase_portraits.png`
- `reports/plots/duffing_controlled_edmdc_noise_checks.png`

- `reports/logs/duffing_controlled_edmdc_smoke.log`
- `reports/logs/duffing_controlled_edmdc_formal.log`

### 测试

- `test/unit/test_duffing_controlled_dynamics.jl`
- `test/unit/test_controlled_noise_models.jl`
- `test/unit/test_controlled_window_alignment.jl`
- `test/unit/test_controlled_manifest_fields.jl`

- `test/integration/test_duffing_controlled_smoke_pipeline.jl`

- `test/regression/test_duffing_controlled_dataset_counts.jl`
- `test/regression/test_duffing_controlled_noise_statistics.jl`

---

## 5. Module / component responsibilities

### `src/dynamics/`
只负责系统本体：
$$

\dot{\mathbf x}=\mathbf f(\mathbf x,u;\beta).

$$
不负责噪声，不负责 split，不负责窗口。

### `src/observations/`
只负责：
$$

(\mathbf X,\mathbf U)\mapsto(\mathbf Z,\widetilde{\mathbf U}),

$$
包括全状态观测、状态噪声、输入噪声、归一化元信息。

### `src/generators/`
负责把 `SystemSpec + ObservationSpec` 变成轨线数据。

### `src/datasets/`
负责定义：

- raw controlled trajectory
- observed controlled trajectory
- controlled one-step sample
- controlled rollout sample

### `src/splits/`
负责轨线级划分，不切窗口。

### `src/windows/`
负责在 split 内切受控窗口，保证
$$

(\mathbf z_m,\tilde u_m,\mathbf z_{m+1})

$$
时刻对齐。

### `src/tasks/`
负责把窗口对象声明为 benchmark task，而不是再做数值积分。

### `src/diagnostics/`
负责检查：

- 输入激励是否足够；
- 轨线是否爆炸；
- 噪声是否达到目标 RMS；
- 各数据版本样本数是否一致。

### `src/manifests/`
负责冻结：

- system_id
- observation_id
- split_id
- task_id
- benchmark_version
- solver metadata
- random seed policy

### `src/io/`
负责路径、文件名、读写协议统一。

### `src/registries/`
负责让 controlled Duffing 以注册对象进入工程，而不是把逻辑散落在脚本里。  
这也符合“协议先于具体实验”的原则。fileciteturn5file2turn4file0

---

## 6. Planned `##` sections

下面给出每个计划 Julia 文件的预期 `##` 分节标题。

### `src/dynamics/duffing_controlled.jl`

- `## 受控 Duffing 系统参数与维度约定`
- `## 连续时间右端函数定义`
- `## 零阶保持开环输入约定`
- `## 参数实例与 beta 网格检查`
- `## 受控 Duffing 数值稳定性辅助检查`

### `src/observations/controlled_noise_models.jl`

- `## 全状态观测映射`
- `## 状态噪声模型`
- `## 输入噪声模型`
- `## clean 与 noisy 观测对象构造`
- `## 噪声强度与尺度诊断`

### `src/generators/generate_controlled_duffing.jl`

- `## 生成器输入配置解析`
- `## 初值与开环输入采样`
- `## clean 状态轨线积分`
- `## clean 与 noisy 观测轨线生成`
- `## raw 与 processed 数据落盘`
- `## 生成日志与元信息写入`

### `src/datasets/controlled_trajectory_types.jl`

- `## 原始受控轨线对象定义`
- `## 观测受控轨线对象定义`
- `## 受控一步样本对象定义`
- `## 受控 rollout 窗口对象定义`
- `## 维度一致性检查`

### `src/splits/controlled_split_builders.jl`

- `## 轨线级 split 输入与分组键`
- `## 初值泛化 split 构造`
- `## beta 泛化 split 构造`
- `## clean 与 noisy 对齐规则`
- `## split 完整性与泄漏检查`

### `src/windows/controlled_windows.jl`

- `## 受控一步窗口构造`
- `## 受控 rollout 窗口构造`
- `## 输入与状态时刻对齐检查`
- `## 窗口长度与样本数统计`
- `## 窗口对象导出接口`

### `src/tasks/edmdc_tasks.jl`

- `## EDMDc 一步辨识任务对象`
- `## EDMDc 开环 rollout 任务对象`
- `## clean 基准任务与 noisy 鲁棒性任务`
- `## 任务元信息与评测键`
- `## 任务对象一致性检查`

### `src/diagnostics/controlled_duffing_diagnostics.jl`

- `## 数据规模与维度统计`
- `## 输入激励强度与覆盖性检查`
- `## 轨线幅值与数值稳定性检查`
- `## 状态噪声与输入噪声统计`
- `## split 与 window 汇总诊断`

### `src/manifests/controlled_release_manifest.jl`

- `## release 元字段定义`
- `## system observation split task 引用写入`
- `## 版本号与 commit 信息冻结`
- `## 数据路径索引写入`
- `## manifest 完整性检查`

### `experiments/smoke_tests/run_duffing_controlled_edmdc_smoke.jl`

- `## smoke 配置载入`
- `## 小规模数据生成`
- `## 基本诊断与汇总表输出`
- `## smoke manifest 与日志保存`

### `experiments/baseline_identification/run_duffing_controlled_edmdc_formal.jl`

- `## formal 配置载入`
- `## 全参数网格生成`
- `## split 与窗口派生`
- `## 正式诊断表与图输出`
- `## release 冻结与日志保存`

---

## 7. Data flow and dimensions

完整数据流建议固定为：

$$

(\beta_i,\mathbf x_0^{(r)},u_{1:M}^{(r)})
\rightarrow
\mathbf X^{(r,i)}
\rightarrow
(\mathbf Z^{(r,i,\eta)},\widetilde{\mathbf U}^{(r,\eta)})
\rightarrow
\text{split}
\rightarrow
\text{windows}
\rightarrow
\text{EDMDc task}.

$$

### 连续阶段

单条轨线状态：
$$

\mathbf x_m\in\mathbb R^2,\qquad m=1,\dots,M+1.

$$

单步输入：
$$

u_m\in\mathbb R,\qquad m=1,\dots,M.

$$

### 轨线矩阵

raw 状态：
$$

\mathbf X\in\mathbb R^{2\times(M+1)}.

$$

processed 状态观测：
$$

\mathbf Z\in\mathbb R^{2\times(M+1)}.

$$

输入矩阵：
$$

\mathbf U,\widetilde{\mathbf U}\in\mathbb R^{1\times M}.

$$

### one-step 样本

每个样本：
$$

(\mathbf z_m,\tilde u_m,\mathbf z_{m+1}),

$$
其中
$$

\mathbf z_m,\mathbf z_{m+1}\in\mathbb R^2,\qquad
\tilde u_m\in\mathbb R.

$$

若一条轨线长度为 $M+1$，则 one-step 样本数为：
$$

M.

$$

### rollout 样本

起点 $s$、窗口长度 $L$ 时：
$$

\mathbf z_s\in\mathbb R^2,
\qquad
(\tilde u_s,\dots,\tilde u_{s+L-1})\in\mathbb R^{L},
\qquad
(\mathbf z_{s+1},\dots,\mathbf z_{s+L})\in\mathbb R^{2\times L}.

$$

单条轨线可形成的 rollout 样本数：
$$

M-L+1.

$$

### 参数与噪声索引

- $\beta$ 维：3 档
- 噪声维：4 档（含 clean）
- 输入种子维：$N_u$
- 初值种子维：$N_{x_0}$

总轨线数为：
$$

R_{\text{total}}
=
3\times 4\times N_u\times N_{x_0}

$$
若每条轨线都独立生成。

更稳妥的是把 clean 状态轨线按 $\beta$ 与轨线种子生成一次，再派生 4 档观测噪声版本。这样 raw 与 processed 的层级更清晰，也更符合 `raw / processed / manifests / releases` 分离原则。fileciteturn5file6turn5file12

---

## 8. Package and documentation plan

后续实现时，建议按功能检查官方文档，不凭记忆写 API。

### 可能需要的 Julia 包方向

- `DifferentialEquations.jl`  
  用于受控 Duffing 数值积分；要重点查时间依赖输入和 ZOH 输入的实现方式。

- `LinearAlgebra`  
  用于后续数据诊断中的秩、条件数、范数。

- `Statistics`  
  用于计算 RMS、标准差、均值与方差。

- `Random`  
  用于初值、输入序列与噪声的可复现采样。

- `JLD2.jl` 或 `HDF5.jl`  
  用于保存矩阵、对象和 manifest 索引。

- `JSON3.jl` 或 `TOML.jl`  
  用于声明式配置。

- `DataFrames.jl`、`CSV.jl`  
  用于汇总表。

- `Plots.jl` 或 `Makie.jl`  
  用于轨线图、相图、输入图、噪声检查图。

### 需要重点查文档的问题

1. time-dependent / piecewise-constant forcing 的标准写法；
2. 高精度积分与固定采样输出的接口；
3. 大矩阵与对象的稳定存盘格式；
4. 配置解析时的数值类型一致性；
5. 随机种子在系统采样、输入采样、噪声采样中的分层管理。

---

## 9. Debugging and inspection plan

本任务最该优先检查的不是“图好不好看”，而是“对象对不对、时刻齐不齐、噪声打没打对”。

### 必打出的量

- 每条轨线的
  $$

  \text{state size}=(2,M+1),\quad
  \text{input size}=(1,M)
  
$$
- 每个 $\beta$ 档、每个噪声档的轨线条数
- 每个 split 的轨线条数与窗口条数
- one-step 与 rollout 样本总数
- 状态最大幅值、速度最大幅值
- 输入均值、标准差、最大绝对值
- 实际噪声 RMS 与目标噪声档位

### 必画的图

- clean 状态时序图
- clean 相图
- 开环输入序列图
- noisy 与 clean 对比图
- 三档 $\beta$ 的代表性相图
- 三档噪声的代表性观测图

### 必保存的表

- `dataset_summary`
- `split_summary`
- `noise_summary`
- `window_summary`

### 必检查的矩阵级对象

对任一代表性子集，要直接检查：

$$

\mathbf X,\ \mathbf Z,\ \mathbf U,\ \widetilde{\mathbf U},

$$
以及 EDMDc 下游将使用的

$$

\mathbf Z_0,\ \mathbf Z_1,\ \widetilde{\mathbf U}_0.

$$

---

## 10. Expected outputs

完成后，预期应产出以下结果。

### 数据对象

- clean raw 状态轨线；
- clean / noisy processed 观测轨线；
- 输入轨线及其 noisy 版本；
- split 索引；
- one-step 受控窗口；
- rollout 受控窗口；
- release manifest。

### 人类可读输出

- 数据规模表；
- split 统计表；
- 噪声统计表；
- 代表性轨线图；
- 代表性输入图；
- 代表性相图；
- smoke / formal 运行日志。

### 下游 EDMDc 直接可用对象

至少应能无歧义读取：

$$

(\mathbf z_m,\tilde u_m,\mathbf z_{m+1})

$$
和
$$

(\mathbf z_s,\tilde u_s,\dots,\tilde u_{s+L-1},\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

### 版本化输出

- `dataset_version`
- `system_id`
- `observation_id`
- `split_id`
- `window_id`
- `task_id`
- `benchmark_version`
- `solver_metadata`

这些都应写入 manifest 与 release 索引中。fileciteturn5file3turn5file12

---

## 11. Failure points and debugging strategies

### Failure 1：状态与输入时刻错位

**现象**  
EDMDc 快照矩阵列数对不上，或 rollout 时输入提前/滞后一步。

**诊断**  
直接检查：

$$

\mathbf Z_0\in\mathbb R^{2\times M},\quad
\mathbf Z_1\in\mathbb R^{2\times M},\quad
\widetilde{\mathbf U}_0\in\mathbb R^{1\times M}.

$$

**处理**  
统一约定输入作用于
$$

[t_m,t_{m+1})

$$
区间，并强制 one-step 样本为
$$

(\mathbf z_m,\tilde u_m,\mathbf z_{m+1}).

$$

---

### Failure 2：随机输入激励不足

**现象**  
不同轨线输入几乎相同，后续 EDMDc 回归退化。

**诊断**  
检查输入标准差、频带变化、分段变化次数。

**处理**  
提高输入幅值范围、缩短持值时长、增加随机种子数。

---

### Failure 3：高 $\beta$ 下轨线爆炸或极端幅值

**现象**  
状态幅值过大，产生数值不稳定或噪声尺度失真。

**诊断**  
统计每条轨线的
$$

\max |q|,\ \max |v|

$$
并画代表性相图。

**处理**  
缩小初值范围、缩小输入幅值、调整固定阻尼 $\delta$、缩短轨线长度或加 burn-in 控制。

---

### Failure 4：状态噪声与输入噪声尺度失衡

**现象**  
输入噪声过小几乎无效，或过大导致控制信号失真。

**诊断**  
分别统计 state noise RMS 与 input noise RMS。

**处理**  
为状态和输入设分离的参考尺度，不共用一个绝对方差。

---

### Failure 5：clean/noisy 版本未严格配对

**现象**  
同一个 trajectory_id 在 clean 与 noisy 版本上轨线不一致，导致鲁棒性比较失真。

**诊断**  
检查 clean 状态轨线是否是 noisy 版本的同一底座。

**处理**  
先生成 clean raw，再派生 noisy processed，不重复积分。

---

### Failure 6：split 泄漏

**现象**  
同一轨线的不同窗口进入 train 和 test。

**诊断**  
检查 `trajectory_id` 在 split 中是否重复。

**处理**  
只按轨线切分，再切窗口。这个规则不能破。fileciteturn5file0turn5file13

---

## 12. Stop before code

这里到此停止。  
以上是 Step 2 的任务计划书，不包含代码实现。下一步应单独进入实现请求，再开始写具体 Julia 文件。