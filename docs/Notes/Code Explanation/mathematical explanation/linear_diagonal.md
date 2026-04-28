下面给出“线性对角系统”的数学说明。它属于 `unit_internal` 内部单元测试层，和旋转–收缩、Jordan / 非正规线性系统同级，用来测试最基础的点谱恢复、稳定/不稳定模态分离，以及数据协议中的矩阵方向、采样步长和轨线切分是否正确。

# 1. 系统定位

系统名称建议：

```text
system_id = "linear_diagonal"
family    = "unit_internal"
```

本系统不是公开 benchmark 主系统，而是最小数学基线。它主要测试：

1. 实对角连续谱与离散谱是否能被正确生成；
2. 稳定模态和不稳定模态是否能同时出现在数据中；
3. 采样后的 one-step 传播是否严格符合解析离散流；
4. 下游 DMD / EDMD / Koopman 方法能否在全状态观测下恢复点谱；
5. 数据协议中的状态矩阵方向、split 和 window 是否没有隐藏错误。

项目数据协议要求动力系统和观测链解耦：

$$
\mathbf{x}\xmapsto{U}\mathbf{u}\xmapsto{S}\mathbf{s}\xmapsto{Z}\mathbf{z}.
$$

本系统只定义状态轨线 $\mathbf{x}_m$ 的生成；第一版观测链采用全状态恒等观测，因此 $\mathbf z_m=\mathbf x_m$。

# 2. 连续时间动力系统

状态为

$$
\mathbf{x}(t)\in\mathbb{R}^d.
$$

定义实对角矩阵

$$
\Lambda
=
\operatorname{diag}(\lambda_1,\dots,\lambda_d),
$$

系统为

$$
\dot{\mathbf{x}}
=
\Lambda\mathbf{x}.
$$

也就是每个坐标独立演化：

$$
\dot{x}_i=\lambda_i x_i,
\qquad i=1,\dots,d.
$$

第一版建议使用

$$
d=4,
\qquad
\lambda=(-1.0,-0.3,0.1,0.5).
$$

这样数据中同时包含：

1. 快衰减模态；
2. 慢衰减模态；
3. 慢增长模态；
4. 快增长模态。

# 3. 解析解

对每个坐标，

$$
x_i(t)=x_i(0)e^{\lambda_i t}.
$$

向量形式为

$$
\mathbf{x}(t)
=
e^{\Lambda t}\mathbf{x}_0
=
\operatorname{diag}\left(e^{\lambda_1t},\dots,e^{\lambda_dt}\right)\mathbf{x}_0.
$$

采样时刻定义为

$$
t_m=(m-1)\tau,
\qquad
m=1,\dots,M+1.
$$

因此

$$
x_i(t_m)
=
x_i(0)e^{\lambda_i(m-1)\tau}.
$$

项目约定每条轨线写成列快照矩阵：

$$
\mathbf X^{(q)}
=
\begin{bmatrix}
\mathbf x_1^{(q)} & \cdots & \mathbf x_{M+1}^{(q)}
\end{bmatrix}
\in
\mathbb R^{d\times(M+1)}.
$$

也就是说，状态维度在行，时间快照在列。

# 4. 离散传播

定义精确离散传播矩阵

$$
A_\tau
=
e^{\Lambda\tau}
=
\operatorname{diag}
\left(
e^{\lambda_1\tau},
\dots,
e^{\lambda_d\tau}
\right).
$$

则采样序列满足

$$
\mathbf{x}_{m+1}=A_\tau\mathbf{x}_m.
$$

本系统的真实离散谱为

$$
\alpha_i=e^{\lambda_i\tau},
\qquad i=1,\dots,d.
$$

因此，如果后续 EDMD / Koopman / HSKL 在全状态观测、无噪声、无归一化的条件下无法恢复这些谱点，应优先检查数据协议、矩阵方向、切分、字典或实现，而不是怀疑动力系统本身。

# 5. 建议采样尺度

