# Step 1：Lotka–Volterra 数学说明书

## 1. Task understanding

本次任务是在 **ODEs_dataset** 项目中新增 `v1_core` 系统对象：**Lotka–Volterra 捕食者–猎物系统**。按照当前数据集协议，系统应先被定义为参数化 ODE，再通过观测链生成算法输入快照：

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
\text{benchmark task}.

$$

这与 ODEs_dataset 文档中“协议库 + 数据工厂 + 评测基座”的定位一致。fileciteturn4file0

本说明书默认第一版采用：

- 二维自治 ODE；
- 无控制输入；
- 标准捕食者–猎物动力学；
- 正参数；
- 正初值；
- 全状态观测；
- 非刚性、非混沌、轨道族泛化版本。

Lotka–Volterra 在你的系统对象规划中属于 `v1_core`，主要用于检查 **非线性耦合、守恒型几何特征、参数可辨识性和轨道族泛化**。fileciteturn4file1

---

## 2. Mathematical objects and dimensions

状态变量定义为

$$

\mathbf x(t)
=
\begin{bmatrix}
x(t)\\
y(t)
\end{bmatrix}
\in \mathbb R_{>0}^{2},

$$

其中：

- $x(t)$：猎物种群；
- $y(t)$：捕食者种群；
- 状态维数 $d_x=2$。

参数向量为

$$

\boldsymbol{\mu}
=
(\alpha,\beta,\gamma,\delta),
\qquad
\alpha,\beta,\gamma,\delta>0,

$$

其中：

- $\alpha$：猎物自然增长率；
- $\beta$：捕食造成的猎物损失系数；
- $\gamma$：捕食者自然死亡率；
- $\delta$：捕食收益转化为捕食者增长的系数。

连续时间系统写为

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;\boldsymbol{\mu})
=
\begin{bmatrix}
\alpha x-\beta xy\\
\delta xy-\gamma y
\end{bmatrix}.

$$

离散采样轨线由流映射给出：

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m),
\qquad
t_m=t_0+(m-1)\tau,
\qquad
m=1,\dots,M.

$$

一条轨线的状态矩阵为

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_1^{(q)} & \mathbf x_2^{(q)} & \cdots & \mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in \mathbb R^{2\times(M+1)}.

$$

第一版全状态观测取

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,

$$

因此

$$

\mathbf z_m=\mathbf x_m,
\qquad
d_z=d_x=2.

$$

这也符合 ODEs_dataset 中“动力系统与观测链解耦”的原则：动力系统只负责生成 $\mathbf x_m$，观测链负责得到最终算法输入 $\mathbf z_m$。fileciteturn4file0

---

## 3. Core formulas / numerical procedures

### 3.1 标准 Lotka–Volterra 方程

$$

\begin{cases}
\dot x = \alpha x-\beta xy,\\
\dot y = \delta xy-\gamma y.
\end{cases}

$$

等价写法为

$$

\begin{cases}
\dot x = x(\alpha-\beta y),\\
\dot y = y(\delta x-\gamma).
\end{cases}

$$

这说明正象限具有不变性：若

$$

x(0)>0,\qquad y(0)>0,

$$

则理想连续系统满足

$$

x(t)>0,\qquad y(t)>0.

$$

### 3.2 平衡点

系统有两个典型平衡点：

$$

\mathbf x_{\mathrm{ext}}
=
\begin{bmatrix}
0\\
0
\end{bmatrix},

$$

以及正平衡点

$$

\mathbf x_\ast
=
\begin{bmatrix}
x_\ast\\
y_\ast
\end{bmatrix}
=
\begin{bmatrix}
\gamma/\delta\\
\alpha/\beta
\end{bmatrix}.

$$

第一版数据集应主要围绕正平衡点附近与中等幅值闭合轨道采样，避免轨线过度靠近坐标轴。

### 3.3 线性化

Jacobian 为

$$

\mathbf J(x,y)
=
\begin{bmatrix}
\alpha-\beta y & -\beta x\\
\delta y & \delta x-\gamma
\end{bmatrix}.

