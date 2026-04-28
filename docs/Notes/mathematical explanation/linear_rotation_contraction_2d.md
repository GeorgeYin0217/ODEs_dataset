下面给出“旋转–收缩线性系统”的数学规划。它应放在 `unit_internal` 内部测试层，和已经完成的线性对角系统同级；项目系统对象文档也明确建议内部测试层保留“线性对角、旋转–收缩、Jordan / 非正规”三类系统，用来暴露谱结构与生成器问题。

# 1. 系统定位

系统名称建议：

```text
system_id = "linear_rotation_contraction_2d"
family    = "unit_internal"
```

它的目的不是作为公开 benchmark 主系统，而是测试：

1. 实数二维状态中的复共轭谱；
2. 收缩率是否正确；
3. 旋转角速度是否正确；
4. 离散采样后相位是否保持；
5. 下游 Koopman / DMD / EDMD 是否能恢复一对复共轭特征值。

数据集工程文档要求动力系统与观测链解耦，并统一把算法输入写成  
$$

\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z}.

$$
因此本系统的数学定义只负责生成状态轨线 $\mathbf{x}_m$，观测版本另由 `ObservationSpec` 处理。

# 2. 连续时间动力系统

状态为

$$

\mathbf{x}(t)
=
\begin{bmatrix}
x_1(t)\\
x_2(t)
\end{bmatrix}
\in\mathbb{R}^2.

$$

定义参数

$$

\gamma>0,\qquad \omega\neq 0,

$$

其中：

- $\gamma$：收缩率；
- $\omega$：角速度。

系统写成

$$

\dot{\mathbf{x}}
=
\mathbf{A}\mathbf{x},

$$

其中

$$

\mathbf{A}
=
\begin{bmatrix}
-\gamma & -\omega\\
\omega & -\gamma
\end{bmatrix}.

$$

也就是

$$

\dot{x}_1=-\gamma x_1-\omega x_2,

$$

$$

\dot{x}_2=\omega x_1-\gamma x_2.

$$

这个系统是一个稳定焦点。只要 $\gamma>0$，所有非零初值都会绕原点旋转并指数衰减到零。

# 3. 解析解

令复变量

$$

w(t)=x_1(t)+i x_2(t).

$$

则系统等价于

$$

\dot{w}=(-\gamma+i\omega)w.

$$

因此

$$

w(t)=e^{(-\gamma+i\omega)t}w(0).

$$

在实数形式下，

$$

\mathbf{x}(t)
=
e^{-\gamma t}
\begin{bmatrix}
\cos(\omega t) & -\sin(\omega t)\\
\sin(\omega t) & \cos(\omega t)
\end{bmatrix}
\mathbf{x}_0.

$$

极坐标形式为

$$

r(t)=e^{-\gamma t}r_0,

$$

$$

\theta(t)=\theta_0+\omega t.

$$

所以它天然分离为：

```text
半径方向：指数收缩
角度方向：匀速旋转
```

# 4. 连续谱结构

连续时间生成矩阵 $\mathbf{A}$ 的特征值为

$$

\nu_\pm=-\gamma\pm i\omega.

$$

因此：

- 实部 $-\gamma$ 控制衰减；
- 虚部 $\pm\omega$ 控制旋转；
- 谱点严格位于左半平面。

对应的复 Koopman 坐标可以直接取

$$

\psi_+(\mathbf{x})=x_1+i x_2,

$$

$$

\psi_-(\mathbf{x})=x_1-i x_2.

$$

沿流演化有

$$

\psi_+(\mathbf{x}(t))
=
e^{(-\gamma+i\omega)t}\psi_+(\mathbf{x}_0),

$$

$$

\psi_-(\mathbf{x}(t))
=
e^{(-\gamma-i\omega)t}\psi_-(\mathbf{x}_0).

$$

这正好构成一对复共轭 Koopman 特征函数。

# 5. 离散时间系统

采样步长为

$$

\tau>0.

$$

离散快照满足

$$

\mathbf{x}_{m+1}
=
\mathbf{F}^{\tau}\mathbf{x}_m,

$$

其中

$$

\mathbf{F}^{\tau}
=
e^{\mathbf{A}\tau}
=
e^{-\gamma\tau}
\begin{bmatrix}
\cos(\omega\tau) & -\sin(\omega\tau)\\
\sin(\omega\tau) & \cos(\omega\tau)
\end{bmatrix}.

