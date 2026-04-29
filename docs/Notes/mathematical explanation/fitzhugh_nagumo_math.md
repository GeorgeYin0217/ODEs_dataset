下面先给出 **Step 1：数学说明书**。我按你项目文档里的数据协议来写：低维 ODE 的最简单情形可取恒等观测链 $U=S=Z=\mathcal I$，于是数据集输入直接等于状态；轨线对象按列存储，并且切分应先按整条轨线，再在各子集内构造一步样本或多步窗口。你的系统注册里也已经把 FitzHugh–Nagumo 放在 `v1_core`，其定位就是测试快慢结构、激发阈值以及 spike–recovery 动力学。fileciteturn3file1 fileciteturn3file0

## 1. Task understanding

目标是为 **ODEs_dataset** 中的 **FitzHugh–Nagumo 系统**给出一份数学说明书，作为后续实现数据生成器、观测对象、切分协议和评测任务的前置说明。

本次任务默认采用：

- 二维、连续时间、自治 ODE；
- 全状态观测；
- 无外部控制输入、无随机扰动；
- 先做固定参数版本，不把参数泛化当作第一版主任务；
- 数据对象仍遵守项目统一协议：先生成状态轨线 $\{\mathbf x_m\}$，再经观测链得到 $\{\mathbf z_m\}$。在本对象中先取
  $$

  \mathbf z_m=\mathbf x_m.
  
$$

预期输出不是代码，而是：

- 系统数学形式；
- 变量、参数与维度定义；
- 数据集层面的轨线构造逻辑；
- 数值风险与诊断重点；
- 后续实现时应检查的关键数值对象。

---

## 2. Mathematical objects and dimensions

### 2.1 状态变量

取状态向量
$$

\mathbf x(t)=
\begin{bmatrix}
v(t)\\
w(t)
\end{bmatrix}\in\mathbb R^2,

$$
其中：

- $v$：快变量，表示激发/膜电位样变量；
- $w$：慢变量，表示恢复变量。

因此状态维数为
$$

d_x=2.

$$

在当前最简单观测设定下，
$$

\mathbf z(t)=\mathbf x(t),\qquad d_z=2.

$$

---

### 2.2 参数

采用标准二维 FitzHugh–Nagumo 形式之一：
$$

\dot v = v-\frac{v^3}{3}-w+I,
\qquad
\dot w = \varepsilon\,(v+a-bw).

$$

参数向量记为
$$

\boldsymbol\mu=(a,b,\varepsilon,I).

$$

其中：

- $a$：恢复方程平移参数；
- $b$：恢复变量反馈系数；
- $\varepsilon>0$：快慢时间尺度分离参数，通常较小；
- $I$：常值外加电流/偏置输入。

虽然方程里有 $I$，但当 $I$ 为常数时，系统依然是**自治系统**；这里不把 $I(t)$ 当作时变控制输入。

---

### 2.3 离散采样对象

给定采样步长 $\tau>0$，离散轨线写为
$$

\mathbf x_{m+1}=\mathbf F^\tau(\mathbf x_m),\qquad m=1,2,\dots,M.

$$

状态矩阵按列存储：
$$

\mathbf X=
\begin{bmatrix}
\mathbf x_1 & \mathbf x_2 & \cdots & \mathbf x_{M+1}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

由于当前为全状态恒等观测，
$$

\mathbf Z=
\begin{bmatrix}
\mathbf z_1 & \mathbf z_2 & \cdots & \mathbf z_{M+1}
\end{bmatrix}
=
\mathbf X
\in\mathbb R^{2\times(M+1)}.

$$

若有多条轨线，则写为
$$

\mathbf x_m^{(q)},\quad \mathbf z_m^{(q)},\qquad q=1,\dots,Q.

$$

这与项目文档里的轨线、一步样本、多步窗口约定一致。fileciteturn3file1

---

## 3. Core formulas / numerical procedures

## 3.1 连续时间动力系统

建议第一版固定使用
$$

\boxed{
\dot v = v-\frac{v^3}{3}-w+I,\qquad
\dot w = \varepsilon\,(v+a-bw)
}

$$
作为系统定义。

这是一个二维非线性快慢系统，核心几何特征来自：

- $v$-nullcline：
  $$

  0=v-\frac{v^3}{3}-w+I
  \quad\Longrightarrow\quad
  w=v-\frac{v^3}{3}+I;
  
$$
- $w$-nullcline：
  $$

  0=\varepsilon(v+a-bw)
  \quad\Longrightarrow\quad
  w=\frac{v+a}{b}.
  
$$

二者交点给出平衡点 $(v_\ast,w_\ast)$。

---

## 3.2 平衡点条件

由
$$

w_\ast=\frac{v_\ast+a}{b}

$$
代入第一式，得到关于 $v_\ast$ 的三次方程
$$

v_\ast-\frac{v_\ast^3}{3}-\frac{v_\ast+a}{b}+I=0.

$$

解得 $v_\ast$ 后，恢复
$$