$$

在正平衡点处，

$$

\mathbf J_\ast
=
\begin{bmatrix}
0 & -\beta\gamma/\delta\\
\delta\alpha/\beta & 0
\end{bmatrix}.

$$

其特征值为

$$

\lambda_{\pm}
=
\pm i\sqrt{\alpha\gamma}.

$$

因此经典 Lotka–Volterra 的正平衡点是中心型线性化结构，局部具有振荡特征，但不是渐近稳定极限环。

### 3.4 守恒量

标准二维 Lotka–Volterra 存在一阶守恒量

$$

H(x,y)
=
\delta x-\gamma\log x
+
\beta y-\alpha\log y,
\qquad x>0,\ y>0.

$$

沿真实连续轨线应满足

$$

\frac{d}{dt}H(x(t),y(t))=0.

$$

因此数值生成时可以使用

$$

\Delta H_m
=
H(x_m,y_m)-H(x_1,y_1)

$$

作为重要诊断量。

这也是该系统在 ODEs_dataset 中的独特价值：它不是耗散极限环系统，而是一个具有闭合轨道族和守恒几何的非线性耦合系统。

### 3.5 轨线与窗口对象

单步样本为

$$

(\mathbf z_m,\mathbf z_{m+1})
=
(\mathbf x_m,\mathbf x_{m+1}).

$$

多步 rollout 窗口为

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

对 $R$ 条轨线，数据对象可写为

$$

\left\{
\mathbf Z^{(q)}
\right\}_{q=1}^{R},
\qquad
\mathbf Z^{(q)}\in\mathbb R^{2\times(M+1)}.

$$

切分应按整条轨线进行，而不是先打碎窗口再随机划分；这与项目文档中“先按轨线切，再按窗口切”的原则一致。fileciteturn4file1

---

## 4. Algorithmic logic

数学层面的数据生成逻辑如下。

首先固定一个参数实例

$$

\boldsymbol{\mu}^{(q)}
=
(\alpha^{(q)},\beta^{(q)},\gamma^{(q)},\delta^{(q)}),

$$

以及一个正初值

$$

\mathbf x_0^{(q)}
=
(x_0^{(q)},y_0^{(q)})^\top
\in\mathbb R_{>0}^2.

$$

然后在时间区间

$$

t\in[0,T],
\qquad
T=M\tau

$$

上数值积分连续系统，得到采样点

$$

\mathbf x_m^{(q)}
=
\mathbf x(t_m;\mathbf x_0^{(q)},\boldsymbol{\mu}^{(q)}).

$$

接着施加观测链。第一版全状态观测下，

$$

\mathbf z_m^{(q)}=\mathbf x_m^{(q)}.

$$

最后基于轨线集合构造：

$$

\mathcal R_{\mathrm{train}},
\qquad
\mathcal R_{\mathrm{val}},
\qquad
\mathcal R_{\mathrm{test}},

$$

并在每个集合内部生成 one-step 样本和 rollout 窗口。

---

## 5. Key assumptions

第一版建议采用以下数学假设。

1. **正象限初值**

$$

x_0>0,\qquad y_0>0.

$$

不要从坐标轴或过近坐标轴处采样，因为 $\log x,\log y$ 诊断量会变得敏感，且数值误差可能导致负值。

2. **正参数**

$$

\alpha,\beta,\gamma,\delta>0.

$$

这保证系统具有标准捕食者–猎物解释。

3. **非刚性参数范围**

参数不应导致过快振荡或数量级极端分离。第一版应避免

$$

\alpha\gamma \gg 1

$$

导致的高频振荡，也避免 $\beta,\delta$ 与初值共同造成过强非线性项。

4. **全状态观测**

第一版采用

$$

\mathbf z=\mathbf x.

$$

部分观测、线性混合、非线性传感器和加噪版本可以留到后续观测泛化任务。

5. **轨道族采样**

