## Step 1：数学 / 算法说明书  
### ODEs_dataset 中的 EDMDc–Duffing 开环强迫数据集

### 1. Task understanding

本次任务是在 `ODEs_dataset` 中新增一个专门服务 **EDMDc / Koopman with control** 的受控 ODE 数据集。

目标不是训练 EDMDc，而是生成下游 EDMDc 可以直接消费的数据对象：

$$

(\mathbf x_m,\mathbf z_m,u_m,\mathbf x_{m+1},\mathbf z_{m+1})

$$

其中：

- 基础动力系统为 Duffing 振子；
- 控制 / 强迫项为**开环输入**，即 $u(t)$ 预先生成，不依赖当前状态 $\mathbf x(t)$；
- 非线性强度取 3 档；
- 观测噪声取 3 档，并同时保留无噪声版本；
- 所有数据仍遵守 ODEs_dataset 的观测链思想  
  $$

  \mathbf x \xmapsto{U}\mathbf u \xmapsto{S}\mathbf s \xmapsto{Z}\mathbf z ,
  
$$
  即下游算法原则上使用 $\mathbf z_m$，而不是绕过数据协议直接使用隐藏状态。ODEs_dataset 文档也明确区分状态 $\mathbf x_m$、观测输入 $\mathbf z_m$、split、window 和 benchmark task 的流水线。fileciteturn2file0

本数据集的预期输出应至少包含：

$$

\mathbf X
=
\begin{bmatrix}
\mathbf x_1 & \cdots & \mathbf x_{M+1}
\end{bmatrix},
\qquad
\mathbf Z^{(\eta)}
=
\begin{bmatrix}
\mathbf z^{(\eta)}_1 & \cdots & \mathbf z^{(\eta)}_{M+1}
\end{bmatrix},
\qquad
\mathbf U
=
\begin{bmatrix}
u_1 & \cdots & u_M
\end{bmatrix}.

$$

其中 $\eta$ 表示噪声强度，包含 $\eta=0$ 的 clean 版本。

---

### 2. Mathematical objects and dimensions

#### 2.1 状态变量

采用二维 Duffing 状态：

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

状态维数为：

$$

d_x=2.

$$

全状态观测时：

$$

d_z=2.

$$

---

#### 2.2 受控 Duffing 方程

建议采用如下受控 Duffing 形式：

$$

\ddot q
+
\delta \dot q
+
\alpha q
+
\beta q^3
=
b_u u(t).

$$

写成一阶系统：

$$

\dot x_1=x_2,

$$

$$

\dot x_2
=
-\delta x_2
-\alpha x_1
-\beta x_1^3
+
b_u u(t).

$$

即

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x,u;\boldsymbol\mu),

$$

其中参数为：

$$

\boldsymbol\mu
=
(\delta,\alpha,\beta,b_u).

$$

本任务中重点扫描非线性强度：

$$

\beta\in
\{\beta_{\mathrm{low}},
\beta_{\mathrm{mid}},
\beta_{\mathrm{high}}\}.

$$

其余参数如 $\delta,\alpha,b_u$ 建议在第一版中固定，避免把“非线性强度效应”和“阻尼 / 线性刚度 / 输入增益效应”混在一起。

---

#### 2.3 开环输入对象

EDMDc 的关键是每个状态转移都伴随一个已知输入：

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m,u_m;\boldsymbol\mu).

$$

这里 $u_m\in\mathbb R^{d_u}$。第一版建议只使用单输入：

$$

d_u=1.

$$

为了与离散 EDMDc 快照形式严格对齐，建议采用 **zero-order hold 开环输入**：

$$

u(t)=u_m,
\qquad
t\in[t_m,t_{m+1}),

$$

其中

$$

t_m=t_0+(m-1)\tau.

$$

输入序列为预先生成的开环序列：

$$

\{u_m\}_{m=1}^{M},

$$

并满足：

$$

u_m \not= \kappa(\mathbf x_m),

$$

即它不是反馈控制，而是外部给定强迫。

