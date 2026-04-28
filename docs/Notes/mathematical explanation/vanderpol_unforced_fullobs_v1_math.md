## Step 1：范德波尔振子数学说明书

### 1. Task understanding

本次任务是在 **ODEs_dataset** 项目中接入 `v1_core` 层的经典非线性系统：**Van der Pol 振子 / 范德波尔振子**。

目标不是训练 Koopman 模型，也不是写 Julia 代码，而是先明确该系统作为数据集对象时的数学定义、状态变量、参数、观测链、离散采样、轨线对象、切分逻辑和数值风险。

在项目规范中，`v1_core` 是公开 benchmark 主集合，包含 Van der Pol、Duffing、Lotka–Volterra、FitzHugh–Nagumo、Lorenz、Rössler、Lorenz96 等系统；而 ODEs_dataset 的核心流水线应保持为  
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
\text{tasks}
\Longrightarrow
\text{metrics}.

$$
这与项目文档中“协议库 + 数据工厂 + 评测基座”的定位一致。fileciteturn0file1

---

### 2. Mathematical objects and dimensions

#### 2.1 连续时间系统

采用标准二阶范德波尔方程：

$$

\ddot{x}-\mu(1-x^2)\dot{x}+x=0,
\qquad \mu>0.

$$

写成一阶自治系统：

$$

\mathbf x =
\begin{bmatrix}
x_1\\
x_2
\end{bmatrix}
=
\begin{bmatrix}
x\\
\dot{x}
\end{bmatrix}
\in \mathbb R^2,

$$

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;\mu)
=
\begin{bmatrix}
x_2\\
\mu(1-x_1^2)x_2-x_1
\end{bmatrix}.

$$

因此：

$$

d_x=2,
\qquad
\boldsymbol\mu=(\mu)\in \mathbb R_{>0}.

$$

#### 2.2 离散采样对象

设采样步长为

$$

\tau>0,
\qquad
t_m=t_0+(m-1)\tau.

$$

连续流映射记为

$$

\mathbf x_{m+1}
=
\mathbf F^\tau_\mu(\mathbf x_m),

$$

其中

$$

\mathbf F^\tau_\mu

$$

表示由 ODE 数值积分诱导的时间 $\tau$ 映射。

一条轨线长度为 $M+1$ 时：

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x^{(q)}_1&
\mathbf x^{(q)}_2&
\cdots&
\mathbf x^{(q)}_{M+1}
\end{bmatrix}
\in
\mathbb R^{2\times(M+1)}.

$$

若共有 $R$ 条轨线，则轨线编号为

$$

q=1,\dots,R.

$$

#### 2.3 观测链对象

ODEs_dataset 规范中不应默认算法输入等同于状态，而应经过观测链

$$

\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z}.

$$

对低维 ODE，最基础版本可以使用全状态观测：

$$

U=\mathcal I,
\qquad
S=\mathcal I,
\qquad
Z=\mathcal I,
\qquad
\mathbf z_m=\mathbf x_m.

$$

此时：

$$

d_z=d_x=2,

$$

$$

\mathbf Z^{(q)}
=
\begin{bmatrix}
\mathbf z^{(q)}_1&
\cdots&
\mathbf z^{(q)}_{M+1}
\end{bmatrix}
\in
\mathbb R^{2\times(M+1)}.

$$

项目规范明确要求动力系统与观测链解耦，因此即使第一版只做全状态观测，也应在数学上保留

$$

\mathbf x\mapsto \mathbf z

$$

这一层。fileciteturn0file1

---

### 3. Core formulas / numerical procedures

#### 3.1 系统右端函数

核心向量场为

$$

f_1(x_1,x_2;\mu)=x_2,

$$

$$

f_2(x_1,x_2;\mu)=\mu(1-x_1^2)x_2-x_1.

$$

因此：

$$

\mathbf f(\mathbf x;\mu)
=
\begin{bmatrix}
f_1\\
f_2
\end{bmatrix}.

$$

#### 3.2 极限环结构

当

$$

\mu>0

$$

时，范德波尔振子具有稳定极限环。它适合作为 `v1_core` 中的低维非混沌非线性系统，用来测试：

$$

\text{非线性耗散结构},
\quad
\text{稳定极限环},
\quad
\text{相位漂移},
\quad
\text{长期周期传播误差}.

$$

相比线性振子，Van der Pol 的 Koopman 谱学习更难，因为它的极限环吸引结构会导致：

$$

\text{径向收缩模式}
+
\text{相位旋转模式}

$$

同时存在。

#### 3.3 推荐参数分层

数学上建议先采用三类参数区间：

1. **平滑极限环区间**

$$

\mu\approx 1.

$$

这是第一版最稳妥的 smoke / small 设置，非线性明显但通常不太刚性。

2. **中等松弛振荡区间**

$$

\mu\in[1,3].

$$

该区间适合正式版本的初始 benchmark，能体现非线性耗散和周期波形畸变。