由于标准 Lotka–Volterra 不是单一吸引子系统，而是围绕正平衡点的一族闭合轨道，所以数据集应覆盖不同能量层

$$

H(x_0,y_0)=c.

$$

这比只在一个初值附近采样更有意义。

---

## 6. Numerical risks

1. **正性破坏**

数值积分误差可能导致

$$

x_m\le 0
\quad\text{或}\quad
y_m\le 0.

$$

这会破坏模型解释，也会使守恒量中的 $\log x,\log y$ 不合法。

2. **守恒量漂移**

标准 Lotka–Volterra 的连续系统守恒，但普通非结构保持积分器可能产生

$$

|H(x_m,y_m)-H(x_1,y_1)|

$$

随时间积累的漂移。该漂移应作为数据质量诊断，而不是忽略。

3. **轨线过近坐标轴**

若初值对应的闭合轨道太大，轨线可能靠近 $x=0$ 或 $y=0$，产生强非线性、时间尺度变化和数值敏感性。

4. **参数尺度不一致**

$\alpha,\beta,\gamma,\delta$ 的尺度会决定正平衡点位置

$$

(x_\ast,y_\ast)=
(\gamma/\delta,\alpha/\beta).

$$

如果参数采样没有约束，正平衡点可能移动到非常大或非常小的区域，导致不同轨线尺度差异过大。

5. **周期依赖参数**

局部角频率近似为

$$

\omega_\ast=\sqrt{\alpha\gamma}.

$$

如果不同参数下 $\omega_\ast$ 差异过大，统一采样步长 $\tau$ 可能对某些轨线过粗，对另一些轨线过密。

6. **归一化风险**

如果后续对 $\mathbf z$ 做标准化，需要记录标准化策略。否则正性、守恒量和物理尺度会被隐藏。对于 benchmark 数据，建议同时保留原始物理状态与处理后观测。

7. **Koopman 表示风险**

标准 Lotka–Volterra 的闭合轨道族不是单一稳定极限环。有限维 Koopman 近似可能对局部轨道表现良好，但跨能量层泛化困难。因此它很适合测试轨道族泛化，但不应期待低阶线性模型在全局精确闭合。

---

## 7. Preliminary package direction

后续进入代码工程计划时，可能需要以下 Julia 包方向，但现在不写代码、不指定未核验 API。

1. **DifferentialEquations.jl / OrdinaryDiffEq.jl**

用于 ODE 数值积分。后续实现前需要查官方文档确认：

- ODEProblem 构造方式；
- solver 选择；
- 保存采样点的方式；
- 容差设置；
- 正性或 domain 相关回调是否需要。

2. **LinearAlgebra**

用于 Jacobian、特征值、范数、条件数等基础诊断。

3. **Random**

用于参数、初值和轨线 split 的可复现采样。

4. **Statistics**

用于轨线均值、方差、尺度检查和统计摘要。

5. **JSON3.jl 或 TOML**

用于读取系统配置、观测配置、split 配置。具体格式应等你确认工程计划时再定。

6. **JLD2.jl / HDF5.jl / Arrow.jl**

用于保存轨线矩阵、manifest 和表格化索引。具体选择需要与 ODEs_dataset 现有存储策略保持一致。

7. **Plots.jl 或 CairoMakie.jl**

用于相图、时间序列图、守恒量漂移图。正式采用哪个绘图库，应在代码计划阶段结合你当前项目习惯确定。

---

## 8. Wait for confirmation

以上是 Lotka–Volterra 系统的第一版数学说明书。请你确认或修改以下关键设定：

- 是否采用标准二维捕食者–猎物形式；
- 第一版是否固定为全状态观测；
- 是否只做正参数、正初值、无控制自治系统；
- 是否把守恒量 $H(x,y)$ 作为主要数据质量诊断；
- smoke 版本是否采用单组标准参数，正式版本再加入轨道族与参数泛化。

你确认后，我再进入 **Step 2：按照 ODEs_dataset 代码工程指南写详细代码工程计划书**。