为了保证 EDMDc 回归中输入方向可辨识，$u_m$ 不应是单一正弦或常数。建议第一版采用分段常值的随机或伪随机输入，例如：

$$

u_m \sim \mathcal U[-A_u,A_u],

$$

或经过平滑 / 限幅的 band-limited open-loop signal。数学上最重要的是：

$$

\operatorname{rank}
\begin{bmatrix}
\boldsymbol\Psi_X\\
\mathbf U
\end{bmatrix}

$$

不能因为输入缺乏激励而退化。

---

#### 2.4 参数网格

本任务的主网格是：

$$

\beta_i\in
\{\beta_{\mathrm{low}},
\beta_{\mathrm{mid}},
\beta_{\mathrm{high}}\},
\qquad i=1,2,3,

$$

$$

\eta_j\in
\{0,\eta_{\mathrm{low}},\eta_{\mathrm{mid}},\eta_{\mathrm{high}}\},
\qquad j=0,1,2,3.

$$

因此每个初值 / 输入种子组合下有：

$$

3\times 4=12

$$

个观测版本：

$$

(\beta_i,\eta_j).

$$

注意这里的 clean 数据不是额外系统，而是 $\eta=0$ 的观测版本。

---

### 3. Core formulas / numerical procedures

#### 3.1 连续时间到离散时间

对每条轨线，给定：

$$

\mathbf x_0^{(r)},
\qquad
\{u_m^{(r)}\}_{m=1}^{M},
\qquad
\beta_i,
\qquad
\tau,

$$

通过数值积分得到：

$$

\mathbf x_{m+1}^{(r,i)}
=
\mathbf F^\tau
\left(
\mathbf x_m^{(r,i)},u_m^{(r)};\boldsymbol\mu_i
\right).

$$

其中 $r$ 是轨线编号，$i$ 是非线性强度编号。

状态轨线矩阵为：

$$

\mathbf X^{(r,i)}
=
\begin{bmatrix}
\mathbf x_1^{(r,i)}
&
\mathbf x_2^{(r,i)}
&
\cdots
&
\mathbf x_{M+1}^{(r,i)}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

输入矩阵为：

$$

\mathbf U^{(r)}
=
\begin{bmatrix}
u_1^{(r)}
&
u_2^{(r)}
&
\cdots
&
u_M^{(r)}
\end{bmatrix}
\in\mathbb R^{1\times M}.

$$

注意输入只有 $M$ 个，因为它对应 $M$ 个转移：

$$

\mathbf x_m \longrightarrow \mathbf x_{m+1}.

$$

---

#### 3.2 观测与加噪

第一版建议采用全状态观测：

$$

U=\mathcal I,
\qquad
S=\mathcal I.

$$

无噪声时：

$$

\mathbf z_m^{(0)}=\mathbf x_m.

$$

有噪声时：

$$

\mathbf z_m^{(\eta)}
=
\mathbf x_m+\boldsymbol\varepsilon_m^{(\eta)}.

$$

建议采用相对尺度高斯噪声：

$$

\boldsymbol\varepsilon_m^{(\eta)}
=
\eta
\,
\mathbf D_x
\boldsymbol\xi_m,
\qquad
\boldsymbol\xi_m\sim\mathcal N(\mathbf 0,\mathbf I_2),

$$

其中：

$$

\mathbf D_x
=
\operatorname{diag}(s_q,s_v)

$$

是位移和速度的参考尺度。参考尺度可以来自 clean 训练轨线的标准差或 RMS。这样不同坐标的噪声强度不会因为物理量纲不同而失衡。

于是：

$$

\mathbf Z^{(r,i,\eta)}
=
\begin{bmatrix}
\mathbf z_1^{(r,i,\eta)}
&
\cdots
&
\mathbf z_{M+1}^{(r,i,\eta)}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

第一版建议只给状态观测加噪，不给输入 $u_m$ 加噪。原因是 EDMDc 的第一基准应先测试“状态观测噪声下的 Koopman-control 回归鲁棒性”，而不是同时引入输入测量误差。

---

#### 3.3 EDMDc 快照矩阵

