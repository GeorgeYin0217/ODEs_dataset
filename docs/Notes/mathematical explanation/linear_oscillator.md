## Step 1：线性阻尼振子 / 谐振子的数学说明

### 1. Task understanding

本次任务是构建 `v1_core` 主测试数据集中的第一个系统：**线性阻尼振子 / 谐振子**。它不是 `unit_internal` 的内部谱结构测试，而是公开主基准中的“零号底盘”：用于检查算法在最简单、可解析、谱结构明确的线性系统上是否仍会出现预测、谱恢复、观测处理或窗口切分错误。项目系统对象指南也明确把线性阻尼振子 / 谐振子列为 `v1-core` 的第一个系统，并将其定位为所有方法的回归测试基线。fileciteturn3file2

输入对象应包括：

- 系统参数，例如质量、阻尼、刚度，或等价的阻尼率与固有频率；
- 初始条件；
- 采样步长；
- 轨线长度；
- 观测链设置；
- 切分协议与窗口协议。

输出对象应包括：

- 连续时间 ODE 生成的状态轨线；
- 经过观测链处理后的标准观测轨线；
- 一步样本、多步 rollout 窗口、统计窗口等任务对象；
- 可用于预测、系统辨识、Koopman 谱分析、重构和长期传播评测的数据对象。

这应服从 ODEs_dataset 的统一流水线：

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

项目规范强调，数据对象不应直接等同于状态，而应经过观测链 $\mathbf x \mapsto \mathbf u \mapsto \mathbf s \mapsto \mathbf z$，并且动力系统、观测链、切分协议、窗口协议应相互解耦。fileciteturn3file0

---

### 2. Mathematical objects and dimensions

令状态为

$$

\mathbf x(t)
=
\begin{bmatrix}
q(t)\\
v(t)
\end{bmatrix}
\in\mathbb R^2,

$$

其中：

- $q(t)$：位移；
- $v(t)=\dot q(t)$：速度。

二阶形式为

$$

m\ddot q + c\dot q + kq = 0,

$$

其中

$$

m>0,\qquad c\ge 0,\qquad k>0.

$$

等价地，可以使用归一化参数

$$

\omega_0 = \sqrt{k/m},
\qquad
\gamma = \frac{c}{2m}.

$$

则系统写为

$$

\ddot q + 2\gamma \dot q + \omega_0^2 q = 0.

$$

一阶状态空间形式为

$$

\dot{\mathbf x}
=
\mathbf A(\boldsymbol{\mu})\mathbf x,

$$

其中

$$

\mathbf A(\boldsymbol{\mu})
=
\begin{bmatrix}
0 & 1\\
-\omega_0^2 & -2\gamma
\end{bmatrix}
\in\mathbb R^{2\times 2},

$$

参数向量可取为

$$

\boldsymbol{\mu}
=
(\gamma,\omega_0)

$$

或

$$

\boldsymbol{\mu}
=
(m,c,k).

$$

建议在数学定义中使用 $(\gamma,\omega_0)$，因为谱结构更清晰；在元数据中可以同时记录 $(m,c,k)$ 的物理解释。

一条轨线离散采样为

$$

\mathbf x_m = \mathbf x(t_m),
\qquad
t_m = t_0 + (m-1)\tau,
\qquad
m=1,\dots,M+1.

$$

状态矩阵为

$$

\mathbf X
=
\begin{bmatrix}
\mathbf x_1 & \mathbf x_2 & \cdots & \mathbf x_{M+1}
\end{bmatrix}
\in \mathbb R^{2\times(M+1)}.

$$

观测轨线为

$$

\mathbf z_m
=
Z\circ S\circ U(\mathbf x_m)
\in\mathbb R^{d_z},

$$

对应观测矩阵

$$

\mathbf Z
=
\begin{bmatrix}
\mathbf z_1 & \mathbf z_2 & \cdots & \mathbf z_{M+1}
\end{bmatrix}
\in\mathbb R^{d_z\times(M+1)}.

$$

---

### 3. Core formulas / numerical procedures

#### 3.1 连续时间谱

矩阵 $\mathbf A$ 的特征值为

$$

\lambda_{\pm}
=
-\gamma
\pm
\sqrt{\gamma^2-\omega_0^2}.

$$

根据阻尼强度，可分为三种情形：

**无阻尼谐振子**

$$

\gamma = 0,
\qquad
\lambda_{\pm}
=
\pm i\omega_0.

$$

这是纯旋转、能量守恒、连续谱点在虚轴上的基线系统。

**欠阻尼振子**

$$

0<\gamma<\omega_0,

$$

此时

$$

\lambda_{\pm}
=
-\gamma \pm i\omega_d,
\qquad
\omega_d=\sqrt{\omega_0^2-\gamma^2}.

$$

这是本数据集最重要的默认情形：轨线在相平面中呈旋转收缩，谱为稳定复共轭对。

