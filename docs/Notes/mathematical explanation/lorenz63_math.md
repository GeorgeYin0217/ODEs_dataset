## Step 1：Lorenz ’63 系统数学说明

### 1. Task understanding

本次任务是在 **ODEs_dataset** 中新增经典 **Lorenz ’63** 系统，作为 `v1_core` 中的低维混沌 benchmark。项目系统指南已将 Lorenz ’63 放入 `v1_core`，其定位是测试耗散混沌、短期可预报、长期失相、谱稳定性与统计保持能力。fileciteturn0file0

第一版建议采用：

- 三维自治连续时间 ODE；
- 标准 Lorenz 参数；
- 无控制输入；
- 全状态观测；
- 多初值轨道族；
- 重点诊断混沌吸引子几何、数值稳定性、有限时间发散率和长期统计量。

目标输出是若干条离散轨线：

$$

\{\mathbf x_m^{(q)}\}_{m=0}^{M},\qquad q=1,\dots,R,

$$

并通过项目统一观测链得到：

$$

\mathbf z_m^{(q)}
=
Z\circ S\circ U(\mathbf x_m^{(q)}).

$$

在全状态观测的第一版中，

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,

$$

因此

$$

\mathbf z_m=\mathbf x_m.

$$

这也符合项目规范中“动力系统状态 $\mathbf x$”与“算法输入 $\mathbf z$”通过观测链解耦的设定。fileciteturn0file1

---

### 2. Mathematical objects and dimensions

Lorenz ’63 状态变量为

$$

\mathbf x(t)
=
\begin{bmatrix}
x(t)\\
y(t)\\
z(t)
\end{bmatrix}
\in\mathbb R^3.

$$

状态维数：

$$

d_x=3.

$$

第一版全状态观测：

$$

\mathbf z(t)=\mathbf x(t),
\qquad
d_z=3.

$$

连续时间系统写为

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;\boldsymbol\mu),

$$

其中参数向量为

$$

\boldsymbol\mu=(\sigma,\rho,\beta).

$$

经典 Lorenz ’63 方程为

$$

\begin{aligned}
\dot x &= \sigma (y-x),\\
\dot y &= x(\rho-z)-y,\\
\dot z &= xy-\beta z.
\end{aligned}

$$

第一版建议使用标准混沌参数：

$$

\sigma=10,\qquad
\rho=28,\qquad
\beta=\frac{8}{3}.

$$

在该参数下，系统是三维非线性自治耗散系统。轨线矩阵按项目约定列优先保存为

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_0^{(q)}&
\mathbf x_1^{(q)}&
\cdots&
\mathbf x_M^{(q)}
\end{bmatrix}
\in\mathbb R^{3\times (M+1)}.

$$

全状态观测时，

$$

\mathbf Z^{(q)}
=
\mathbf X^{(q)}
\in\mathbb R^{3\times (M+1)}.

$$

项目规范也要求原始状态轨线和观测轨线作为不同数据对象处理，即 `RawTrajectory` 与 `ObservedTrajectory` 分离。fileciteturn0file1

---

### 3. Core formulas / numerical procedures

#### 3.1 连续时间流与离散采样

令 $\Phi^t$ 表示 Lorenz 系统的连续时间流映射，则

$$

\mathbf x(t+\tau)
=
\Phi^\tau(\mathbf x(t)).

$$

采样步长为 $\tau>0$，离散快照为

$$

\mathbf x_m
=
\mathbf x(t_m),
\qquad
t_m=t_0+m\tau.

$$

离散动力学可写成

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m),
\qquad
\mathbf F^\tau=\Phi^\tau.

$$

#### 3.2 耗散性诊断

Lorenz ’63 的向量场散度为

$$

\nabla\cdot \mathbf f
=
\frac{\partial \dot x}{\partial x}
+
\frac{\partial \dot y}{\partial y}
+
\frac{\partial \dot z}{\partial z}
=
-\sigma-1-\beta.

$$

在标准参数下，

$$

\nabla\cdot \mathbf f
=
-10-1-\frac83
=
-\frac{41}{3}<0.

$$

因此系统是体积压缩的耗散系统。数值数据应呈现出轨线进入有界吸引子区域的行为。

#### 3.3 平衡点

平衡点满足

$$

\dot x=\dot y=\dot z=0.

$$

当 $\rho>1$ 时，有三个平衡点：

$$

\mathbf x_\ast^{(0)}
=
(0,0,0)^\top,

$$

以及

$$

\mathbf x_\ast^{(\pm)}
=
\left(
\pm \sqrt{\beta(\rho-1)},
\ \pm \sqrt{\beta(\rho-1)},
\ \rho-1
\right)^\top.

$$

在标准参数下，

$$

\sqrt{\beta(\rho-1)}
=
\sqrt{\frac83\cdot 27}
=
\sqrt{72}
=
6\sqrt{2},

