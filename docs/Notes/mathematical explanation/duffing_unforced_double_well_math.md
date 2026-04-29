## Step 1：Duffing 振子数学说明书

### 1. Task understanding

本次任务是在 **ODEs_dataset** 中新增 / 规划一个 `v1_core` 级别的 Duffing 振子数据集对象。按照当前数据集协议，系统对象不应只是一段 ODE，而应服务于完整数据链：

$$

(\mathbf f,\boldsymbol\mu,\mathbf x_0,\tau)
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

这里 $\mathbf x_m$ 是真实状态，$\mathbf z_m$ 是经过观测链后的算法输入；ODEs_dataset 的规范也明确要求动力系统、观测链、切分协议和窗口协议解耦。fileciteturn4file0

Duffing 振子的 benchmark 价值在于：它比 Van der Pol 更适合测试 **多稳态、双势阱结构、势阱间边界、非线性刚度、受迫后的分岔与混沌前夜**；在你的长期 ODE 规划中，Duffing 已经被列为 `v1_core` 主集合之一。fileciteturn4file1

本次数学说明书建议先明确两个层级：

1. **第一版主对象**：无受迫阻尼双井 Duffing，二维自治系统，适合作为 ODEs_dataset 的稳定核心版本。
2. **后续扩展对象**：周期受迫 Duffing，通过相位变量增广成三维自治系统，用于更复杂的分岔、混沌和参数泛化测试。

---

### 2. Mathematical objects and dimensions

#### 2.1 无受迫阻尼 Duffing：推荐第一版主对象

状态变量取

$$

\mathbf x =
\begin{bmatrix}
q\\
v
\end{bmatrix}
\in \mathbb R^2,

$$

其中：

$$

q = \text{位移},\qquad v = \dot q = \text{速度}.

$$

标准无受迫 Duffing 方程写为

$$

\ddot q + \delta \dot q + \alpha q + \beta q^3 = 0.

$$

写成一阶系统：

$$

\dot q = v,

$$

$$

\dot v = -\delta v - \alpha q - \beta q^3.

$$

因此

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;\boldsymbol\mu),
\qquad
\boldsymbol\mu = (\delta,\alpha,\beta).

$$

状态维数为

$$

d_x = 2.

$$

建议第一版采用双井 Duffing 参数结构：

$$

\delta > 0,\qquad \alpha < 0,\qquad \beta > 0.

$$

对应势能函数

$$

V(q)
=
\frac{\alpha}{2}q^2
+
\frac{\beta}{4}q^4.

$$

总能量为

$$

E(q,v)
=
\frac12 v^2 + V(q)
=
\frac12 v^2
+
\frac{\alpha}{2}q^2
+
\frac{\beta}{4}q^4.

$$

当 $\alpha<0,\beta>0$ 时，系统具有双势阱结构。平衡点满足

$$

v = 0,\qquad \alpha q + \beta q^3 = 0.

$$

因此有三个平衡点：

$$

(q^\ast,v^\ast) = (0,0),

$$

$$

(q^\ast,v^\ast)
=
\left(
\pm \sqrt{-\frac{\alpha}{\beta}},
0
\right).

$$

其中 $(0,0)$ 是势垒附近的鞍型点，两侧平衡点是两个势阱中心附近的吸引点。

#### 2.2 受迫 Duffing：后续扩展对象

周期受迫 Duffing 方程为

$$

\ddot q + \delta \dot q + \alpha q + \beta q^3
=
\gamma \cos(\omega t).

$$

它作为二维系统是非自治系统。为了保持 ODEs_dataset 当前“ODE 系统对象”的自治形式，可引入相位变量

$$

\theta = \omega t,
\qquad
\dot\theta = \omega.

$$

增广状态为

$$

\mathbf x =
\begin{bmatrix}
q\\
v\\
\theta
\end{bmatrix}
\in \mathbb R^2 \times \mathbb S^1.

$$

一阶自治系统为

$$

\dot q = v,

$$

$$

\dot v
=
-\delta v - \alpha q - \beta q^3 + \gamma \cos \theta,

$$

$$

\dot\theta = \omega.

$$

参数为

$$

\boldsymbol\mu = (\delta,\alpha,\beta,\gamma,\omega),

$$

状态维数为