**临界阻尼与过阻尼**

当

$$

\gamma=\omega_0

$$

时，系统有重复实特征值；当

$$

\gamma>\omega_0

$$

时，系统有两个负实特征值。这两类可以作为参数扩展情形，但不建议作为第一版默认主配置，因为临界阻尼处存在谱退化，容易混入非泛化性的数值病态。

#### 3.2 离散时间流映射

采样步长为 $\tau>0$ 时，

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m)
=
\exp(\tau\mathbf A)\mathbf x_m.

$$

令

$$

\mathbf K_\tau
=
\exp(\tau\mathbf A)
\in\mathbb R^{2\times 2},

$$

则

$$

\mathbf x_{m+1}
=
\mathbf K_\tau \mathbf x_m.

$$

连续谱 $\lambda_\pm$ 对应的离散谱为

$$

\rho_\pm
=
e^{\tau\lambda_\pm}.

$$

欠阻尼时，

$$

\rho_\pm
=
e^{-\gamma\tau}
e^{\pm i\omega_d\tau}.

$$

这使本系统非常适合检查 Koopman / DMD / EDMD 类方法是否能恢复：

- 衰减率 $e^{-\gamma\tau}$；
- 旋转角 $\omega_d\tau$；
- 复共轭谱；
- 多步传播稳定性。

#### 3.3 解析解

欠阻尼情形下，若

$$

q(0)=q_0,\qquad v(0)=v_0,

$$

则

$$

q(t)
=
e^{-\gamma t}
\left[
q_0\cos(\omega_d t)
+
\frac{v_0+\gamma q_0}{\omega_d}
\sin(\omega_d t)
\right],

$$

并且

$$

v(t)=\dot q(t).

$$

无阻尼情形下，

$$

q(t)
=
q_0\cos(\omega_0 t)
+
\frac{v_0}{\omega_0}\sin(\omega_0 t).

$$

解析解可作为数值积分的强基准，用于检查轨线误差、相位误差、能量误差和离散流矩阵误差。

#### 3.4 能量与耗散诊断

定义机械能

$$

E(t)
=
\frac12 v(t)^2
+
\frac12 \omega_0^2 q(t)^2.

$$

若 $\gamma=0$，则

$$

\frac{dE}{dt}=0.

$$

若 $\gamma>0$，则

$$

\frac{dE}{dt}
=
-2\gamma v(t)^2
\le 0.

$$

因此：

- 谐振子应保持能量近似守恒；
- 阻尼振子应表现出单调耗散趋势；
- 能量曲线是本系统最重要的数据质量诊断之一。

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

首先，确定系统参数集合：

$$

\boldsymbol{\mu}^{(r)}
=
(\gamma^{(r)},\omega_0^{(r)}),
\qquad r=1,\dots,R.

$$

每条轨线选择一个参数实例和一个初始条件：

$$

\mathbf x_0^{(r)}
=
\begin{bmatrix}
q_0^{(r)}\\
v_0^{(r)}
\end{bmatrix}.

$$

然后，对每条轨线生成连续或离散状态序列：

$$

\mathbf x_m^{(r)}
=
\mathbf F^{(m-1)\tau}(\mathbf x_0^{(r)}),
\qquad
m=1,\dots,M+1.

$$

在数值上可以选择：

$$

\mathbf x_{m+1}^{(r)}
=
\exp(\tau\mathbf A^{(r)})\mathbf x_m^{(r)}

$$

作为解析离散流基准；也可以用 ODE 求解器积分，以测试通用 ODE 生成接口。第一版建议同时保留解析基准思想，但正式生成仍可走统一 ODE 接口，以保证与后续非线性系统一致。

之后施加观测链：

$$

\mathbf x_m^{(r)}
\xmapsto{U}
\mathbf u_m^{(r)}
\xmapsto{S}
\mathbf s_m^{(r)}
\xmapsto{Z}
\mathbf z_m^{(r)}.

$$

建议至少考虑三类观测：

**全状态观测**

$$

\mathbf z_m
=
\begin{bmatrix}
q_m\\
v_m
\end{bmatrix}
\in\mathbb R^2.

$$

这是最基础版本。

**部分观测**

$$

\mathbf z_m
=
q_m
\in\mathbb R,

$$

或

$$

\mathbf z_m = v_m.

$$

这用于测试仅观测位移或速度时，模型是否能利用时间窗口恢复动力学信息。

**线性混合观测**

$$

\mathbf z_m
=
\mathbf H\mathbf x_m + \boldsymbol\varepsilon_m,
\qquad
\mathbf H\in\mathbb R^{d_z\times 2}.

$$

若 $d_z=1$，这是压缩传感器；若 $d_z=2$，这是可逆或近可逆线性混合。

最后，按轨线级别切分：

$$

\mathcal R_{\mathrm{train}},
\quad
\mathcal R_{\mathrm{val}},
\quad
\mathcal R_{\mathrm{test}}.