$$

所以两个非零平衡点为

$$

(6\sqrt2,6\sqrt2,27)^\top,
\qquad
(-6\sqrt2,-6\sqrt2,27)^\top.

$$

这些平衡点可作为相图诊断参考，而不是训练目标。

#### 3.4 Jacobian 与局部稳定性诊断

Lorenz 向量场的 Jacobian 为

$$

D\mathbf f(\mathbf x)
=
\begin{bmatrix}
-\sigma & \sigma & 0\\
\rho-z & -1 & -x\\
y & x & -\beta
\end{bmatrix}.

$$

它可用于：

- 检查局部线性化是否合理；
- 估计局部伸缩方向；
- 诊断数值积分是否进入异常区域；
- 后续估计有限时间 Lyapunov 指标。

#### 3.5 一步样本与 rollout 窗口

项目规范中，一步样本为

$$

(\mathbf z_m,\mathbf z_{m+1}),

$$

多步 rollout 窗口为

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

对 Lorenz ’63，第一版可保留这两类任务对象：

$$

\mathbf z_m\in\mathbb R^3,
\qquad
\mathbf z_{s:s+L}\in\mathbb R^{3\times(L+1)}.

$$

由于 Lorenz 是混沌系统，长期 rollout 误差不应被解释为逐点长期精确预测；更合理的长期目标是统计保持、吸引子几何保持、短期 forecast horizon 和误差增长率诊断。

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

#### 4.1 参数固定

第一版固定

$$

\boldsymbol\mu_0
=
(10,28,8/3).

$$

暂不做参数泛化。后续可以扩展 $\rho$、$\sigma$、$\beta$ 的参数族，但不建议在第一版混入。

#### 4.2 初值族采样

从某个初值区域

$$

\mathcal X_0\subset\mathbb R^3

$$

采样多条初值：

$$

\mathbf x_0^{(q)}\sim \mathcal P_0,
\qquad q=1,\dots,R.

$$

初值区域应避免只在吸引子上采样，否则无法观察瞬态进入吸引子的过程；也应避免离吸引子过远，否则可能导致过长 transient 或数值尺度过大。

#### 4.3 数值积分

对每个初值，积分连续系统得到高精度轨线：

$$

\mathbf x^{(q)}(t),
\qquad t\in[0,T].

$$

再以固定采样步长 $\tau$ 形成离散序列：

$$

\mathbf x_m^{(q)}
=
\mathbf x^{(q)}(m\tau),
\qquad m=0,\dots,M.

$$

#### 4.4 transient 处理

Lorenz 系统通常需要丢弃初始 transient。若总积分长度为

$$

T_{\mathrm{total}}
=
T_{\mathrm{burn}}+T_{\mathrm{keep}},

$$

则只保存

$$

t\in[T_{\mathrm{burn}},T_{\mathrm{total}}]

$$

上的轨线作为正式数据。这样数据更集中于吸引子区域。

#### 4.5 观测链

第一版全状态观测：

$$

\mathbf z_m^{(q)}=\mathbf x_m^{(q)}.

$$

后续版本可加入：

$$

\mathbf z_m=H\mathbf x_m+\boldsymbol\varepsilon_m

$$

的部分观测或线性混合观测，以及非线性传感器观测。项目规范本身要求动力系统与观测链解耦，因此 Lorenz 的系统定义不应绑定某一个观测模式。fileciteturn0file1

#### 4.6 轨线级切分

数据切分应以整条轨线为单位：

$$

\mathcal Q_{\mathrm{train}},
\qquad
\mathcal Q_{\mathrm{val}},
\qquad
\mathcal Q_{\mathrm{test}}.

$$

禁止先切窗口再随机分配，因为相邻窗口会导致训练/测试泄漏。项目规范明确要求先按轨线切，再在各集合内部生成窗口。fileciteturn0file1

#### 4.7 诊断对象

Lorenz ’63 的核心诊断不应只看轨线图，还应包括：

$$

\min_m x_m,\quad \max_m x_m,
\quad
\min_m y_m,\quad \max_m y_m,
\quad
\min_m z_m,\quad \max_m z_m,

$$

以及：

- 是否出现 `NaN` 或 `Inf`；
- 是否进入有界吸引子区域；
- 坐标尺度是否合理；
- 是否呈现双翼结构；
- 各轨线长度是否一致；
- 采样步长是否过粗；
- transient 是否充分丢弃；
- 轨线之间是否有足够初值差异。

---

### 5. Key assumptions

第一版建议固定以下假设。

#### 5.1 系统假设

- 连续时间自治 ODE；
- 状态空间为 $\mathbb R^3$；
- 参数固定为标准混沌参数；
- 无控制输入；
- 无外部强迫；
- 不加入随机扰动。

