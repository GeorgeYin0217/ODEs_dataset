## Step 1：Jordan / 非正规线性系统的数学说明

### 1. Task understanding

本次任务是构建第三个内部单元测试数据集：

$$

\texttt{unit\_internal / jordan\_nonnormal\_linear}

$$

它服务于 ODEs_dataset 的内部回归测试，而不是公开 benchmark 主榜。项目指南中明确把线性对角、旋转–收缩、Jordan / 非正规系统列为内部单元测试层；其中 Jordan / 非正规系统专门用于暴露不可对角化、上三角结构、非正规传播与结构化谱学习相关的问题。fileciteturn3file1

目标是生成一组解析可控的线性 ODE 轨线：

$$

\dot{\mathbf x}(t)=\mathbf A\mathbf x(t),
\qquad 
\mathbf x(0)=\mathbf x_0,

$$

并通过统一观测链得到算法输入：

$$

\mathbf x \xmapsto{U}\mathbf u\xmapsto{S}\mathbf s\xmapsto{Z}\mathbf z.

$$

对于本内部测试，默认使用最简单的全状态观测：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,
\qquad \mathbf z=\mathbf x.

$$

这与 ODEs_dataset 指南中“状态轨线”和“观测轨线”分离的原则一致：动力系统只负责生成 $\{\mathbf x_m\}$，观测链再生成 $\{\mathbf z_m\}$。fileciteturn3file0

---

### 2. Mathematical objects and dimensions

建议本系统先从二维 Jordan 块开始，必要时再扩展到多维 Jordan 块。

#### 状态变量

$$

\mathbf x(t)=
\begin{bmatrix}
x_1(t)\\
x_2(t)
\end{bmatrix}
\in\mathbb R^2.

$$

#### 连续时间生成矩阵

最小 Jordan 非正规系统取：

$$

\mathbf A
=
\begin{bmatrix}
\alpha & \gamma\\
0 & \alpha
\end{bmatrix}
=
\alpha \mathbf I+\gamma \mathbf N,
\qquad
\mathbf N=
\begin{bmatrix}
0&1\\
0&0
\end{bmatrix},
\qquad
\mathbf N^2=\mathbf 0.

$$

其中：

- $\alpha\in\mathbb R$：重复特征值的实部；
- $\gamma\in\mathbb R$：非正规耦合强度；
- $\gamma=0$ 时退化为对角系统；
- $\gamma\neq 0$ 时矩阵不可正交对角化，且当只有一个特征向量时具有 Jordan 结构。

为保证稳定但仍能观察瞬态放大，建议默认：

$$

\alpha<0,\qquad \gamma>0.

$$

#### 离散时间采样

采样步长记为：

$$

\tau>0.

$$

离散流映射为：

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m)
=
\mathbf K_\tau \mathbf x_m,
\qquad
\mathbf K_\tau = \exp(\tau \mathbf A).

$$

对于二维 Jordan 块有解析式：

$$

\mathbf K_\tau
=
e^{\alpha \tau}
\begin{bmatrix}
1 & \gamma \tau\\
0 & 1
\end{bmatrix}.

$$

若轨线长度为 $M+1$，则第 $q$ 条轨线写为：

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x^{(q)}_1 & \mathbf x^{(q)}_2 & \cdots & \mathbf x^{(q)}_{M+1}
\end{bmatrix}
\in\mathbb R^{2\times(M+1)}.

$$

默认全状态观测下：

$$

\mathbf Z^{(q)}=\mathbf X^{(q)}
\in\mathbb R^{2\times(M+1)}.

$$

这符合项目规范中按列存储状态矩阵与观测矩阵的约定。fileciteturn3file0

---

### 3. Core formulas / numerical procedures

#### 连续时间解

由于 $\mathbf A=\alpha \mathbf I+\gamma \mathbf N$，且 $\mathbf N^2=0$，有：

$$

e^{t\mathbf A}
=
e^{\alpha t}e^{\gamma t\mathbf N}
=
e^{\alpha t}
\left(
\mathbf I+\gamma t\mathbf N
\right).

$$

因此：

$$

\mathbf x(t)
=
e^{\alpha t}
\begin{bmatrix}
1&\gamma t\\
0&1
\end{bmatrix}
\mathbf x_0.

$$

如果

$$

\mathbf x_0=
\begin{bmatrix}
x_{1,0}\\
x_{2,0}
\end{bmatrix},

$$

则

$$

x_2(t)=e^{\alpha t}x_{2,0},

$$

$$

x_1(t)=e^{\alpha t}\left(x_{1,0}+\gamma t x_{2,0}\right).

$$

这个解析式是本数据集最重要的数学基准。

