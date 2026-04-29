## Step 1：Rössler 系统数学说明

### 1. Task understanding

本次任务是在 **ODEs_dataset** 中新增经典 **Rössler 系统**的数据生成对象。根据系统指南，Rössler 属于 `v1_core` 的经典混沌系统；它与 Lorenz ’63 一起用于测试低维耗散混沌，但其吸引子几何更接近“单卷曲”结构，因此可以检验算法是否只适配 Lorenz 双翼结构，还是能处理不同 chaotic geometry。fileciteturn2file1

本阶段只给出数学与算法说明，不进入代码工程计划。

目标是生成连续时间三维自治 ODE 的离散轨线：

$$

\dot{\mathbf x}=\mathbf f(\mathbf x;\boldsymbol\mu),
\qquad
\mathbf x(t)\in\mathbb R^3,

$$

并通过项目统一的数据协议得到：

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

这与 ODEs_dataset 指南中规定的“系统配置 → 轨线生成 → 观测处理 → 数据保存 → 切分与窗口 → 任务与评测”流程一致。fileciteturn2file0

---

### 2. Mathematical objects and dimensions

#### 2.1 状态变量

设

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

状态维度为

$$

d_x=3.

$$

Rössler 系统的标准形式可写为：

$$

\begin{aligned}
\dot x &= -y-z,\\
\dot y &= x+a y,\\
\dot z &= b+z(x-c),
\end{aligned}

$$

其中参数为

$$

\boldsymbol\mu=(a,b,c)\in\mathbb R^3.

$$

经典混沌参数通常取：

$$

a=0.2,\qquad b=0.2,\qquad c=5.7.

$$

因此右端函数为

$$

\mathbf f(\mathbf x;\boldsymbol\mu)
=
\begin{bmatrix}
-y-z\\
x+a y\\
b+z(x-c)
\end{bmatrix}.

$$

#### 2.2 离散采样轨线

给定采样步长

$$

\tau>0,

$$

连续流映射记为

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m),
\qquad
m=1,\dots,M.

$$

单条轨线存储为列优先矩阵：

$$

\mathbf X
=
\begin{bmatrix}
\mathbf x_1 & \mathbf x_2 & \cdots & \mathbf x_{M+1}
\end{bmatrix}
\in\mathbb R^{3\times(M+1)}.

$$

若有 $R$ 条轨线，则第 $q$ 条轨线记为：

$$

\mathbf X^{(q)}
\in\mathbb R^{3\times(M+1)},
\qquad
q=1,\dots,R.

$$

#### 2.3 观测变量

按照项目规范，数据对象不应默认等同于状态，而应经过观测链：

$$

\mathbf x
\xmapsto{U}
\mathbf u
\xmapsto{S}
\mathbf s
\xmapsto{Z}
\mathbf z.

$$

对于第一版 Rössler 数据集，建议采用最简单的全状态观测：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,

$$

因此

$$

\mathbf z_m=\mathbf x_m,
\qquad
d_z=d_x=3.

$$

项目指南也明确要求动力系统与观测链解耦，下游 benchmark 依赖 $\mathbf z_m$，而不直接绑定 $\mathbf x_m$。fileciteturn2file0

---

### 3. Core formulas / numerical procedures

#### 3.1 数值积分

对每条初值

$$

\mathbf x_0^{(q)}
\in\mathbb R^3,

$$

从连续系统积分得到高精度轨线：

$$

\mathbf x(t;\mathbf x_0^{(q)},\boldsymbol\mu).

$$

然后按固定采样间隔 $\tau$ 取样：

$$

t_m=t_{\mathrm{start}}+m\tau,
\qquad
\mathbf x_m^{(q)}
=
\mathbf x(t_m;\mathbf x_0^{(q)},\boldsymbol\mu).

$$

Rössler 是混沌系统，建议区分：

$$

T_{\mathrm{burn}}>0

$$

和正式保存区间。先积分到 $T_{\mathrm{burn}}$，丢弃暂态，再从吸引子附近开始保存：

$$

\mathbf x_{\mathrm{burn}}^{(q)}
=
\mathbf x(T_{\mathrm{burn}};\mathbf x_0^{(q)}),

$$

正式数据为

$$

\mathbf x_m^{(q)}
=
\mathbf x(T_{\mathrm{burn}}+m\tau;\mathbf x_0^{(q)}),
\qquad
m=0,\dots,M.

$$

#### 3.2 一步样本

一步预测任务使用相邻快照：

$$

(\mathbf z_m,\mathbf z_{m+1}),
\qquad
m=1,\dots,M.