w_\ast=\frac{v_\ast+a}{b}.

$$

这一定义后续很重要，因为：

- 初值域可围绕平衡点布置；
- 局部线性化稳定性可由 Jacobian 判断；
- 数据质量检查可以比较轨线是否落在预期的激发/恢复相区间内。

---

## 3.3 线性化与局部稳定性

Jacobian 为
$$

J(v,w)=
\begin{bmatrix}
1-v^2 & -1\\
\varepsilon & -\varepsilon b
\end{bmatrix}.

$$

在平衡点处：
$$

J_\ast=
\begin{bmatrix}
1-v_\ast^2 & -1\\
\varepsilon & -\varepsilon b
\end{bmatrix}.

$$

其迹与行列式分别为
$$

\operatorname{tr}(J_\ast)=1-v_\ast^2-\varepsilon b,

$$
$$

\det(J_\ast)=\varepsilon\bigl(1-b+bv_\ast^2\bigr).

$$

由此可判断：

- 稳定焦点/结点；
- 不稳定平衡；
- 接近 Hopf 分岔的区域；
- 快慢振荡和阈值激发出现的参数背景。

---

## 3.4 快慢结构

因为 $\varepsilon\ll 1$ 时 $w$ 演化显著慢于 $v$，系统具有典型快慢分解：

- 快过程主要沿 $v$ 方向快速跃迁；
- 慢过程主要沿立方 nullcline 附近漂移；
- 轨线在相图中常表现为“慢漂移 + 快跃迁”的 spike–recovery 结构。

因此这个系统对数据集的意义，不只是“二维非线性”，而是“二维快慢、阈值触发型非线性”。

---

## 3.5 数据集层面的一步样本与多步窗口

一步样本：
$$

(\mathbf z_m,\mathbf z_{m+1})
\in \mathbb R^2\times\mathbb R^2.

$$

长度为 $L$ 的 rollout 窗口：
$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}),
\qquad
\mathbf z_{s+\ell}\in\mathbb R^2.

$$

若把所有窗口堆叠起来，应先按轨线切分，再在每个 split 内生成窗口，而不能先把窗口打散。这一点是项目协议的硬要求。fileciteturn3file1

---

## 3.6 适合本系统的主要数值任务

对 FitzHugh–Nagumo，数据集上最自然的评测任务是：

1. 一步预测  
   $$

   \mathbf z_m\mapsto \mathbf z_{m+1}.
   
$$

2. 多步 rollout  
   $$

   \mathbf z_s\mapsto (\mathbf z_{s+1},\dots,\mathbf z_{s+L}).
   
$$

3. 表示/算子学习中的近闭合检验  
   检查在某个特征映射 $\varphi$ 下，
   $$

   \varphi(\mathbf z_{m+1})\approx A\varphi(\mathbf z_m)
   
$$
   是否比普通二维极限环系统更难，因为这里包含明显的快慢不均匀性与阈值跃迁。项目系统指南里也正是把它列为检验快慢结构、激发阈值和尖峰恢复动力学的核心对象。fileciteturn3file0

---

## 4. Algorithmic logic

这里先给数学层面的生成逻辑，不涉及代码。

### Step A：固定系统版本
先选定一个固定参数组
$$

(a,b,\varepsilon,I)=\boldsymbol\mu_{\mathrm{ref}},

$$
使系统处于你想要的数据机制中。第一版建议明确选择以下两类之一：

- **excitable regime**：平衡点稳定，但足够大的扰动会触发一次大 excursion；
- **oscillatory regime**：存在稳定极限环，轨线呈持续 spike–recovery 振荡。

如果你希望它和 Van der Pol 形成明显分工，我更建议第一版偏向 **excitable / threshold-driven** 风格，而不是纯粹“又一个平滑极限环”。

---

### Step B：定义初值域
在相平面上取初值集合
$$

\mathbf x_0^{(q)}\in\Omega_{\mathrm{ic}}\subset\mathbb R^2.

$$

初值域最好覆盖三类区域：

- 平衡点附近的小扰动区；
- 阈值附近敏感区；
- 完整 spike–recovery 轨道会经过的较大区域。

这样才能让数据包含“未激发 / 临界 / 已激发”三类动力学行为。

---

### Step C：数值积分得到状态轨线
对每个初值
$$

\mathbf x(0)=\mathbf x_0^{(q)}

$$
积分得到
$$

\{\mathbf x_m^{(q)}\}_{m=1}^{M+1}.

$$

由于 FHN 是快慢系统，积分器内部步长通常需要自适应；但最终输出到数据集的仍是统一采样步长 $\tau$ 下的离散快照。

---

### Step D：施加观测链
当前最简单版本取
$$

U=S=Z=\mathcal I,

$$
所以
$$

\mathbf z_m^{(q)}=\mathbf x_m^{(q)}.

$$

这与 ODEs_dataset 对低维 ODE 的最简协议完全一致。fileciteturn3file1

---

### Step E：轨线级切分
按轨线编号 $q$ 做
$$