它说明：即使 $\alpha<0$，系统最终衰减，但 $x_1(t)$ 中存在多项式因子 $t e^{\alpha t}$。因此系统会出现稳定谱下的瞬态非正规放大。

#### 离散时间解

令

$$

\lambda_\tau=e^{\alpha\tau},
\qquad
\eta_\tau=\gamma\tau e^{\alpha\tau}.

$$

则

$$

\mathbf K_\tau
=
\begin{bmatrix}
\lambda_\tau & \eta_\tau\\
0 & \lambda_\tau
\end{bmatrix}.

$$

并且

$$

\mathbf x_m
=
\mathbf K_\tau^{m-1}\mathbf x_1.

$$

由于二维 Jordan 块满足：

$$

\mathbf K_\tau^k
=
\lambda_\tau^k
\begin{bmatrix}
1 & k\gamma\tau\\
0 & 1
\end{bmatrix},

$$

所以多步预测应满足：

$$

x_{2,m+k}
=
\lambda_\tau^k x_{2,m},

$$

$$

x_{1,m+k}
=
\lambda_\tau^k
\left(
x_{1,m}+k\gamma\tau x_{2,m}
\right).

$$

这组公式可以作为之后 smoke test 和 regression test 的解析对照。

#### Koopman / 谱解释

对状态观测 $\mathbf z=\mathbf x$，线性 observable 子空间在该系统下闭合。有限维 Koopman 表示等价于：

$$

\mathbf z_{m+1}
=
\mathbf K_\tau \mathbf z_m.

$$

但与对角线性系统不同的是，$\mathbf K_\tau$ 不具有完整的特征向量基。它的谱只有重复特征值：

$$

\sigma(\mathbf K_\tau)=\{\lambda_\tau,\lambda_\tau\},

$$

但有非平凡 nilpotent 部分：

$$

\mathbf K_\tau
=
\lambda_\tau \mathbf I+\eta_\tau \mathbf N.

$$

因此，本系统不是为了测试“能不能找到两个不同特征值”，而是测试算法能否区分：

$$

\text{重复特征值}
\quad \neq \quad
\text{两个独立对角模态}.

$$

这正是 Jordan / 上三角结构化谱学习的核心单元测试。

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

第一步，固定系统参数：

$$

\boldsymbol\mu=(\alpha,\gamma,\tau,M,R),

$$

其中 $R$ 是轨线条数，$M+1$ 是每条轨线的快照数。

第二步，采样初值：

$$

\mathbf x_0^{(q)}
\sim \mathcal D_{x_0},
\qquad q=1,\dots,R.

$$

初值采样要覆盖两个方向：

$$

x_{1,0}\neq 0,
\qquad
x_{2,0}\neq 0.

$$

特别是 $x_{2,0}$ 不能总为零，否则非正规耦合项 $\gamma t x_{2,0}$ 不会被激活。

第三步，生成解析轨线：

$$

\mathbf x_m^{(q)}
=
\exp(t_m\mathbf A)\mathbf x_0^{(q)},
\qquad
t_m=(m-1)\tau.

$$

或者等价地使用离散递推：

$$

\mathbf x_{m+1}^{(q)}
=
\mathbf K_\tau \mathbf x_m^{(q)}.

$$

因为本系统是内部单元测试，推荐优先以解析解作为主标准，数值积分只作为可选交叉检查。

第四步，施加观测链。默认版本：

$$

\mathbf z_m^{(q)}=\mathbf x_m^{(q)}.

$$

后续可扩展为部分观测或线性混合观测，但本次第三个内部单元测试的基础版本应保持简单。

第五步，构造单步样本和 rollout 窗口：

$$

(\mathbf z_m,\mathbf z_{m+1}),

$$

$$

(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}).

$$

项目规范要求先按整条轨线切分，再在各自集合内部生成窗口，不能先把窗口随机打散，否则会造成训练和测试泄漏。fileciteturn3file1

---

### 5. Key assumptions

本数学说明默认以下假设。

1. 系统是自治连续时间线性 ODE：

$$

\dot{\mathbf x}=\mathbf A\mathbf x.

$$

2. 状态维度先取：

$$

d_x=2.

$$

3. 默认观测为全状态无噪声观测：

$$

d_z=d_x=2,
\qquad
\mathbf z=\mathbf x.

$$

4. 默认参数满足：

$$

\alpha<0,
\qquad
\gamma>0.

$$

这样系统渐近稳定，但仍可能存在瞬态放大。

5. 初值分布必须激活 Jordan 链方向，不能只沿唯一特征向量方向采样。

对于矩阵

$$

\mathbf A=
\begin{bmatrix}
\alpha&\gamma\\
0&\alpha
\end{bmatrix},

$$

唯一特征向量方向为：

$$