#### 5.2 观测假设

- 全状态观测；
- 无观测噪声；
- 无非线性传感器；
- 暂不归一化或仅保存归一化元信息，不改变 raw state 语义。

即

$$

\mathbf z_m=\mathbf x_m.

$$

#### 5.3 数据切分假设

- 按轨线编号切分；
- train / val / test 不共享同一条轨线；
- 窗口只在各自 split 内部生成；
- 第一版做初值泛化 split，不做参数泛化 split。

#### 5.4 任务假设

Lorenz ’63 在 benchmark 中主要服务：

- 一步预测；
- 短期多步 rollout；
- 长期统计比较；
- 吸引子几何诊断；
- Koopman / EDMD / Neural Koopman / HSKL 的混沌系统压力测试。

不建议把长期逐点预测误差作为唯一核心指标，因为混沌系统的长期相位失配是动力学本身的性质。

---

### 6. Numerical risks

#### 6.1 采样步长过大

若 $\tau$ 太大，离散轨线会丢失 Lorenz 吸引子的细节结构，并导致一步样本过难，表现为：

$$

\|\mathbf z_{m+1}-\mathbf z_m\|_2

$$

异常偏大，局部动态不连续感增强。

#### 6.2 采样步长过小

若 $\tau$ 太小，相邻样本高度相关，短期预测任务可能过于简单，且窗口样本有效信息密度下降。

#### 6.3 transient 过短

若 burn-in 时间不足，数据会混入大量靠近初值区域的瞬态轨线，导致训练集统计分布与吸引子分布不一致。

#### 6.4 轨线太短

Lorenz 混沌系统需要足够长的时间覆盖双翼吸引子。如果每条轨线太短，可能只覆盖单侧翼或局部片段，导致训练/测试统计偏差。

#### 6.5 数值积分误差累积

Lorenz 对初值和数值扰动敏感。积分器误差不会导致“逐点轨线永远一致”，但会影响短期预测基准和统计量。因此应保存 solver、容差、步长、随机种子等 manifest 信息。

#### 6.6 归一化风险

三个坐标的典型尺度不同，尤其 $z$ 坐标中心通常较高。如果后续学习器使用统一欧氏误差，未归一化可能让 $z$ 维主导损失；但如果在数据层直接覆盖原始状态，又会破坏物理语义。因此建议 raw 数据保持物理尺度，processed 数据可以附带 normalization policy。

#### 6.7 混沌系统误差解释风险

Lorenz rollout 的长期逐点误差会快速增长，不能简单理解为模型失败。应同时报告：

- 短期 rollout horizon；
- 误差增长曲线；
- 吸引子边际分布；
- 均值、协方差；
- 功率谱或自相关；
- 双翼切换统计。

#### 6.8 维度与存储方向风险

项目约定轨线矩阵为

$$

\mathbf X\in\mathbb R^{d_x\times(M+1)}.

$$

对 Lorenz 即

$$

\mathbf X\in\mathbb R^{3\times(M+1)}.

$$

如果误写成 $(M+1)\times3$，后续窗口、batch、指标和 Koopman 数据接口都会发生维度错位。

---

### 7. Preliminary package direction

这里只给高层包方向，不涉及 API。

- **DifferentialEquations.jl / OrdinaryDiffEq.jl**：用于高精度 ODE 积分。Lorenz 非刚性但混沌敏感，需要检查积分器选择、容差控制、保存采样点的官方文档。
- **Random / StableRNGs.jl**：用于可复现初值采样和 split 生成。需要确保不同轨线、不同 split 的随机种子可追踪。
- **LinearAlgebra / Statistics**：用于基本诊断，例如均值、协方差、范数、Jacobian 相关检查。
- **JLD2 / HDF5 / Arrow 等数据保存包**：用于保存 raw、processed、manifest。具体格式应服从 ODEs_dataset 现有数据协议。
- **Plots.jl 或 Makie.jl**：用于相图、时间序列、吸引子投影、边际分布等可视化。正式实现前应检查当前项目更偏好的绘图库。

工程层面需要注意：ODEs_dataset 负责“数据怎么生成”，Koopman Learning 工程负责“模型怎么训练、评测、保存”，这两层不应混淆。fileciteturn2file0

---

### 8. Wait for confirmation

请你确认或修改这份 Lorenz ’63 数学设定，尤其是以下选择：

- 第一版是否固定标准参数 $(\sigma,\rho,\beta)=(10,28,8/3)$；
- 是否采用全状态观测 $\mathbf z=\mathbf x$；
- 是否只做初值泛化，不做参数泛化；
- 是否加入 burn-in 后再保存吸引子轨线；
- 是否把长期统计诊断作为 Lorenz 的核心诊断之一。

确认后，我再进入 **Step 2：详细代码工程计划书**。