$$

记

$$

\rho=e^{-\gamma\tau},
\qquad
\vartheta=\omega\tau.

$$

则

$$

\mathbf{F}^{\tau}
=
\rho
\begin{bmatrix}
\cos\vartheta & -\sin\vartheta\\
\sin\vartheta & \cos\vartheta
\end{bmatrix}.

$$

离散 Koopman 特征值为

$$

\lambda_\pm
=
e^{(-\gamma\pm i\omega)\tau}
=
\rho e^{\pm i\vartheta}.

$$

它们满足

$$

|\lambda_\pm|=\rho<1,

$$

$$

\arg(\lambda_\pm)=\pm\vartheta.

$$

这个系统的核心检查量就是：

```text
模长是否等于 exp(-γτ)
相位是否等于 ±ωτ
```

# 6. 默认参数建议

为了和线性对角系统一样先保持简单，建议默认只做二维版本。

推荐默认值：

$$

\gamma=0.15,
\qquad
\omega=2\pi.

$$

这样旋转周期为

$$

T=\frac{2\pi}{\omega}=1.

$$

如果取

$$

\tau=0.01,

$$

则每个周期有 100 个采样点，相位分辨率足够清楚。

默认离散谱为

$$

\lambda_\pm
=
e^{(-0.15\pm i2\pi)0.01}.

$$

模长为

$$

\rho=e^{-0.0015}\approx 0.9985.

$$

相位步长为

$$

\vartheta=2\pi\cdot 0.01\approx 0.06283.

$$

也就是说每一步旋转约 $3.6^\circ$。

# 7. 初值区域

为了避免所有轨线都快速塌到原点，同时又不让数值过大，建议初值从圆环或方形区域采样。

最简单版本：

$$

x_1(0),x_2(0)\sim \mathrm{Uniform}([-2,2]).

$$

但需要排除过小初值，例如要求

$$

\|\mathbf{x}_0\|_2\geq r_{\min}.

$$

推荐

$$

r_{\min}=0.25.

$$

更干净的版本是直接从极坐标采样：

$$

r_0\sim \mathrm{Uniform}(0.5,2.0),

$$

$$

\theta_0\sim \mathrm{Uniform}(0,2\pi),

$$

然后

$$

\mathbf{x}_0
=
r_0
\begin{bmatrix}
\cos\theta_0\\
\sin\theta_0
\end{bmatrix}.

$$

这个更适合旋转系统，因为初值角度分布天然均匀。

# 8. 轨线长度建议

如果默认周期 $T=1$，建议每条轨线至少覆盖多个周期。

small 档：

$$

\tau=0.01,
\qquad
M=500,
\qquad
t_{\max}=5.

$$

也就是 5 个周期。

medium 档：

$$

\tau=0.01,
\qquad
M=2000,
\qquad
t_{\max}=20.

$$

也就是 20 个周期。

但由于系统会持续收缩，不能让 $t_{\max}$ 太大，否则后半段几乎全在原点附近，数值上不利于检验旋转相位。

以 $\gamma=0.15$ 为例，

$$

e^{-\gamma t_{\max}}
=
e^{-0.15\times 20}
=
e^{-3}
\approx 0.05.

$$

所以 $t_{\max}=20$ 已经足够长，不建议初版超过太多。

# 9. 观测版本

初版建议只实现最小必要观测：

## Observation-A：全状态无噪声

$$

\mathbf{z}_m=\mathbf{x}_m.

$$

这是 smoke test 和 regression test 的主版本。

## Observation-B：全状态低噪声

$$

\mathbf{z}_m=\mathbf{x}_m+\boldsymbol{\varepsilon}_m,

$$

其中

$$

\boldsymbol{\varepsilon}_m\sim\mathcal{N}(0,\sigma^2\mathbf{I}).

$$

推荐

$$

\sigma=10^{-3}
\quad\text{或}\quad
\sigma=10^{-2}.

$$

## Observation-C：单坐标观测，暂时可延后

$$

z_m=x_1(t_m).

$$

这个版本会把二维旋转系统变成一维振荡信号，适合以后测试 delay embedding，但不建议第一轮就做。

# 10. Split 设计

由于这是内部单元测试系统，初版只需要 `Split-I`：

```text
Split-I：初值泛化
```

也就是参数 $(\gamma,\omega)$ 固定，训练、验证、测试使用不同初值轨线。