$$

d_x = 3.

$$

这个版本更适合研究长期非线性传播、周期驱动下的势阱切换、Poincaré 结构、混沌前夜和参数泛化。但它会引入相位变量处理、采样同步和角变量不连续等额外风险，因此不建议作为最先实现的 smoke 对象。

#### 2.3 观测变量

ODEs_dataset 的标准观测链写为

$$

\mathbf x
\xmapsto{U}
\mathbf u
\xmapsto{S}
\mathbf s
\xmapsto{Z}
\mathbf z.

$$

第一版建议使用全状态观测：

$$

U = \mathcal I,\qquad
S = \mathcal I,\qquad
Z = \mathcal I.

$$

因此无受迫版本中：

$$

\mathbf z_m = \mathbf x_m =
\begin{bmatrix}
q_m\\
v_m
\end{bmatrix},
\qquad
d_z = 2.

$$

对于受迫增广版本，不建议直接把 wrapped angle $\theta\in[0,2\pi)$ 作为普通实数输入，因为 $\theta=0$ 和 $\theta=2\pi$ 物理上相同但数值上不连续。更稳定的观测方式是

$$

\mathbf z_m =
\begin{bmatrix}
q_m\\
v_m\\
\cos\theta_m\\
\sin\theta_m
\end{bmatrix}
\in \mathbb R^4.

$$

此时

$$

d_x = 3,\qquad d_z = 4.

$$

#### 2.4 轨线矩阵

对第 $r$ 条轨线，若采样得到 $M+1$ 个快照，则状态矩阵为

$$

\mathbf X^{(r)}
=
\begin{bmatrix}
\mathbf x^{(r)}_1&
\mathbf x^{(r)}_2&
\cdots&
\mathbf x^{(r)}_{M+1}
\end{bmatrix}
\in \mathbb R^{d_x\times(M+1)}.

$$

观测矩阵为

$$

\mathbf Z^{(r)}
=
\begin{bmatrix}
\mathbf z^{(r)}_1&
\mathbf z^{(r)}_2&
\cdots&
\mathbf z^{(r)}_{M+1}
\end{bmatrix}
\in \mathbb R^{d_z\times(M+1)}.

$$

单步样本为

$$

(\mathbf z_m,\mathbf z_{m+1}),

$$

多步 rollout 窗口为

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

---

### 3. Core formulas / numerical procedures

#### 3.1 连续流与离散采样

连续时间系统为

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;\boldsymbol\mu).

$$

给定采样步长 $\tau>0$，离散流映射定义为

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m;\boldsymbol\mu).

$$

其中

$$

t_m = t_0 + (m-1)\tau.

$$

数值积分生成的是 $\mathbf x(t_m)$，而 benchmark 接口使用的是

$$

\mathbf z_m = Z\circ S\circ U(\mathbf x_m).

$$

#### 3.2 能量结构

无受迫系统的能量为

$$

E(q,v)
=
\frac12 v^2
+
\frac{\alpha}{2}q^2
+
\frac{\beta}{4}q^4.

$$

沿轨线求导：

$$

\frac{dE}{dt}
=
v\dot v + (\alpha q+\beta q^3)\dot q.

$$

代入

$$

\dot q = v,
\qquad
\dot v = -\delta v-\alpha q-\beta q^3,

$$

得到

$$

\frac{dE}{dt}
=
-\delta v^2.

$$

因此当

$$

\delta>0

$$

时，

$$

\frac{dE}{dt}\le 0.

$$

这给出一个非常有用的数值诊断：无受迫阻尼 Duffing 的能量应当单调非增。若数值积分得到明显能量增长，需要检查步长、求解器容差或数据采样过程。

#### 3.3 平衡点与线性化

系统右端为

$$

\mathbf f(q,v)
=
\begin{bmatrix}
v\\
-\delta v-\alpha q-\beta q^3
\end{bmatrix}.

$$

Jacobian 为

$$

D\mathbf f(q,v)
=
\begin{bmatrix}
0 & 1\\
-\alpha-3\beta q^2 & -\delta
\end{bmatrix}.

$$

在平衡点 $(q^\ast,0)$ 附近，线性化为

$$

