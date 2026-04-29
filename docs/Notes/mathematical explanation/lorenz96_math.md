## Step 1：Lorenz ’96 系统数学 / 算法说明

### 1. Task understanding

本次任务是把 **Lorenz ’96** 接入 `ODEs_dataset` 的 `v1_core` 主集合。项目指南中已将 Lorenz ’96 定位为 `v1_core` 的最后一个对象，并强调它承担的是“高维混沌 / 复杂传播”的角色，而不是低维混沌系统的简单重复；它的核心价值在于 **高维、平移对称、参数主导、长期统计性质可比**。fileciteturn2file0

本次数学说明暂定第一版采用：

- 标准 Lorenz ’96 连续时间自治系统；
- 状态维度建议取经典设置 $d_x=K=40$；
- forcing 参数固定为经典混沌设置 $F=8$；
- 全状态观测；
- 无噪声；
- 数值积分后丢弃 burn-in，再保存吸引子轨线；
- 诊断重点包括高维轨线统计、局部坐标时间序列、相邻变量热图、长期统计量，而不是三维相空间图作为主诊断。

输出对象应符合 ODEs_dataset 的通用协议：先生成状态轨线 $\{\mathbf x_m\}_{m=1}^{M+1}$，再经过观测链得到 $\{\mathbf z_m\}_{m=1}^{M+1}$，随后再进入 split、window、task 和 metric 流程。该流水线是项目规范中的核心数据路径。fileciteturn2file1

---

### 2. Mathematical objects and dimensions

Lorenz ’96 的状态为

$$

\mathbf x(t)
=
(x_1(t),x_2(t),\dots,x_K(t))^\top
\in \mathbb R^K .

$$

第一版建议固定

$$

K=40,
\qquad
F=8.

$$

其中：

- $K$：空间格点数 / 环上变量数；
- $F$：外部强迫参数；
- $\mathbf x_0\in\mathbb R^K$：初值；
- $\tau>0$：数据保存采样步长；
- $M+1$：正式保存的快照数量；
- $B$：burn-in 快照数或 burn-in 时间长度；
- $R$：轨线条数。

单条轨线的状态矩阵为

$$

\mathbf X
=
\begin{bmatrix}
\mathbf x_1 & \mathbf x_2 & \cdots & \mathbf x_{M+1}
\end{bmatrix}
\in\mathbb R^{K\times(M+1)}.

$$

按照项目观测链记号，低维或有限维 ODE 的全状态观测可取

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,

$$

因此

$$

\mathbf z_m=\mathbf x_m,
\qquad
\mathbf Z=\mathbf X
\in\mathbb R^{K\times(M+1)}.

$$

这与项目文档中“状态变量 $\mathbf x$”和“学习器输入变量 $\mathbf z$”分离的约定一致；即使本任务中 $\mathbf z=\mathbf x$，接口上仍应保留观测链抽象。fileciteturn2file1

---

### 3. Core formulas / numerical procedures

Lorenz ’96 标准方程为

$$

\frac{d x_i}{dt}
=
(x_{i+1}-x_{i-2})x_{i-1}
-
x_i
+
F,
\qquad
i=1,\dots,K.

$$

采用周期边界条件：

$$

x_{K+1}=x_1,
\qquad
x_0=x_K,
\qquad
x_{-1}=x_{K-1}.

$$

更统一地，可以把下标解释为模 $K$ 的循环索引：

$$

\dot x_i
=
(x_{i+1}-x_{i-2})x_{i-1}
-
x_i
+
F,
\qquad
i\in \mathbb Z/K\mathbb Z.

$$

向量形式写作

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x;F),
\qquad
\mathbf x(t)\in\mathbb R^K.

$$

离散采样轨线为

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m),
\qquad
m=1,\dots,M.

$$

其中 $\mathbf F^\tau$ 是连续系统在时间间隔 $\tau$ 下的流映射。

