## Step 1：非线性摆数据集数学说明书

### 1. Task understanding

本次任务是在 `ODEs_dataset` 中新增一个 **非线性摆 nonlinear pendulum** 数据集。该系统应与 Lusch–Kutz–Brunton 2018 中的 continuous-spectrum pendulum 算例对齐：采用无阻尼、无外力、未线性化的 Hamiltonian pendulum，而不是受迫摆、阻尼摆或小角度线性摆。用户贴出的参数说明中给出的核心系统是

$$

\ddot{x}=-\sin x,
\qquad
\Longleftrightarrow
\begin{cases}
\dot{x}_1=x_2,\\
\dot{x}_2=-\sin(x_1).
\end{cases}

$$

该算例的意义不是“又一个二维周期系统”，而是为 Koopman / DeepKoopman / variable-$\mathbf K$ 方法提供一个干净的 **连续频率谱** 测试对象：不同能量层上的摆动周期不同，能量越接近 separatrix，周期越长、频率越低。你贴出的材料也明确建议采用 $t=0,0.02,\ldots,1$、$\tau=0.02$、$T=51$，并使用能量约束 $H(\mathbf x_0)<0.99$ 来避开 separatrix。fileciteturn2file0

本数据集任务的输出应是标准 ODE benchmark 数据对象：

$$

\{\mathbf x_m^{(q)}\}_{m=0}^{T-1},\qquad q=1,\dots,R,

$$

以及经过观测链后的

$$

\{\mathbf z_m^{(q)}\}_{m=0}^{T-1}.

$$

第一版建议采用全状态观测、无噪声、固定参数，因此

$$

\mathbf z_m=\mathbf x_m.

$$

---

### 2. Mathematical objects and dimensions

状态变量定义为

$$

\mathbf x
=
\begin{bmatrix}
x_1\\
x_2
\end{bmatrix}
=
\begin{bmatrix}
\theta\\
\dot\theta
\end{bmatrix}
\in \mathbb R^2.

$$

其中：

$$

x_1=\theta

$$

是摆角，

$$

x_2=\dot\theta

$$

是角速度。

连续时间动力系统为

$$

\dot{\mathbf x}
=
\mathbf f(\mathbf x)
=
\begin{bmatrix}
x_2\\
-\sin(x_1)
\end{bmatrix}.

$$

状态维数为

$$

d_x=2.

$$

第一版全状态观测下，

$$

\mathbf z=\mathbf x,
\qquad
d_z=2.

$$

采样步长为

$$

\tau=\Delta t=0.02.

$$

Lusch 对齐版本时间窗为

$$

t=0,0.02,\ldots,1,

$$

因此每条轨线包含

$$

T=51

$$

个采样点。如果记离散时间索引为 $m=0,\dots,T-1$，则

$$

t_m=m\tau,
\qquad
m=0,\dots,50.

$$

离散流映射写作

$$

\mathbf x_{m+1}
=
\mathbf F^\tau(\mathbf x_m).

$$

单条轨线矩阵可写为

$$

\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x^{(q)}_0 &
\mathbf x^{(q)}_1 &
\cdots &
\mathbf x^{(q)}_{T-1}
\end{bmatrix}
\in \mathbb R^{2\times T}.

$$

若共有 $R$ 条轨线，则整个原始状态数据可以理解为

$$

\mathcal X_{\mathrm{data}}
=
\{\mathbf X^{(q)}\}_{q=1}^R,
\qquad
\mathbf X^{(q)}\in\mathbb R^{2\times 51}.

$$

---

### 3. Core formulas / numerical procedures

#### 3.1 Hamiltonian energy

非线性摆的 Hamiltonian 可写为

$$

H(\mathbf x)
=
\frac12 x_2^2-\cos(x_1).

$$

其时间导数为

$$

\frac{dH}{dt}
=
\frac{\partial H}{\partial x_1}\dot x_1
+
\frac{\partial H}{\partial x_2}\dot x_2
=
\sin(x_1)x_2+x_2[-\sin(x_1)]
=
0.

$$

因此在连续精确动力学中，

$$

H(\mathbf x(t))=H(\mathbf x(0)).

$$

能量最低点位于

$$

(x_1,x_2)=(0,0),
\qquad
H_{\min}=-1.

$$

separatrix 能量为

$$

H_{\mathrm{sep}}=1.

$$

用户提供的 Lusch 对齐设置为

$$

x_1(0)\in[-3.1,3.1],
\qquad
x_2(0)\in[-2,2],
\qquad
H(\mathbf x_0)<0.99.

$$

因此初值区域定义为

$$

\mathcal X_{\mathrm{pend}}
=
\left\{
\mathbf x\in\mathbb R^2:
x_1\in[-3.1,3.1],\
x_2\in[-2,2],\
\frac12 x_2^2-\cos(x_1)<0.99
\right\}.

$$