\frac{d}{dt}
\begin{bmatrix}
\eta\\
w
\end{bmatrix}
=
\begin{bmatrix}
0 & 1\\
-\alpha-3\beta (q^\ast)^2 & -\delta
\end{bmatrix}
\begin{bmatrix}
\eta\\
w
\end{bmatrix}.

$$

对于双井参数 $\alpha<0,\beta>0$：

- 原点 $(0,0)$ 的线性刚度为 $\alpha<0$，对应鞍型不稳定结构；
- 两个势阱点

$$

q^\ast = \pm \sqrt{-\frac{\alpha}{\beta}}

$$

处的有效刚度为

$$

\alpha + 3\beta(q^\ast)^2
=
-2\alpha > 0.

$$

因此两个势阱点附近是阻尼振子型稳定结构。

#### 3.4 推荐参数结构

第一版建议采用非刚性、双井、阻尼适中的参数区间：

$$

\alpha = -1,\qquad
\beta = 1,

$$

$$

\delta \in [0.05,0.5].

$$

默认单参数版本可以先取

$$

\delta = 0.2,\qquad
\alpha=-1,\qquad
\beta=1.

$$

此时势阱中心位于

$$

q^\ast = \pm 1.

$$

初值区域建议覆盖两个势阱与势垒附近：

$$

q_0 \in [-2,2],
\qquad
v_0 \in [-2,2].

$$

这样可以生成三类典型轨线：

1. 从左势阱附近衰减到左稳定点；
2. 从右势阱附近衰减到右稳定点；
3. 从势垒附近出发，对初值敏感，可能跨越势阱边界后进入某一侧吸引域。

#### 3.5 参数泛化方向

如果需要 Split-P 参数泛化，可以优先变化阻尼参数：

$$

\delta_{\mathrm{train}}
\cap
\delta_{\mathrm{test}}
=
\emptyset.

$$

更复杂的参数泛化可以变化：

$$

\alpha,\qquad \beta.

$$

但不建议第一版随意让 $\beta\le 0$，因为 $\beta>0$ 保证高能区势能向上增长，系统更容易保持有界。

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

第一，确定 Duffing 系统类型：

$$

\text{unforced 2D}
\quad\text{or}\quad
\text{forced augmented 3D}.

$$

第一版建议采用无受迫二维系统。

第二，采样参数实例：

$$

\boldsymbol\mu^{(r)}
=
(\delta^{(r)},\alpha^{(r)},\beta^{(r)}).

$$

若当前只做初值泛化，则所有轨线共享同一组参数；若做参数泛化，则训练、验证、测试使用不同参数子集。

第三，采样初值：

$$

\mathbf x_0^{(r)}
=
\begin{bmatrix}
q_0^{(r)}\\
v_0^{(r)}
\end{bmatrix}.

$$

初值采样应覆盖左势阱、右势阱和势垒附近，而不是只在一个吸引域内部采样。

第四，数值积分得到连续时间状态轨线：

$$

\{\mathbf x^{(r)}(t)\}_{t\in[0,T]}.

$$

第五，以固定采样步长 $\tau$ 生成离散快照：

$$

\mathbf x_m^{(r)}
=
\mathbf x^{(r)}(t_m),
\qquad
m=1,\dots,M+1.

$$

第六，施加观测链：

$$

\mathbf z_m^{(r)}
=
Z\circ S\circ U(\mathbf x_m^{(r)}).

$$

第一版全状态观测下：

$$

\mathbf z_m^{(r)}=\mathbf x_m^{(r)}.

$$

第七，基于完整轨线进行后续切分。注意：切分单位应是整条轨线，而不是窗口或单点。否则相邻窗口可能同时出现在训练和测试集中，导致 rollout 指标虚高。这个原则已经在 ODEs_dataset 的数据协议中被明确强调。fileciteturn4file1

---

### 5. Key assumptions

1. **第一版采用自治 ODE**  
   默认使用无受迫阻尼 Duffing：

   $$

   \dot q=v,
   \qquad
   \dot v=-\delta v-\alpha q-\beta q^3.
   
$$

2. **第一版采用全状态观测**  
   默认

   $$

   \mathbf z=\mathbf x=(q,v)^\top.
   
$$

3. **默认系统为双井结构**  
   采用

   $$

   \alpha<0,\qquad \beta>0.
   