由于 Lorenz ’96 是高维混沌系统，正式数据生成建议使用两段式积分：

$$

\mathbf x_0
\longrightarrow
\text{burn-in}
\longrightarrow
\widetilde{\mathbf x}_0
\longrightarrow
\{\mathbf x_m\}_{m=1}^{M+1}.

$$

其中 $\widetilde{\mathbf x}_0$ 是进入吸引子附近后的初始状态。正式保存只包含 burn-in 后的轨线。

推荐的初值构造方式是围绕平衡背景 $F\mathbf 1$ 加小扰动：

$$

\mathbf x_0
=
F\mathbf 1
+
\boldsymbol\epsilon,
\qquad
\boldsymbol\epsilon\in\mathbb R^K.

$$

例如仅扰动某一个分量，或对所有分量加入小随机扰动。数学上只要求：

$$

\|\boldsymbol\epsilon\|_2 \ll \sqrt K |F|.

$$

---

### 4. Algorithmic logic

数学层面的生成逻辑如下。

首先固定系统维度 $K$、forcing 参数 $F$、采样步长 $\tau$、保存长度 $M+1$、burn-in 长度以及轨线条数 $R$。

然后对每条轨线 $q=1,\dots,R$，采样初值

$$

\mathbf x_0^{(q)}\in\mathbb R^K.

$$

接着从 $\mathbf x_0^{(q)}$ 开始积分 Lorenz ’96 方程，先经过 burn-in 得到

$$

\widetilde{\mathbf x}_0^{(q)}.

$$

再从 $\widetilde{\mathbf x}_0^{(q)}$ 出发继续积分，并按固定采样间隔 $\tau$ 保存

$$

\mathbf x_1^{(q)},\mathbf x_2^{(q)},\dots,\mathbf x_{M+1}^{(q)}.

$$

在全状态、无噪声观测下，观测快照为

$$

\mathbf z_m^{(q)}
=
\mathbf x_m^{(q)}.

$$

每条轨线形成矩阵

$$

\mathbf X^{(q)}
=
\mathbf Z^{(q)}
=
\begin{bmatrix}
\mathbf x_1^{(q)}
&
\cdots
&
\mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in\mathbb R^{K\times(M+1)}.

$$

之后的数据协议应遵守项目要求：切分单位是整条轨线，而不是窗口或单点样本；窗口样本应在 train / val / test 各自内部派生，避免相邻窗口泄漏到不同集合。项目代码指南也明确要求默认切分单位为整条轨线，并且窗口协议包括 one-step、rollout 和 statistics 三类基础对象。fileciteturn2file1

---

### 5. Key assumptions

本说明默认以下设定。

第一版系统设定：

$$

K=40,\qquad F=8.

$$

这是 Lorenz ’96 的经典高维混沌 benchmark 设置。它适合作为 v1_core 最后一个对象，因为它明显高于 Lorenz ’63 / Rössler 的维度，并具有循环平移结构。

观测设定：

$$

\mathbf z=\mathbf x.

$$

即全状态观测、无噪声、无降维、无非线性传感器。虽然本任务使用恒等观测，工程上仍应保留 $U,S,Z$ 观测链位置，因为项目规范要求动力系统与观测链解耦。fileciteturn2file1

参数设定：

$$

F=8

$$

在第一版中固定，不做参数泛化。但 Lorenz ’96 的天然参数泛化方向就是改变 $F$。后续可以用 $F$ 构造 Split-P，但不建议在第一版 v1_core 冻结前同时引入参数泛化。

数据设定：

- burn-in 后保存吸引子轨线；
- 保存矩阵按列表示时间快照；
- 每列是一个 $K$-维状态；
- 多条轨线通过轨线编号 $q$ 区分；
- 正式任务可以派生 one-step、multi-step rollout 和 statistics windows。

诊断设定：

Lorenz ’96 不适合只依赖三维相图诊断。建议正式诊断至少包括：