这个区域接近 separatrix 但不跨越 separatrix，因此只包含 libration 摆动轨道，不包含 rotation 翻转轨道。关键是不要只取小角度区域；否则

$$

\sin x_1\approx x_1

$$

会让系统退化成近似线性振子，失去连续频率漂移这一测试价值。fileciteturn2file0

#### 3.2 初值采样

推荐数学采样规则为 rejection sampling：

$$

x_1^{\mathrm{raw}}\sim \mathrm{Unif}[-3.1,3.1],
\qquad
x_2^{\mathrm{raw}}\sim \mathrm{Unif}[-2,2],

$$

保留满足

$$

H(x_1^{\mathrm{raw}},x_2^{\mathrm{raw}})<0.99

$$

的样本，作为正式初值

$$

\mathbf x_0^{(q)}.

$$

这样生成的轨线族覆盖多个 Hamiltonian level sets：

$$

H(\mathbf x_0^{(q)})=h_q,
\qquad
h_q\in[-1,0.99).

$$

#### 3.3 离散轨线生成

对每个初值 $\mathbf x_0^{(q)}$，积分

$$

\dot{\mathbf x}=\mathbf f(\mathbf x)

$$

并在

$$

t_m=m\tau,
\qquad
m=0,\dots,50

$$

处保存快照：

$$

\mathbf x_m^{(q)}
=
\mathbf x^{(q)}(t_m).

$$

数值上应检查能量漂移：

$$

\Delta H_m^{(q)}
=
H(\mathbf x_m^{(q)})-H(\mathbf x_0^{(q)}),

$$

以及最大能量漂移：

$$

\Delta H_{\max}^{(q)}
=
\max_{0\le m<T}
\left|
H(\mathbf x_m^{(q)})-H(\mathbf x_0^{(q)})
\right|.

$$

这是本系统最重要的数据质量诊断之一。

#### 3.4 摆动周期与频率

对能量层

$$

H(\mathbf x)=h,
\qquad -1<h<1,

$$

轨线是封闭摆动轨道。随着

$$

h\to 1^{-},

$$

轨线靠近 separatrix，周期趋于增大，频率趋于降低。Lusch continuous-spectrum pendulum 的核心正是利用这一点：不同能量层对应连续变化的频率，而不是单一固定频率。用户贴出的材料也指出，原文使用 $\|\mathbf y\|_2^2$ 作为辅助网络输入来参数化频率，并期望 $\omega$ 随能量增大而下降。fileciteturn2file0

在数据集层面，不需要实现辅助网络，但需要保留足够宽的能量分布，使下游学习器可以检验：

$$

\omega=\omega(H)

$$

或

$$

\omega=\omega(\rho)

$$

这类能量依赖频率结构。

---

### 4. Algorithmic logic

数学层面的数据生成逻辑如下。

第一，固定无量纲非线性摆系统：

$$

\dot x_1=x_2,
\qquad
\dot x_2=-\sin(x_1).

$$

第二，定义 Hamiltonian：

$$

H(\mathbf x)=\frac12x_2^2-\cos(x_1).

$$

第三，从矩形区域

$$

[-3.1,3.1]\times[-2,2]

$$

中采样候选初值，并只保留

$$

H(\mathbf x_0)<0.99

$$

的样本。

第四，对每个合法初值积分到

$$

t=1

$$

并以

$$

\tau=0.02

$$

采样，得到长度

$$

T=51

$$

的轨线。

第五，第一版观测链取恒等映射：

$$

U=\mathcal I,\qquad S=\mathcal I,\qquad Z=\mathcal I,

$$

因此

$$

\mathbf z_m=\mathbf x_m.

$$

第六，数据集应提供 one-step、rollout、statistics 等下游任务所需的基础轨线对象，但本次数学说明阶段不进入窗口文件或脚本组织。

第七，诊断数据质量：

$$

\Delta H_{\max},
\qquad
\max_m |x_{1,m}|,
\qquad
\max_m |x_{2,m}|,
\qquad
\min_q H(\mathbf x_0^{(q)}),
\qquad
\max_q H(\mathbf x_0^{(q)}).

$$

第八，检查初值能量分布是否覆盖低能、中能、高能区域。如果高能区域样本过少，下游将难以检验连续频率漂移；如果太靠近 separatrix，数值积分和周期估计会变得更敏感。

---

### 5. Key assumptions

1. **无阻尼、无外力、无参数泛化**

   第一版采用固定无量纲系统：

   $$

   \ddot x=-\sin x.
   
$$

   不加入阻尼项、外力项、长度参数、重力参数或质量参数。

2. **全状态观测**

   第一版采用：

   $$

   \mathbf z_m=\mathbf x_m=
   \begin{bmatrix}
   x_{1,m}\\
   x_{2,m}
   \end{bmatrix}.
   
$$

3. **无噪声**

   第一版不加入观测噪声和过程噪声。