$$

   这样 Duffing 的核心特征是双势阱、多吸引域和非线性势能结构。

4. **默认阻尼不太强**  
   若 $\delta$ 太大，轨线会很快坍缩到稳定平衡点，数据缺少非线性传播信息。

5. **默认不进入强刚性区域**  
   不选择过大的 $\beta$、过大的初始能量或极小时间尺度，否则数值积分难度会不必要增加。

6. **默认采样步长需要解析势阱内振荡**  
   $\tau$ 应足够小，使得势阱附近的阻尼振荡不过度 aliasing。

7. **长期轨线可能趋于平衡点**  
   无受迫阻尼 Duffing 的长期极限不是极限环，而是稳定平衡点。因此它更适合测试势阱结构、吸引域和非线性瞬态传播，而不是测试长期持续振荡。

---

### 6. Numerical risks

1. **数据长期退化为平衡点附近样本**  
   无受迫阻尼 Duffing 最终会落入左右势阱。如果轨线太长，大部分样本会集中在平衡点附近，导致训练集动态信息不足。  
   诊断方式：检查不同时间段的 $(q,v)$ 分布，以及速度 $v$ 是否长期接近零。

2. **左右势阱样本不平衡**  
   若初值区域或随机种子不合适，数据可能大量落入同一个势阱。  
   诊断方式：根据最终 $q(T)$ 的符号统计左 / 右吸引域比例。

3. **势垒附近初值敏感**  
   靠近分界流形的轨线可能对数值误差和采样误差敏感。  
   诊断方式：单独标记初始能量接近势垒能量的轨线。

4. **能量单调性被破坏**  
   对无受迫阻尼版本，应有

   $$

   E_{m+1}\le E_m
   
$$

   近似成立。若能量频繁上升，说明积分误差、采样误差或公式实现存在问题。

5. **参数导致非预期动力学**  
   若 $\beta<0$，势能高阶项向下，可能导致大振幅逃逸或数值爆炸。因此第一版不建议开放 $\beta<0$。

6. **采样步长 aliasing**  
   势阱附近近似为阻尼线性振子。若 $\tau$ 太大，会错过局部振荡结构，使 one-step 与 rollout 数据质量下降。

7. **受迫版本的相位变量不连续**  
   若后续采用受迫 Duffing 并直接保存 $\theta\in[0,2\pi)$，会在 $2\pi\to0$ 处产生人工跳跃。更稳妥的是保存 $(\cos\theta,\sin\theta)$。

8. **归一化受双簇结构影响**  
   双井数据通常呈现左右两个簇。全局标准化可能让势垒附近样本权重过小。后续评测时应检查归一化前后的相图和边界区域密度。

---

### 7. Preliminary package direction

后续实现时，可以考虑以下 Julia 包方向，但正式编码前需要查官方文档确认接口、推荐写法和当前版本行为。

1. **DifferentialEquations.jl / SciML 生态**  
   用于 ODE 数值积分、容差控制、固定采样点保存。需要重点确认 ODE 问题定义、求解器选择、保存时间点和事件 / 回调机制。

2. **LinearAlgebra**  
   用于 Jacobian、局部线性化、特征值诊断和基础矩阵计算。

3. **Random / Distributions**  
   用于初值采样、参数采样和随机种子控制。需要保证轨线级可复现。

4. **Statistics / StatsBase**  
   用于吸引域比例、状态均值方差、能量统计、轨线分布诊断。

5. **JLD2 / HDF5 / JSON3 / TOML**  
   后续用于保存轨线、manifest 和配置。具体格式应在代码工程计划阶段再确定。

---

### 8. Wait for confirmation

请你确认或修改下面这个数学选择：

我建议 **第一版 Duffing 对象采用无受迫、阻尼、双井、全状态观测的二维自治系统**：

$$

\dot q = v,
\qquad
\dot v = -\delta v-\alpha q-\beta q^3,

$$

默认结构为

$$

\delta>0,\qquad \alpha=-1,\qquad \beta=1,
\qquad
\mathbf z=(q,v)^\top.

$$

周期受迫 Duffing 先作为后续扩展版本，通过相位变量增广成三维自治系统。确认后，我再进入 Step 2，按照 ODEs_dataset 代码工程指南写详细代码工程计划书。