轨线级切分必须优先于窗口切分；数据集工程文档明确要求先按整条轨线切分，再在各自集合内部生成窗口，禁止把同一条轨线的相邻窗口分散到 train/test。fileciteturn0file1

建议比例：

$$

70\%/15\%/15\%.

$$

后续可以再扩展 `Split-P`：

```text
训练：γ, ω 取若干固定值
测试：γ, ω 取未见组合
```

但这不是第一版必须项。

# 11. 窗口任务

至少支持两类窗口。

## 一步样本

$$

(\mathbf{z}_m,\mathbf{z}_{m+1}).

$$

用于检查：

$$

\mathbf{z}_{m+1}\approx \mathbf{F}^{\tau}\mathbf{z}_m.

$$

## 多步 rollout 窗口

$$

(\mathbf{z}_s,\mathbf{z}_{s+1},\dots,\mathbf{z}_{s+L}).

$$

用于检查：

$$

\mathbf{z}_{s+\ell}
\approx
(\mathbf{F}^{\tau})^\ell \mathbf{z}_s.

$$

建议初始 horizon：

$$

L\in\{10,50,100\}.

$$

其中 $L=100$ 对应一个完整周期。

# 12. 数值真值与 sanity check

这个系统应尽量不用数值积分误差污染测试。因为解析解非常简单，推荐生成器直接使用闭式离散推进：

$$

\mathbf{x}_{m+1}
=
\mathbf{F}^{\tau}\mathbf{x}_m.

$$

如果后续为了统一接口使用 ODE solver，也必须和解析解做对比：

$$

\max_m
\|\mathbf{x}_m^{\mathrm{solver}}-\mathbf{x}_m^{\mathrm{exact}}\|_2

$$

应接近 solver 容差量级。

生成数据后至少检查：

$$

\frac{\|\mathbf{x}_{m+1}\|_2}{\|\mathbf{x}_m\|_2}
\approx
e^{-\gamma\tau},

$$

以及

$$

\angle(\mathbf{x}_{m+1})-\angle(\mathbf{x}_m)
\approx
\omega\tau
\quad
\mathrm{mod}\ 2\pi.

$$

这两个检查比单纯看轨线图更关键。

# 13. 应输出的数学元信息

每个 manifest 至少记录：

```text
system_id
state_dim = 2
gamma
omega
dt = τ
trajectory_length = M
continuous_matrix_A
discrete_matrix_F
continuous_eigenvalues = -γ ± iω
discrete_eigenvalues = exp((-γ ± iω)τ)
contraction_factor = exp(-γτ)
rotation_angle_per_step = ωτ
initial_condition_policy
observation_id
noise_level
split_id
seed
```

这样后续 DMD / EDMD / Koopman 学习结果可以直接和真值谱对比。

# 14. 和线性对角系统的关系

已经完成的线性对角系统本质上测试的是：

$$

\lambda_1,\lambda_2\in\mathbb{R}.

$$

旋转–收缩系统测试的是：

$$

\lambda_\pm=\rho e^{\pm i\vartheta}\in\mathbb{C}.

$$

所以它补足的是“实数状态空间中的复共轭模态”。这对 Koopman 学习尤其重要，因为很多模型如果只看预测误差，可能能拟合短期轨线，但未必能正确恢复相位和复谱。

# 15. 最小数学定稿

第一版可以冻结为：

$$

\boxed{
\dot{\mathbf{x}}
=
\begin{bmatrix}
-\gamma & -\omega\\
\omega & -\gamma
\end{bmatrix}
\mathbf{x},
\qquad
\gamma=0.15,
\qquad
\omega=2\pi.
}

$$

离散推进为：

$$

\boxed{
\mathbf{x}_{m+1}
=
e^{-\gamma\tau}
\begin{bmatrix}
\cos(\omega\tau) & -\sin(\omega\tau)\\
\sin(\omega\tau) & \cos(\omega\tau)
\end{bmatrix}
\mathbf{x}_m.
}

$$

默认观测为：

$$

\boxed{
\mathbf{z}_m=\mathbf{x}_m.
}

$$

默认任务为：

```text
one_step_forecast
multi_step_rollout
spectrum_recovery_diagnostic
```

这个系统完成后，内部测试层就从“只会检查实对角谱”推进到了“能检查复共轭谱块”。下一步编码时，应先实现系统右端函数、解析离散推进矩阵、配置文件和 smoke test。