$$

x_i(t)\ \text{的若干代表坐标时间序列},

$$

$$

(i,t)\mapsto x_i(t)\ \text{的空间-时间热图},

$$

$$

\text{变量均值、方差、协方差、能量型统计量},

$$

以及 rollout 任务下的短期误差增长和长期统计偏差。

---

### 6. Numerical risks

Lorenz ’96 在本项目中比前面的 v1_core 对象更容易暴露数值和数据协议问题。

**循环索引错误。**  
方程依赖 $x_{i+1},x_{i-1},x_{i-2}$。最容易出错的是边界项：

$$

i=1,2,K

$$

附近的索引。如果周期边界写错，系统仍可能运行，但统计性质会完全错误。

**维度升高导致的数据矩阵约定错误。**  
单条轨线应为

$$

K\times(M+1),

$$

而不是

$$

(M+1)\times K.

$$

这对后续 Koopman / EDMD / neural dataset 接口非常关键。项目规范中也明确状态矩阵和观测矩阵按列存储快照。fileciteturn2file1

**混沌敏感性。**  
Lorenz ’96 对初值误差敏感。单条轨线逐点长期预测误差会快速增长，因此长期任务不应只看点态误差，还应看长期统计性质。

**积分步长过大。**  
若内部积分步长或保存步长过大，可能产生伪混沌、数值耗散或直接发散。需要区分 solver 内部自适应步长与数据保存步长 $\tau$。

**burn-in 不足。**  
若 burn-in 太短，保存轨线可能仍包含初值松弛过程，导致数据统计不稳定。Lorenz ’96 的正式版本应检查 burn-in 前后统计量是否稳定。

**状态尺度和归一化。**  
在 $F=8$、$K=40$ 时，不同变量由于循环对称性应具有相近统计分布。若某些坐标均值或方差显著异常，可能是索引错误、积分错误或轨线未进入吸引子。

**参数命名风险。**  
Lorenz ’96 中常用 $K$、$N$、$d$ 表示维度，容易与 Koopman 矩阵 $K$ 混淆。建议数学说明中用 $K$ 表示系统维度，但在后续代码工程计划中应明确区分 `state_dim` 和 Koopman operator 矩阵。

**数据量风险。**  
$K=40$ 会显著增大 raw / processed 数据体积。small / medium / large 三档数据规模需要谨慎控制。系统指南也建议每个系统固定 small、medium、large 三档，并固定轨线条数、轨线长度、采样步长、窗口长度、噪声水平和参数范围。fileciteturn2file0

---

### 7. Preliminary package direction

后续进入代码工程计划时，Julia 包方向可以是：

- `DifferentialEquations.jl` / `OrdinaryDiffEq.jl`：用于 Lorenz ’96 的连续时间 ODE 数值积分；
- `LinearAlgebra` / `Statistics`：用于均值、方差、协方差、能量型统计量和数据质量诊断；
- `Random`：用于多轨线初值扰动和可复现实验种子；
- `JLD2` 或类似格式：用于保存 raw / processed / manifest 数据对象；
- `Plots.jl`、`Makie.jl` 或其他绘图库：用于时间序列、空间-时间热图、统计图和代表性投影图。

重要说明：这里仅给出包方向，不预设 API、函数名、关键字参数或具体实现方式。进入实现前需要检查官方文档，尤其是 ODE solver 的保存步长、容差、回调和数据输出格式。

---

### 8. Wait for confirmation

请你确认或修改这份 Lorenz ’96 的数学设定：

$$

K=40,\qquad F=8,\qquad \mathbf z=\mathbf x,

$$

即 **标准 40 维 Lorenz ’96、固定参数、全状态观测、无噪声、burn-in 后保存吸引子轨线**。

确认后我再进入 Step 2，按照 `ODEs_dataset` 代码工程指南写详细代码工程计划书。