对某个 $(\beta_i,\eta_j)$ 数据子集，构造一步快照：

$$

\mathbf Z_0
=
\begin{bmatrix}
\mathbf z_1 & \mathbf z_2 & \cdots & \mathbf z_M
\end{bmatrix}
\in\mathbb R^{2\times M},

$$

$$

\mathbf Z_1
=
\begin{bmatrix}
\mathbf z_2 & \mathbf z_3 & \cdots & \mathbf z_{M+1}
\end{bmatrix}
\in\mathbb R^{2\times M},

$$

$$

\mathbf U_0
=
\begin{bmatrix}
u_1 & u_2 & \cdots & u_M
\end{bmatrix}
\in\mathbb R^{1\times M}.

$$

给定 EDMD 字典：

$$

\boldsymbol\psi:\mathbb R^{2}\to\mathbb R^{N_\psi},

$$

提升后的快照矩阵为：

$$

\boldsymbol\Psi_0
=
\begin{bmatrix}
\boldsymbol\psi(\mathbf z_1)
&
\cdots
&
\boldsymbol\psi(\mathbf z_M)
\end{bmatrix}
\in\mathbb R^{N_\psi\times M},

$$

$$

\boldsymbol\Psi_1
=
\begin{bmatrix}
\boldsymbol\psi(\mathbf z_2)
&
\cdots
&
\boldsymbol\psi(\mathbf z_{M+1})
\end{bmatrix}
\in\mathbb R^{N_\psi\times M}.

$$

EDMDc 的基本线性回归形式为：

$$

\boldsymbol\Psi_1
\approx
\mathbf K \boldsymbol\Psi_0
+
\mathbf B \mathbf U_0,

$$

其中：

$$

\mathbf K\in\mathbb R^{N_\psi\times N_\psi},
\qquad
\mathbf B\in\mathbb R^{N_\psi\times 1}.

$$

堆叠后：

$$

\boldsymbol\Psi_1
\approx
\begin{bmatrix}
\mathbf K & \mathbf B
\end{bmatrix}
\begin{bmatrix}
\boldsymbol\Psi_0\\
\mathbf U_0
\end{bmatrix}.

$$

令

$$

\mathbf\Omega
=
\begin{bmatrix}
\boldsymbol\Psi_0\\
\mathbf U_0
\end{bmatrix}
\in\mathbb R^{(N_\psi+1)\times M},

$$

则最小二乘估计为：

$$

\begin{bmatrix}
\widehat{\mathbf K} & \widehat{\mathbf B}
\end{bmatrix}
=
\boldsymbol\Psi_1 \mathbf\Omega^\dagger.

$$

带 ridge 正则时：

$$

\begin{bmatrix}
\widehat{\mathbf K} & \widehat{\mathbf B}
\end{bmatrix}
=
\boldsymbol\Psi_1
\mathbf\Omega^\top
\left(
\mathbf\Omega\mathbf\Omega^\top+\lambda\mathbf I
\right)^{-1}.

$$

数据集本身不应固定 $\boldsymbol\psi$，但必须保证它可以支持这类 EDMDc 回归。ODEs_dataset 规范也强调数据集层不应嵌入某个特定算法的 latent 结构、算子形式或损失函数；这些应属于下游算法配置。fileciteturn2file0

---

#### 3.4 原状态预测形式

如果字典中包含原始状态坐标，或者下游额外学习线性读出：

$$

\mathbf C\in\mathbb R^{2\times N_\psi},

$$

则状态预测为：

$$

\widehat{\mathbf z}_{m+1}
=
\mathbf C
\left(
\widehat{\mathbf K}\boldsymbol\psi(\mathbf z_m)
+
\widehat{\mathbf B}u_m
\right).

$$

多步开环 rollout 为：

$$

\widehat{\boldsymbol\psi}_{m+\ell+1|m}
=
\widehat{\mathbf K}
\widehat{\boldsymbol\psi}_{m+\ell|m}
+
\widehat{\mathbf B}u_{m+\ell},

$$

$$