\operatorname{span}
\left\{
\begin{bmatrix}
1\\0
\end{bmatrix}
\right\}.

$$

若所有初值都落在该方向，则系统退化为普通一维指数衰减，无法测试非正规耦合。

6. 轨线时间窗不能过短。因为非正规效应由

$$

t e^{\alpha t}

$$

控制，如果时间窗太短，只能看到近似线性变化；如果时间窗太长，信号会完全衰减。建议时间窗覆盖瞬态峰值附近。

对于项 $t e^{\alpha t}$，当 $\alpha<0$ 时，其峰值大约出现在：

$$

t_\star\approx -\frac{1}{\alpha}.

$$

因此最终采样区间应覆盖 $t_\star$ 前后。

---

### 6. Numerical risks

#### 1. 误把 Jordan 系统当成可对角化系统

虽然 $\mathbf A$ 的特征值重复，但它通常只有一个线性独立特征向量。若后续算法或诊断只检查 eigenvalues，而不检查 Jordan / Schur / rank 结构，就可能误判系统已经被正确恢复。

需要检查：

$$

\operatorname{rank}(\mathbf A-\alpha\mathbf I)=1,

$$

$$

\dim\ker(\mathbf A-\alpha\mathbf I)=1.

$$

#### 2. 非正规瞬态放大导致尺度变化大

即使 $\alpha<0$，也可能存在：

$$

\|\mathbf x(t)\|_2>\|\mathbf x(0)\|_2

$$

的短时增长。若直接做全局归一化，可能压缩后期衰减段；若不归一化，早期瞬态峰值可能主导误差。

#### 3. $\gamma\tau$ 太小导致系统近似对角

离散矩阵为：

$$

\mathbf K_\tau
=
e^{\alpha\tau}
\begin{bmatrix}
1&\gamma\tau\\
0&1
\end{bmatrix}.

$$

如果 $\gamma\tau$ 太小，非正规项难以被数值识别；如果太大，瞬态放大可能过强，导致数据尺度不稳。

#### 4. 长时间衰减导致接近零信号

当 $t\gg -1/\alpha$ 时，

$$

e^{\alpha t}\to 0.

$$

此时所有轨线接近零，窗口样本可能缺乏辨识信息，并导致相对误差或归一化误差不稳定。

#### 5. 离散特征值重复导致谱诊断敏感

$$

\lambda_\tau=e^{\alpha\tau}

$$

是重复特征值。任何小噪声、数值误差或回归误差都可能把重复特征值扰动成两个相近但不同的特征值。后续诊断应区分：

$$

\text{真实 Jordan 块}

$$

和

$$

\text{数值扰动下的近重复特征值}.

$$

#### 6. 初值采样退化

如果 $x_{2,0}$ 太小，非正规项

$$

\gamma t x_{2,0}

$$

几乎不可见。需要在数据检查中显式确认 $x_2$ 方向被充分激活。

---

### 7. Preliminary package direction

本阶段不进入代码计划，只给出高层包方向。

1. **LinearAlgebra**  
   用于矩阵指数、特征值、Schur 分解、秩、范数、条件数等基础线性代数检查。正式实现前应确认矩阵指数、Schur 分解和秩判定的具体数值行为。

2. **DifferentialEquations.jl / OrdinaryDiffEq.jl**  
   对这个系统不是必须，因为解析解已经足够。但可以作为数值积分交叉验证工具，检查通用 ODE 生成器接口是否能处理线性系统。

3. **Random**  
   用于可复现初值采样。需要固定 seed policy，符合数据集工程中“配置控制参数与随机性”的原则。

4. **JLD2 / HDF5 / Arrow / JSON3 等数据与配置相关包**  
   这些属于后续工程计划阶段再定。当前数学说明只要求明确：系统参数、观测参数、split 参数和窗口参数应由配置对象控制，而不是写死在实验脚本中。项目规范也要求 `SystemSpec`、`ObservationSpec`、`SplitSpec`、`WindowSpec` 等配置对象独立存在。fileciteturn3file0

---

### 8. Wait for confirmation

本次 Jordan / 非正规线性系统的核心数学定位是：

$$

\boxed{
\dot{\mathbf x}
=
\begin{bmatrix}
\alpha&\gamma\\
0&\alpha
\end{bmatrix}
\mathbf x,
\qquad
\alpha<0,\ \gamma>0,
}

$$

它用于测试稳定重复谱下的 Jordan 链、非正规瞬态放大、不可对角化结构，以及后续 Koopman / HSKL 模型是否能区分“重复对角模态”和“真实 Jordan 块”。

请你确认或修改这个数学设定。确认后，我再进入 Step 2，按照 **ODEs 测试数据集代码工程指南** 给出详细代码工程计划书，不写代码。