$$

项目指南强调应先按轨线切分，再在各自集合内部构造窗口，避免相邻窗口同时泄漏到训练集和测试集。fileciteturn3file2

窗口样本包括：

$$

(\mathbf z_m,\mathbf z_{m+1})

$$

的一步样本，以及

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L})

$$

的多步 rollout 样本。

---

### 5. Key assumptions

本系统的第一版建议采用以下假设。

1. 状态维数固定为

$$

d_x=2.

$$

2. 默认参数区域以无阻尼和欠阻尼为主：

$$

\gamma \ge 0,
\qquad
\omega_0>0,
\qquad
\gamma < \omega_0.

$$

3. 初始条件从有界区域采样，例如

$$

q_0\in[q_{\min},q_{\max}],
\qquad
v_0\in[v_{\min},v_{\max}],

$$

并排除过小初值，避免轨线接近零解导致谱和误差诊断失去意义。

4. 默认观测为全状态：

$$

\mathbf z=\mathbf x.

$$

后续再加入部分观测、线性混合观测和带噪观测。

5. 默认采样步长 $\tau$ 应解析主周期：

$$

T_d=\frac{2\pi}{\omega_d}.

$$

应保证每个周期至少有足够采样点，避免相位混叠。

6. 对阻尼系统，轨线长度不能过长到全部衰减到数值零附近；否则后半段数据会被低幅值噪声和舍入误差支配。

7. 对谐振子，积分误差会直接表现为能量漂移。因此如果使用通用 ODE 求解器，需要把能量误差作为核心质量检查。

---

### 6. Numerical risks

本系统虽然简单，但非常适合暴露基础数值问题。

**采样混叠**

若

$$

\omega_d\tau

$$

过大，则离散轨线可能无法正确表示旋转相位。谱估计得到的离散角度也会发生别名问题。

**阻尼过强导致信号消失**

若 $\gamma$ 太大或轨线太长，则

$$

\|\mathbf x_m\|_2

$$

很快衰减到接近零，后续窗口对学习器几乎没有有效信息。

**临界阻尼谱退化**

当

$$

\gamma\approx \omega_0

$$

时，两个特征值接近合并，谱分解对扰动敏感。第一版不应把临界阻尼作为默认主配置。

**归一化破坏物理诊断**

如果对 $q$ 和 $v$ 分别做标准化，则能量

$$

E(t)=\frac12v^2+\frac12\omega_0^2q^2

$$

不再能直接在归一化坐标中解释。因此应区分物理状态 $\mathbf x$ 与算法输入 $\mathbf z$。

**部分观测下的状态不可直接恢复**

若只观测 $q_m$，单个快照

$$

z_m=q_m

$$

不足以唯一确定完整状态 $(q_m,v_m)$。此时需要时间窗口或延迟坐标才能恢复二阶动力学信息。

**复谱与实值实现之间的转换**

连续谱和离散谱天然是复共轭对，但数据本身是实值。后续 Koopman 学习如果用实值块结构，应检查二维旋转块是否正确对应复谱；如果用复值特征函数，则要检查共轭配对和实值重构一致性。

**矩阵指数与 ODE 积分差异**

解析离散流

$$

\exp(\tau\mathbf A)

$$

和数值积分器生成的结果应高度一致。若两者差异明显，说明求解器容差、时间步设置或状态排列可能有问题。

---

### 7. Preliminary package direction

这里只给高层方向，不涉及任何 Julia API。

- **DifferentialEquations.jl / OrdinaryDiffEq.jl**：用于走统一 ODE 生成接口，方便与后续 Van der Pol、Duffing、Lorenz 等非线性系统共享数据生成流程。正式实现前需要查官方文档确认求解器选择、容差设置、保存时间点设置。
- **LinearAlgebra**：用于矩阵指数、特征值、范数、条件数等基础线性代数诊断。需要确认矩阵指数和特征分解在当前 Julia 版本中的推荐用法。
- **Random / StableRNGs 类随机数工具**：用于可复现地采样初值、参数和噪声。
- **JLD2 / HDF5 / JSON3 / TOML 等 I/O 工具**：用于保存轨线、配置和 manifest。具体格式应等到工程计划阶段再定。
- **Plots / CairoMakie / Makie 类绘图工具**：用于相图、时间序列、能量曲线和谱点图。具体绘图后端应在实现前查文档确认。

---

### 8. Wait for confirmation

请你确认这份数学 / 算法说明是否符合本次任务定位：  
**`v1_core` 第 1 个主测试数据集，默认以无阻尼谐振子与欠阻尼线性振子为核心，重点检查解析谱、复共轭离散谱、多步传播、能量诊断、轨线级切分和观测链协议。**

确认后，我再进入 Step 2，按照 **ODEs 测试数据集代码工程指南** 给出详细代码工程计划书，不写代码。