\widehat{\mathbf z}_{m+\ell|m}
=
\mathbf C
\widehat{\boldsymbol\psi}_{m+\ell|m}.

$$

这里使用的是未来已知的开环输入序列：

$$

u_m,u_{m+1},\dots,u_{m+L-1}.

$$

---

### 4. Algorithmic logic

数学流程建议如下。

首先，固定 Duffing 主结构：

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x,u;\delta,\alpha,\beta,b_u).

$$

然后选择三档非线性强度：

$$

\beta_{\mathrm{low}},
\quad
\beta_{\mathrm{mid}},
\quad
\beta_{\mathrm{high}}.

$$

对每条轨线，采样初值：

$$

\mathbf x_0^{(r)}
\sim
\mathcal P_{x_0},

$$

并生成开环输入序列：

$$

\{u_m^{(r)}\}_{m=1}^{M}
\sim
\mathcal P_u.

$$

对每个 $\beta_i$，使用 zero-order hold 输入积分：

$$

\mathbf x_{m+1}^{(r,i)}
=
\mathbf F^\tau(\mathbf x_m^{(r,i)},u_m^{(r)};\beta_i).

$$

得到 clean 状态轨线后，再对每个噪声级别 $\eta_j$ 构造观测：

$$

\mathbf z_m^{(r,i,\eta_j)}
=
\mathbf x_m^{(r,i)}
+
\boldsymbol\varepsilon_m^{(\eta_j)}.

$$

最后形成 EDMDc 所需的一步样本：

$$

\left(
\mathbf z_m^{(r,i,\eta_j)},
u_m^{(r)},
\mathbf z_{m+1}^{(r,i,\eta_j)}
\right),
\qquad
m=1,\dots,M.

$$

同时也可形成 rollout 窗口：

$$

\left(
\mathbf z_s,
u_s,u_{s+1},\dots,u_{s+L-1},
\mathbf z_{s+1},\dots,\mathbf z_{s+L}
\right).

$$

这与 ODEs_dataset 中 one-step 和 rollout window 的协议一致：一步样本对应 $(\mathbf z_m,\mathbf z_{m+1})$，rollout 窗口对应 $(\mathbf z_s,\dots,\mathbf z_{s+L})$。fileciteturn2file0

---

### 5. Key assumptions

1. **开环输入独立于状态**

   $$

   u_m \not= \kappa(\mathbf x_m).
   
$$

   因此该数据集不是 closed-loop control 数据集，而是 forced / controlled identification 数据集。

2. **输入在采样区间内保持常值**

   $$

   u(t)=u_m,
   \qquad t\in[t_m,t_{m+1}).
   
$$

   这样 EDMDc 中的 $u_m$ 与转移 $\mathbf x_m\to\mathbf x_{m+1}$ 一一对应。

3. **第一版使用全状态观测**

   $$

   \mathbf z_m=\mathbf x_m+\boldsymbol\varepsilon_m.
   
$$

   不加入部分观测或非线性传感器，避免任务过早复杂化。

4. **噪声只作用于观测，不作用于真实积分状态**

   clean $\mathbf X$ 是数值积分得到的参考轨线；noisy $\mathbf Z^{(\eta)}$ 是算法输入。

5. **输入默认不加噪**

   $$

   \widetilde u_m=u_m.
   
$$

   输入测量噪声可以作为未来扩展，而不是第一版混入。

6. **非线性强度只通过 $\beta$ 扫描**

   第一版先固定 $\delta,\alpha,b_u$，只改变 $\beta$，使不同数据子集之间的差异可解释。

7. **split 应按轨线切分**

   不应先把窗口打乱再划分 train / val / test。项目文档也强调默认切分单位应是整条轨线，而不是窗口或单点样本。fileciteturn2file0

---

### 6. Numerical risks

1. **输入矩阵与状态快照长度错位**

   状态有 $M+1$ 个快照：

   $$

   \mathbf z_1,\dots,\mathbf z_{M+1},
   
$$

   输入只有 $M$ 个：

   $$

   u_1,\dots,u_M.
   
