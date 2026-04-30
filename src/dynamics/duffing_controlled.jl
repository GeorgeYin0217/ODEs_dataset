## Controlled Duffing system parameters and dimension convention

struct ControlledDuffingSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    input_dim::Int
    delta::Float64
    alpha::Float64
    beta::Float64
    input_gain::Float64
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function controlled_duffing_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return ControlledDuffingSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Int(config["input_dim"]),
        Float64(params["delta"]),
        Float64(params["alpha"]),
        Float64(params["beta"]),
        Float64(params["input_gain"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Controlled Duffing validation

function validate_controlled_duffing_spec(spec::ControlledDuffingSpec; atol::Real = 1e-10)
    spec.system_id == "duffing_controlled_edmdc" ||
        throw(ArgumentError("system_id must be duffing_controlled_edmdc"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    spec.input_dim == 1 || throw(ArgumentError("input_dim must be 1"))
    all(isfinite, (spec.delta, spec.alpha, spec.beta, spec.input_gain)) ||
        throw(ArgumentError("controlled Duffing parameters must be finite"))
    spec.input_gain != 0.0 || throw(ArgumentError("input_gain must be nonzero"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    spec.solver_name == "fixed_step_rk4_zoh" ||
        throw(ArgumentError("controlled Duffing smoke expects solver_name=fixed_step_rk4_zoh"))
    return true
end

function validate_controlled_duffing_state(spec::ControlledDuffingSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

function validate_control_input_matrix(spec::ControlledDuffingSpec, U::AbstractMatrix{<:Real})
    size(U) == (spec.input_dim, spec.trajectory_length) ||
        throw(ArgumentError("input matrix must have size (input_dim, trajectory_length)"))
    all(isfinite, U) || throw(ArgumentError("input matrix contains NaN or Inf"))
    return true
end

## Continuous-time right hand side with zero-order-held input

function controlled_duffing_rhs_components(
    delta::Real,
    alpha::Real,
    beta::Real,
    input_gain::Real,
    q::Real,
    v::Real,
    u::Real,
)
    return v, -delta * v - alpha * q - beta * q^3 + input_gain * u
end

function controlled_duffing_vector_field(
    spec::ControlledDuffingSpec,
    x::AbstractVector{<:Real},
    u::Real,
)
    validate_controlled_duffing_state(spec, x)
    dq, dv = controlled_duffing_rhs_components(
        spec.delta,
        spec.alpha,
        spec.beta,
        spec.input_gain,
        x[1],
        x[2],
        u,
    )
    return [dq, dv]
end

## Fixed-step RK4 trajectory propagation under ZOH inputs

function controlled_duffing_times(spec::ControlledDuffingSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_controlled_duffing_step(
    delta::Real,
    alpha::Real,
    beta::Real,
    input_gain::Real,
    dt::Real,
    q::Real,
    v::Real,
    u::Real,
)
    k1_q, k1_v = controlled_duffing_rhs_components(delta, alpha, beta, input_gain, q, v, u)
    k2_q, k2_v = controlled_duffing_rhs_components(
        delta,
        alpha,
        beta,
        input_gain,
        q + 0.5 * dt * k1_q,
        v + 0.5 * dt * k1_v,
        u,
    )
    k3_q, k3_v = controlled_duffing_rhs_components(
        delta,
        alpha,
        beta,
        input_gain,
        q + 0.5 * dt * k2_q,
        v + 0.5 * dt * k2_v,
        u,
    )
    k4_q, k4_v = controlled_duffing_rhs_components(
        delta,
        alpha,
        beta,
        input_gain,
        q + dt * k3_q,
        v + dt * k3_v,
        u,
    )

    next_q = q + dt * (k1_q + 2 * k2_q + 2 * k3_q + k4_q) / 6
    next_v = v + dt * (k1_v + 2 * k2_v + 2 * k3_v + k4_v) / 6
    return next_q, next_v
end

function generate_controlled_duffing_trajectory(
    spec::ControlledDuffingSpec,
    x0::AbstractVector{<:Real},
    U::AbstractMatrix{<:Real},
)
    validate_controlled_duffing_spec(spec)
    validate_controlled_duffing_state(spec, x0)
    validate_control_input_matrix(spec, U)

    times = controlled_duffing_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1] = rk4_controlled_duffing_step(
            spec.delta,
            spec.alpha,
            spec.beta,
            spec.input_gain,
            spec.dt,
            X[1, m],
            X[2, m],
            U[1, m],
        )
    end

    return times, X
end

## Metadata for controlled Duffing outputs

function controlled_duffing_metadata(spec::ControlledDuffingSpec)
    validate_controlled_duffing_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "input_dim" => spec.input_dim,
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "input_gain" => spec.input_gain,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "input_convention" => "U[:, m] is held on [t_m, t_{m+1})",
        "vector_field" => "q_dot = v; v_dot = -delta*v - alpha*q - beta*q^3 + input_gain*u",
    )
end