\mathcal R_{\mathrm{train}},\ \mathcal R_{\mathrm{val}},\ \mathcal R_{\mathrm{test}}

$$
划分，而不是按窗口随机打散。fileciteturn3file0 fileciteturn3file1

---

### Step F：窗口派生
在各自 split 内部派生：

- one-step 样本；
- rollout 窗口；
- 统计窗口。

对于 FHN，统计窗口尤其有意义，因为：

- 可统计 spike 次数；
- 可统计 spike 间隔；
- 可统计快变量振幅分布；
- 可统计恢复变量滞后环结构。

---

## 5. Key assumptions

第一版数学说明建议固定以下假设。

### 5.1 系统假设
- 系统是二维自治 ODE；
- 不含时变 forcing；
- 不含显式控制输入；
- 不含随机扰动项。

### 5.2 观测假设
- 当前版本使用全状态观测；
- 不做部分观测；
- 不做非线性传感器；
- 可先不加噪。

### 5.3 参数假设
- 第一版先固定单一参数组，不做参数泛化主实验；
- 但参数对象 $\boldsymbol\mu$ 仍应保留在系统定义里，方便以后扩展到 `Split-P`。

### 5.4 数值假设
- 内部积分可以自适应，但输出采样步长固定；
- 每条轨线长度足够覆盖完整的激发—恢复事件，或足够多的周期；
- 多条轨线的长度、采样协议、观测协议保持一致。

### 5.5 数据协议假设
- 状态矩阵、观测矩阵都按列存储；
- 先保存轨线，再构造样本；
- 先 split，再 window。fileciteturn3file1

---

## 6. Numerical risks

FitzHugh–Nagumo 的主要数值风险比普通二维平滑振子更集中在快慢尺度与阈值结构上。

### 6.1 采样步长过粗
如果输出步长 $\tau$ 太大，会出现：

- spike 顶点被漏采样；
- 快跃迁阶段严重失真；
- 估计的一步映射过于粗糙；
- 多步 rollout 对阈值行为不敏感。

### 6.2 初值域选取不当
若初值都离阈值太远，数据会退化成“平淡恢复”；  
若初值全在强激发区，数据会缺少临界边界信息。

### 6.3 参数落入错误动力学区间
若参数选得不合适，可能出现：

- 几乎线性的小振幅行为；
- 过于单一的稳定平衡收敛；
- 与预期不符的持续振荡或多时间尺度不明显。

### 6.4 快慢分离导致局部刚性倾向
$\varepsilon$ 很小时，系统虽然未必属于典型强刚性 benchmark，但会出现：

- 积分器内部步长显著缩小；
- spike 段与恢复段误差特征不均匀；
- 同一轨线上局部 Lipschitz 尺度差异很大。

### 6.5 阈值敏感导致样本分布不均
在阈值附近，极小初值差异可引起截然不同的后续轨线，这会导致：

- 训练/测试误差方差增大；
- rollout 误差在少数窗口上暴涨；
- 用均方误差汇总时被少数尖峰窗口主导。

### 6.6 归一化风险
若后续对 $v,w$ 做统一归一化，要注意：

- $v$ 的 spike 幅值范围通常大于 $w$；
- 若混合归一化不当，可能压缩快变量尖峰信息；
- 对算子学习而言，不同尺度变量会影响 Gram 条件数与特征方向稳定性。

---

## 7. Preliminary package direction

这里只给高层方向，不写 API。

- **DifferentialEquations.jl / OrdinaryDiffEq.jl**  
  用于 ODE 积分，特别适合快慢系统的稳定求解。具体应选哪类求解器、容差如何设定，后续实现前需要查官方文档。

- **LinearAlgebra**  
  用于平衡点线性化、Jacobian 分析、局部谱诊断。

- **Statistics / StatsBase**  
  用于轨线统计量、振幅/周期/spike 间隔等基本汇总。

- **Plots.jl 或 CairoMakie.jl**  
  用于相图、时间历程、nullcline 叠加和数据质量诊断。绘图库具体选型可以后面再定。

如果后续你想把 FHN 轨线做成更标准的数据对象，还会用到项目里统一的数据读写与 manifest 机制；但那已经属于 Step 2 的工程规划，不在这里展开。ODEs_dataset 的配置对象、轨线对象、切分对象与窗口对象已经在项目规范文档中定义清楚了。fileciteturn3file1

---

## 8. Wait for confirmation

我对这次 FitzHugh–Nagumo 的 **Step 1** 建议是：

- 采用二维自治标准 FHN；
- 全状态观测；
- 第一版固定参数；
- 重点突出 **快慢结构 + 激发阈值 + spike–recovery**，使其和 Van der Pol 的“平滑极限环主导”形成清晰分工。这个定位也与你系统指南里对 FHN 的角色描述一致。fileciteturn3file0

你确认这份数学/算法设定后，我再进入 **Step 2：按照 ODEs 测试数据集代码工程指南写详细代码工程计划书**。