3. **强松弛振荡区间**

$$

\mu\gg 1.

$$

此时系统出现明显快慢结构，数值积分更接近刚性问题。第一版不建议直接把很大的 $\mu$ 放入默认主测试，否则会把“动力学挑战”和“数值积分挑战”混在一起。

#### 3.4 初值集合

初值为

$$

\mathbf x_0
=
\begin{bmatrix}
x_{1,0}\\
x_{2,0}
\end{bmatrix}
\in \Omega_0\subset\mathbb R^2.

$$

建议选择包含极限环内外的矩形区域，例如数学上表示为

$$

\Omega_0=[a_1,b_1]\times[a_2,b_2].

$$

这样可以同时覆盖：

$$

\text{向极限环收敛的 transient}

$$

和

$$

\text{极限环附近的准周期采样}.

$$

#### 3.5 单步样本

对每条轨线，单步样本为

$$

(\mathbf z^{(q)}_m,\mathbf z^{(q)}_{m+1}),
\qquad
m=1,\dots,M.

$$

全状态观测时即为

$$

(\mathbf x^{(q)}_m,\mathbf x^{(q)}_{m+1}).

$$

#### 3.6 多步 rollout 窗口

长度为 $L$ 的 rollout 样本为

$$

(\mathbf z^{(q)}_s,\mathbf z^{(q)}_{s+1},\dots,\mathbf z^{(q)}_{s+L}),

$$

其中

$$

s=1,\dots,M+1-L.

$$

该对象用于检查长期传播误差和相位误差。

#### 3.7 统计窗口

对稳定极限环系统，可定义局部统计窗口：

$$

(\mathbf z_s,\dots,\mathbf z_{s+L-1}),

$$

用于估计：

$$

\text{均值},
\quad
\text{协方差},
\quad
\text{主频},
\quad
\text{周期},
\quad
\text{相图闭合程度}.

$$

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

#### 4.1 固定系统族

定义系统族：

$$

\mathcal S_{\mathrm{vdp}}
=
\left\{
\dot{\mathbf x}=\mathbf f(\mathbf x;\mu)
:
\mu\in\Pi
\right\}.

$$

其中 $\Pi$ 是参数集合。

#### 4.2 采样参数和初值

对每条轨线 $q$，采样：

$$

\mu^{(q)}\in\Pi,
\qquad
\mathbf x_0^{(q)}\in\Omega_0.

$$

若做初值泛化，则所有轨线可共享同一 $\mu$，只改变初值。  
若做参数泛化，则训练、验证、测试使用不同的 $\mu$ 子集。

#### 4.3 数值积分

对每个 $(\mu^{(q)},\mathbf x_0^{(q)})$，求解：

$$

\dot{\mathbf x}^{(q)}(t)
=
\mathbf f(\mathbf x^{(q)}(t);\mu^{(q)}),
\qquad
\mathbf x^{(q)}(0)=\mathbf x_0^{(q)}.

$$

在采样时刻得到：

$$

\mathbf x_m^{(q)}
=
\mathbf x^{(q)}(t_m),
\qquad
m=1,\dots,M+1.

$$

#### 4.4 观测链处理

对每个状态快照施加观测链：

$$

\mathbf z_m^{(q)}
=
Z\circ S\circ U(\mathbf x_m^{(q)}).

$$

第一版建议先使用：

$$

\mathbf z_m^{(q)}=\mathbf x_m^{(q)}.

$$

但数学接口应允许后续加入：

$$

\mathbf z_m=
\begin{bmatrix}
x_{1,m}
\end{bmatrix}
\in\mathbb R^1

$$

的部分观测，或

$$

\mathbf z_m=
\mathbf H\mathbf x_m+\boldsymbol\varepsilon_m

$$

的线性传感器观测。

#### 4.5 轨线级切分

切分单位必须是整条轨线，而不是窗口。也就是先划分轨线编号集合：

$$

\mathcal R_{\mathrm{train}},
\qquad
\mathcal R_{\mathrm{val}},
\qquad
\mathcal R_{\mathrm{test}}.

$$

然后只在各自集合内部切窗口。项目规范中也强调 split 应独立、默认按轨线切分，避免相邻窗口泄漏到不同数据集。fileciteturn0file1

#### 4.6 窗口派生

在每个 split 内部构造：

$$

\text{one-step samples},
\quad
\text{rollout windows},
\quad
\text{statistics windows}.

$$

这样 Van der Pol 同一批基础轨线可以服务多种 benchmark 任务。

---

### 5. Key assumptions

#### 5.1 系统假设

默认范德波尔振子是二维自治 ODE：

$$

d_x=2,
\qquad
\mu>0.

$$

第一版不加入外部周期 forcing，不加入控制输入，不加入随机扰动。

#### 5.2 观测假设

第一版默认全状态观测：

$$

\mathbf z=\mathbf x.

$$

此时：

$$

d_z=2.

$$