$$

在全状态观测下：

$$

(\mathbf z_m,\mathbf z_{m+1})
=
(\mathbf x_m,\mathbf x_{m+1}).

$$

#### 3.3 多步 rollout 窗口

多步传播窗口为：

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}),

$$

其中 $L$ 是 rollout horizon。

对应输入与目标为：

$$

\text{input}=\mathbf z_s,
\qquad
\text{target}=(\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

#### 3.4 长期统计诊断

由于 Rössler 是耗散混沌系统，除了短期预测误差，还应保留长期统计诊断。可考虑：

时间均值：

$$

\bar{\mathbf x}
=
\frac{1}{M+1}
\sum_{m=0}^{M}
\mathbf x_m.

$$

协方差：

$$

\mathbf C_x
=
\frac{1}{M}
\sum_{m=0}^{M}
(\mathbf x_m-\bar{\mathbf x})
(\mathbf x_m-\bar{\mathbf x})^\top.

$$

坐标范围：

$$

x_{\min},x_{\max},
\quad
y_{\min},y_{\max},
\quad
z_{\min},z_{\max}.

$$

局部步长增量：

$$

\Delta_m
=
\|\mathbf x_{m+1}-\mathbf x_m\|_2.

$$

这些量用于检查轨线是否落在合理吸引子范围、是否存在积分爆炸、是否采样过粗。

#### 3.5 耗散性检查

Rössler 向量场的散度为：

$$

\nabla\cdot \mathbf f
=
\frac{\partial \dot x}{\partial x}
+
\frac{\partial \dot y}{\partial y}
+
\frac{\partial \dot z}{\partial z}
=
0+a+(x-c)
=
x+a-c.

$$

在经典参数 $a=0.2,c=5.7$ 下，

$$

\nabla\cdot \mathbf f=x-5.5.

$$

沿吸引子长期平均通常应表现为体积收缩趋势：

$$

\left\langle \nabla\cdot \mathbf f \right\rangle_t < 0.

$$

这可作为数据质量诊断之一，但不应当作为严格点态约束，因为 $x(t)$ 可能局部使散度为正。

---

### 4. Algorithmic logic

数学层面的生成逻辑如下。

1. **固定系统参数**  
   第一版建议使用经典混沌参数：
   $$

   (a,b,c)=(0.2,0.2,5.7).
   
$$
   暂不做参数泛化。

2. **采样初值**  
   从预设初值区域中采样若干个 $\mathbf x_0^{(q)}$。  
   由于 Rössler 存在吸引子，初值只需要保证积分能进入吸引子区域，不必直接落在吸引子上。

3. **burn-in 积分**  
   对每条轨线先积分到 $T_{\mathrm{burn}}$，丢弃暂态，使正式保存数据更接近吸引子动力学。

4. **正式轨线积分与采样**  
   从 burn-in 后状态继续积分，并按固定采样步长 $\tau$ 保存：
   $$

   \{\mathbf x_m^{(q)}\}_{m=0}^{M}.
   
$$

5. **观测链处理**  
   第一版使用全状态无噪声观测：
   $$

   \mathbf z_m^{(q)}=\mathbf x_m^{(q)}.
   
$$

6. **构造数据对象**  
   每条轨线具有：
   $$

   \mathbf X^{(q)}\in\mathbb R^{3\times(M+1)},
   \qquad
   \mathbf Z^{(q)}\in\mathbb R^{3\times(M+1)}.
   
$$

7. **轨线级切分**  
   按轨线编号 $q$ 切分 train / val / test。  
   项目规范要求默认切分单位是整条轨线，而不是窗口或单点样本，以避免相邻窗口泄漏。fileciteturn2file0

8. **窗口派生**  
   在每个 split 内部分别构造 one-step、rollout、statistics 窗口。

9. **诊断输出**  
   应检查：
   $$

   \min/\max,\quad
   \mathrm{mean},\quad
   \mathrm{std},\quad
   \max_m \|\mathbf x_m\|_2,
   \quad
   \max_m \|\mathbf x_{m+1}-\mathbf x_m\|_2,
   \quad
   \left\langle x+a-c \right\rangle_t.
   
$$

10. **三维相空间诊断**  
    Rössler 属于三维混沌吸引子，正式数据应检查三维相空间轨线：
    $$

    (x(t),y(t),z(t)).
    
$$
    这不是算法输入的一部分，而是数据质量与人工可读诊断。

---

### 5. Key assumptions

本数学说明默认以下设定：

1. **系统类型**  
   三维自治连续时间 ODE：

   $$

   \dot{\mathbf x}=\mathbf f(\mathbf x).
   
$$

2. **参数设定**  
   第一版采用固定经典参数：

   $$

   a=0.2,\qquad b=0.2,\qquad c=5.7.
   
$$

3. **观测设定**  
   第一版采用全状态观测：

   $$

   \mathbf z=\mathbf x.
   
$$

4. **噪声设定**  
   第一版不加观测噪声：

   $$

   \boldsymbol\varepsilon_m=\mathbf 0.
   
$$

5. **参数泛化**  
   第一版暂不做参数泛化。  
   所有 train / val / test 共享相同 $(a,b,c)$，只通过不同初值生成不同轨线。

6. **切分方式**  
   使用轨线级 Split-I，即测试集使用未见初值，不把同一条轨线的窗口拆到不同 split 中。

7. **采样方式**  
   采样步长 $\tau$ 应足够小，以解析 Rössler 吸引子的卷曲结构；同时不宜过小到造成数据冗余严重。

8. **burn-in**  
   正式保存数据应从 burn-in 后开始，以减少暂态对吸引子统计的污染。

---

### 6. Numerical risks

1. **混沌敏感性**  
   Rössler 对初值敏感。长期逐点预测误差会自然增长，因此长期 rollout 不应只用点态误差判断模型失败，还应看统计一致性。

2. **采样步长过大**  
   若 $\tau$ 太大，吸引子的卷曲结构会被欠采样，造成轨线跳跃、局部速度异常和 Koopman / EDMD 近似困难。

3. **采样步长过小**  
   若 $\tau$ 太小，相邻样本高度相关，one-step 任务过于容易，但长期传播仍可能困难；也会增加数据量和存储压力。

4. **burn-in 不足**  
   如果 $T_{\mathrm{burn}}$ 太短，轨线仍包含强暂态，统计窗口会混入非吸引子动力学。

5. **初值区域不当**  
   初值过远可能导致长暂态；初值过于集中则轨线多样性不足。

6. **数值积分误差积累**  
   混沌系统中小的局部积分误差会快速放大。数据生成阶段应使用比下游模型更严格的积分公差。

7. **异常轨线检查**  
   应检查是否存在：
   $$

   \max_m \|\mathbf x_m\|_2
   
$$
   异常偏大、NaN、Inf、轨线未进入吸引子或明显偏离典型 Rössler 几何。

8. **归一化风险**  
   若后续使用标准化，应只从训练集估计均值和尺度，再应用到 val / test；不能用全数据统计量泄漏测试信息。

9. **三维绘图误判**  
   单条轨线若太短，可能看不到完整吸引子；轨线若太长且点太密，绘图可能遮挡结构。诊断图需要合理抽样或透明度控制，但这是后续工程计划问题。

10. **Koopman 角度的谱风险**  
    Rössler 的混沌吸引子不会给出简单有限维闭合谱结构。有限维 EDMD / Koopman 学习更可能学习到局部近似、统计模态或有限窗传播结构，而不是精确全局闭合。

---

### 7. Preliminary package direction

后续实现时可能涉及以下 Julia 包方向，但现在不指定 API：

1. **DifferentialEquations.jl / OrdinaryDiffEq.jl**  
   用于连续时间 ODE 数值积分。需要查官方文档确认具体 solver、保存采样点、公差设置和随机初值批量生成流程。

2. **StaticArrays.jl**  
   对三维小状态向量可能有性能优势，但是否使用取决于项目既有接口是否更偏向普通数组。

3. **JLD2.jl / HDF5.jl / JSON3.jl**  
   用于保存轨线数据、manifest 和配置对象。具体格式应与 ODEs_dataset 现有数据协议保持一致。

4. **Plots.jl / Makie.jl**  
   用于三维相空间轨线图。Rössler 的正式数据质量诊断应包含 $(x,y,z)$ 三维吸引子图。

5. **LinearAlgebra / Statistics**  
   用于均值、协方差、范数、条件检查和基础诊断量计算。

重要原则：实现阶段必须查官方文档，不从记忆中编造 solver 接口、保存选项或绘图 API。

---

### 8. Wait for confirmation

请你确认或修改本次数学设定，尤其是以下几点：

是否采用标准参数

$$

(a,b,c)=(0.2,0.2,5.7),

$$

全状态观测、固定参数、无噪声、burn-in 后保存吸引子轨线，并在正式诊断中输出三维相空间轨线图？

确认后我再进入 **Step 2：详细代码工程计划书**。