为避免不稳定模态导致数值过快增长，第一版 smoke test 不应使用过长时间跨度。建议：

$$
\tau=0.05,
\qquad
M=200,
\qquad
T=M\tau=10.
$$

当最大增长率为 $\lambda_{\max}=0.5$ 时，最大增长因子约为

$$
e^{0.5T}=e^5,
$$

仍处于可控范围。

# 6. 初值采样

第一版采用盒采样：

$$
\mathbf{x}_0^{(q)}
\sim
\operatorname{Uniform}([-1,1]^d).
$$

为了避免某些模态初始系数过小、导致该谱方向几乎不可见，建议加入过滤条件：

$$
\min_i |x_{0,i}^{(q)}|
\ge
\epsilon_{\mathrm{ic}}.
$$

例如：

$$
\epsilon_{\mathrm{ic}}=0.1.
$$

这样每个模态在数据中都有可观测能量。

# 7. 观测链

第一版只做全状态观测：

$$
U=\mathcal I,
\qquad
S=\mathcal I,
\qquad
Z=\mathcal I.
$$

因此

$$
\mathbf z_m=\mathbf x_m.
$$

对应观测轨线为

$$
\mathbf Z^{(q)}
=
\mathbf X^{(q)}
\in
\mathbb R^{d\times(M+1)}.
$$

本阶段不加噪声、不做 normalization、不做降维，目的是建立零复杂度观测链的工程基线。

# 8. Split 数学约束

先生成完整轨线集合

$$
\left\{\mathbf Z^{(q)}\right\}_{q=1}^R,
$$

再按轨线 ID 切分：

$$
\mathcal R_{\mathrm{train}},
\quad
\mathcal R_{\mathrm{val}},
\quad
\mathcal R_{\mathrm{test}}.
$$

必须满足

$$
\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{val}}
=
\mathcal R_{\mathrm{train}}
\cap
\mathcal R_{\mathrm{test}}
=
\mathcal R_{\mathrm{val}}
\cap
\mathcal R_{\mathrm{test}}
=
\varnothing.
$$

窗口只能在各自 split 内部生成，不能先切窗口再随机分配，否则同一条轨线的相邻片段可能同时进入训练集和测试集。

# 9. Window 定义

一步样本为

$$
(\mathbf z_m,\mathbf z_{m+1}),
\qquad
1\le m\le M.
$$

多步 rollout window 为

$$
(\mathbf z_s,\mathbf z_{s+1},\dots,\mathbf z_{s+L}),
\qquad
1\le s\le M+1-L.
$$

每个 window 的 `trajectory_id` 必须属于对应 split 的轨线集合。

# 10. Correctness Metrics

## 10.1 解析误差

$$
E_{\mathrm{exact}}
=
\max_{q,m}
\left\|
\mathbf x_m^{(q)}
-
\exp(\Lambda t_m)\mathbf x_0^{(q)}
\right\|_\infty.
$$

如果使用解析生成器，该误差应接近机器精度。

## 10.2 一步残差

$$
E_{\mathrm{step}}
=
\max_{q,m}
\left\|
\mathbf x_{m+1}^{(q)}
-
A_\tau\mathbf x_m^{(q)}
\right\|_\infty.
$$

解析生成器下，该残差也应接近机器精度。

## 10.3 维度检查

每条轨线必须满足

$$
\operatorname{size}(\mathbf X^{(q)})
=
(d,M+1),
$$

且全状态观测下

$$
\operatorname{size}(\mathbf Z^{(q)})
=
\operatorname{size}(\mathbf X^{(q)}).
$$

# 11. 谱诊断

本系统最直观的谱诊断是对每个坐标画

$$
\log |x_i(t)|.
$$

理想情况下，该曲线斜率应接近对应的 $\lambda_i$。稳定模态的斜率为负，不稳定模态的斜率为正。

同时，one-step DMD 在全状态、无噪声、足够激发所有坐标的情况下，应恢复离散特征值

$$
\alpha_i=e^{\lambda_i\tau}.
$$