4. **只保留 libration 区域**

   初值满足：

   $$

   H(\mathbf x_0)<0.99<1.
   
$$

   因此不包含完整 rotation 轨道。

5. **角变量暂不做 modulo wrapping**

   由于初值被限制在 separatrix 以下，理论上角度在有限摆动区间内往返，不需要把 $x_1$ 映射到 $(-\pi,\pi]$。但数值诊断仍应检查是否出现异常越界。

6. **时间窗与 Lusch 对齐**

   严格对齐版本采用：

   $$

   t\in[0,1],
   \qquad
   \tau=0.02,
   \qquad
   T=51.
   
$$

   后续可以增加 longer rollout 或统计窗口版本，但这属于下一步任务计划。

7. **数据集只定义动力学与数据协议**

   Lusch 中的 autoencoder、latent coordinate、auxiliary network、variable-$\mathbf K$ 不是本数据集生成器的一部分。它们应属于下游 Koopman Learning 工程。数据集层面只需要保证轨线覆盖连续频率结构。

---

### 6. Numerical risks

1. **separatrix 附近积分敏感**

   当

   $$

   H(\mathbf x_0)\to 1^{-}
   
$$

   时，轨线靠近鞍点，速度在转折附近变慢，周期快速增大。数值误差可能导致能量轻微越过 separatrix，从 libration 误判成 rotation。因此需要检查：

   $$

   \max_m H(\mathbf x_m)<1
   
$$

   或至少记录是否发生越界。

2. **能量漂移**

   普通非辛积分器在 Hamiltonian 系统上可能产生小的能量漂移。虽然 $t\le 1$ 很短，但仍应记录：

   $$

   \Delta H_{\max}.
   
$$

   如果后续生成长轨线，能量漂移会更重要。

3. **高能样本比例不足**

   由于 rejection sampling 和能量约束，靠近 separatrix 的区域可接受体积可能较小。如果 $H$ 的分布过度集中在低能量区间，则数据会接近线性振子，不能有效测试连续频率漂移。

4. **小角度退化**

   如果初值集中在

   $$

   |x_1|\ll 1,\qquad |x_2|\ll 1,
   
$$

   则

   $$

   \sin x_1\approx x_1
   
$$

   系统退化为

   $$

   \ddot x\approx -x,
   
$$

   此时 fixed-$\mathbf K$ 方法可能表现过好，掩盖 variable-$\mathbf K$ 的必要性。

5. **角度尺度与归一化风险**

   如果后续对 $\mathbf z$ 做标准化，需要注意 $x_1$ 与 $x_2$ 的物理含义不同。标准化不应破坏能量诊断；能量应始终在物理坐标 $\mathbf x$ 上计算。

6. **轨线长度较短**

   Lusch 对齐窗口 $t\in[0,1]$ 较短，适合训练短期预测和对齐原始设置，但未必足够估计完整周期，尤其对高能轨道。因此第一版可以作为 Lusch-aligned 数据，后续可能需要 longer trajectory 版本用于周期、相图和统计诊断。

7. **维度与存储约定**

   每条轨线应稳定采用

   $$

   \mathbf X^{(q)}\in\mathbb R^{2\times 51}
   
$$

   的列快照约定。如果实现中误用为 $51\times2$，后续窗口构造和学习器输入会出现维度错位。

---

### 7. Preliminary package direction

这里只给出高层方向，不涉及具体 API。

1. **DifferentialEquations.jl**

   适合用于 ODE 数值积分。正式实现前需要查文档，确认求解器选择、保存时刻、误差容限、随机初值批量生成等工作流。

2. **LinearAlgebra / Statistics**

   用于能量、均值、方差、误差和矩阵维度检查。

3. **Random**

   用于可复现的初值采样和 rejection sampling。

4. **JLD2 / HDF5 / JSON3 / CSV**

   可能用于保存轨线、manifest、诊断表和配置元数据。具体格式应等到 Step 2 结合工程目录再决定。

5. **Plots.jl 或 Makie.jl**

   可用于相图、能量分布、轨线图和能量漂移诊断。正式实现前需要检查绘图保存流程。

---

### 8. Wait for confirmation

请确认或修改以下数学设定：

$$

\dot x_1=x_2,\qquad
\dot x_2=-\sin(x_1),

$$

$$

\tau=0.02,\qquad
t\in[0,1],\qquad
T=51,

$$

$$

x_1(0)\sim\mathrm{Unif}[-3.1,3.1],
\qquad
x_2(0)\sim\mathrm{Unif}[-2,2],

$$

并用

$$

H(\mathbf x_0)=\frac12x_2(0)^2-\cos(x_1(0))<0.99

$$

筛选初值。第一版采用全状态观测、无噪声、固定参数，并把该系统登记为摆系统家族中的 Lusch-aligned nonlinear pendulum。确认后我再进入 Step 2，按照 ODEs_dataset 工程指南给出详细任务计划书。