后续可以扩展到部分观测、线性混合观测和带噪观测，但不应改变系统本体定义。

#### 5.3 采样假设

采样步长 $\tau$ 应足够小，使得每个周期内有足够多采样点。若主周期记为 $T(\mu)$，则应满足：

$$

\frac{T(\mu)}{\tau}

$$

足够大，以避免相位轨迹过粗。

#### 5.4 transient 与 attractor 假设

Van der Pol 的轨线通常包含两段：

$$

\text{transient approaching limit cycle}

$$

和

$$

\text{near-attractor periodic motion}.

$$

数据集设计需要明确是否保留 transient。建议第一版保留，因为它对学习径向收缩模式有价值；但评测时应允许区分：

$$

\text{transient error}
\quad\text{vs.}\quad
\text{limit-cycle error}.

$$

#### 5.5 切分假设

默认按轨线切分，而不是按窗口随机打散。这样可以避免测试集和训练集共享同一条轨线的相邻片段。

---

### 6. Numerical risks

#### 6.1 中大 $\mu$ 下的刚性风险

当 $\mu$ 较大时，系统进入松弛振荡状态，轨线包含慢段和快跃迁段。此时存在：

$$

\text{时间尺度分离},
\quad
\text{局部陡峭变化},
\quad
\text{积分步长敏感}.

$$

如果默认 solver 或容差不合适，数据误差可能来自数值积分，而不是动力系统本身。

#### 6.2 采样步长过大导致相位混叠

若 $\tau$ 太大，则极限环上的相位推进会被欠采样，导致：

$$

\mathbf z_m\mapsto \mathbf z_{m+1}

$$

看起来不平滑，影响后续 EDMD、DMD、Neural Koopman 等方法。

#### 6.3 初值区域过窄

若初值都在极限环附近，则数据几乎只覆盖一维闭曲线附近，不能充分测试径向收缩模式。

若初值范围过大，则可能出现大幅 transient，使训练任务从“极限环学习”变成“全局非线性恢复”，难度显著提高。

#### 6.4 窗口泄漏

如果先切窗口再随机分 train / test，同一条轨线的相邻片段可能同时出现在训练和测试中，导致 rollout 指标虚高。必须先按轨线切，再构造窗口。

#### 6.5 归一化风险

Van der Pol 的两个状态分量尺度可能不同：

$$

x_1 \quad \text{and} \quad x_2

$$

在不同 $\mu$ 下的幅值和速度尺度也可能变化。若做全局归一化，需要记录归一化统计量来自训练集，而不是全数据集，否则会发生测试信息泄漏。

#### 6.6 周期误差与点态误差的区别

长期 rollout 中，即使轨线仍在正确极限环上，只要相位略微漂移，点态误差也会增长。因此评测时应区分：

$$

\text{amplitude / attractor error}

$$

和

$$

\text{phase error}.

$$

这对 Van der Pol 特别重要。

---

### 7. Preliminary package direction

后续实现时可能涉及以下 Julia 包方向，但在编码前需要检查官方文档，不应凭记忆假设 API。

#### 7.1 DifferentialEquations.jl / OrdinaryDiffEq.jl

用于 ODE 数值积分：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\mu).

$$

需要确认：

$$

\text{ODEProblem 定义方式},
\quad
\text{solver 选择},
\quad
\text{saveat 采样},
\quad
\text{abstol / reltol 设置}.

$$

#### 7.2 Random / Distributions

用于采样初值和参数：

$$

\mathbf x_0^{(q)}\sim \mathcal D_x,
\qquad
\mu^{(q)}\sim \mathcal D_\mu.

$$

需要明确随机种子策略，保证同一配置可复现。

#### 7.3 LinearAlgebra / Statistics

用于数据诊断，例如：

$$

\text{均值},
\quad
\text{协方差},
\quad
\text{状态范围},
\quad
\text{轨线范数},
\quad
\text{周期估计}.

$$

#### 7.4 JLD2 / HDF5 / JSON3 / TOML

用于保存数据对象、配置和 manifest。具体选型应在 Step 2 中结合 ODEs_dataset 工程指南决定。

---

### 8. Wait for confirmation

请你确认这份 **范德波尔振子的数学 / 算法 formulation** 是否符合预期，尤其是下面几个选择：

1. 第一版是否采用标准无受迫 Van der Pol：
   $$

   \dot{x}_1=x_2,\qquad
   \dot{x}_2=\mu(1-x_1^2)x_2-x_1?
   
$$

2. 第一版是否默认全状态观测：
   $$

   \mathbf z=\mathbf x\in\mathbb R^2?
   
$$

3. 参数范围是否先控制在非强刚性的区间，例如：
   $$

   \mu\in[1,3]
   
$$
   而不是直接上大 $\mu$ 松弛振荡？

你确认后，我再进入 **Step 2：按照 ODEs_dataset 代码工程指南写详细代码工程计划书**，仍然不写代码。