$$

   常见错误是把 $\mathbf U$ 错存成 $M+1$ 列，导致 EDMDc 回归维度错位。

2. **控制输入激励不足**

   如果 $u_m$ 是常数、单频正弦或幅度过小，则

   $$

   \mathbf\Omega=
   \begin{bmatrix}
   \boldsymbol\Psi_0\\
   \mathbf U_0
   \end{bmatrix}
   
$$

   可能秩不足，$\mathbf B$ 难以辨识。

3. **强非线性 Duffing 可能产生大振幅或跨井运动**

   当 $\beta$、输入幅度 $A_u$、初值范围组合不当时，轨线可能出现过大幅值，导致数值积分困难或数据尺度极不均衡。

4. **噪声尺度不平衡**

   位移 $q$ 与速度 $v$ 的自然尺度可能不同。若直接使用同一绝对标准差加噪，可能导致某一通道噪声过大、另一通道几乎无噪。

5. **EDMDc 字典病态**

   高阶多项式字典在 Duffing 大幅值数据上容易出现严重尺度膨胀，导致：

   $$

   \kappa(\mathbf\Omega\mathbf\Omega^\top)
   
$$

   很大。数据集应保留 clean / noisy / scale metadata，方便下游做归一化和正则化。

6. **噪声污染 $\boldsymbol\Psi_0$ 与 $\boldsymbol\Psi_1$**

   若两端快照都使用 noisy observation，则 EDMDc 回归是 errors-in-variables 问题。普通 least squares 会产生偏差。这个偏差正是噪声鲁棒性评测的一部分，但必须在文档中明确。

7. **不同 $\beta$ 数据混合训练的语义问题**

   如果把三档 $\beta$ 混在同一个 EDMDc 回归中，但不把 $\beta$ 作为参数输入，则模型实际上在拟合一个参数混合系统。第一版应明确支持两类任务：

   $$

   \text{fixed-}\beta\text{ identification},
   
$$

   和

   $$

   \text{cross-}\beta\text{ generalization}.
   
$$

8. **输入幅度与非线性强度耦合**

   高 $\beta$ 加强输入可能导致动力学从局部井内振动进入跨井运动。若目标是比较非线性强度，应控制输入幅度一致；若目标是 stress test，则可额外开强输入版本。

---

### 7. Preliminary package direction

后续实现时可能涉及以下 Julia 包方向，但此处不指定 API：

- `DifferentialEquations.jl` / SciML 生态：用于积分受控 Duffing ODE，尤其是处理 time-dependent 或 zero-order hold 输入；
- `Random`：生成初值、输入序列和噪声；
- `LinearAlgebra`：后续 EDMDc 诊断中需要秩、条件数、伪逆、SVD；
- `Statistics`：计算 RMS、标准差、噪声尺度和数据诊断；
- `JSON3.jl` 或 `TOML.jl`：用于配置系统参数、噪声层级、输入策略；
- `JLD2.jl` / `HDF5.jl`：保存轨线矩阵、输入矩阵、manifest；
- `DataFrames.jl` / `CSV.jl`：保存数据规模表、参数表和诊断指标；
- `Plots.jl` 或 `Makie.jl`：绘制 clean/noisy 轨线、相图、输入序列、能量/幅值诊断。

正式实现前应检查这些包的官方文档，尤其是 time-dependent forcing、保存格式、随机种子复现和数组维度约定。

---

### 8. Wait for confirmation

请你确认或修改以下数学设定：

1. 受控 Duffing 是否采用  
   $$

   \ddot q+\delta\dot q+\alpha q+\beta q^3=b_u u(t)
   
$$
   这一形式；
2. 三档非线性强度是否只扫描 $\beta$；
3. 开环输入是否采用 zero-order hold 的随机 / 伪随机输入序列；
4. 噪声是否只加在状态观测 $\mathbf z_m$ 上，不加在输入 $u_m$ 上；
5. 第一版是否固定全状态观测，并保留 clean + 三档 noisy 版本。

确认后我再进入 Step 2，按 ODEs_dataset 的工程目录给出详细任务计划书。