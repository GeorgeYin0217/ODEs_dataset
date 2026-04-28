## Lotka-Volterra system identity and parameter convention

struct LotkaVolterraSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    alpha::Float64
    beta::Float64
    gamma::Float64
    delta::Float64
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function lotka_volterra_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return LotkaVolterraSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["alpha"]),
        Float64(params["beta"]),
        Float64(params["gamma"]),
        Float64(params["delta"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter and positive-state validation

function validate_lotka_volterra_spec(spec::LotkaVolterraSpec; atol::Real = 1e-10)
    spec.system_id == "lotka_volterra" || throw(ArgumentError("system_id must be lotka_volterra"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    all(isfinite, (spec.alpha, spec.beta, spec.gamma, spec.delta)) ||
        throw(ArgumentError("Lotka-Volterra parameters must be finite"))
    spec.alpha > 0 || throw(ArgumentError("alpha must be positive"))
    spec.beta > 0 || throw(ArgumentError("beta must be positive"))
    spec.gamma > 0 || throw(ArgumentError("gamma must be positive"))
    spec.delta > 0 || throw(ArgumentError("delta must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("Lotka-Volterra smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_lotka_volterra_state(spec::LotkaVolterraSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    all(>(0), x) || throw(ArgumentError("Lotka-Volterra state must stay in the positive quadrant"))
    return true
end

## Vector field, equilibrium, Jacobian, and invariant

function lotka_volterra_rhs_components(
    alpha::Real,
    beta::Real,
    gamma::Real,
    delta::Real,
    x::Real,
    y::Real,
)
    return alpha * x - beta * x * y, delta * x * y - gamma * y
end

function lotka_volterra_vector_field(spec::LotkaVolterraSpec, x::AbstractVector{<:Real})
    validate_lotka_volterra_state(spec, x)
    dx, dy = lotka_volterra_rhs_components(spec.alpha, spec.beta, spec.gamma, spec.delta, x[1], x[2])
    return [dx, dy]
end

function lotka_volterra_positive_equilibrium(spec::LotkaVolterraSpec)
    validate_lotka_volterra_spec(spec)
    return [spec.gamma / spec.delta, spec.alpha / spec.beta]
end

function lotka_volterra_jacobian(spec::LotkaVolterraSpec, x::AbstractVector{<:Real})
    validate_lotka_volterra_state(spec, x)
    prey, predator = x
    return [
        spec.alpha-spec.beta*predator -spec.beta*prey
        spec.delta*predator spec.delta*prey-spec.gamma
    ]
end

function lotka_volterra_invariant(
    alpha::Real,
    beta::Real,
    gamma::Real,
    delta::Real,
    x::Real,
    y::Real,
)
    x > 0 || throw(ArgumentError("invariant requires x > 0"))
    y > 0 || throw(ArgumentError("invariant requires y > 0"))
    return delta * x - gamma * log(x) + beta * y - alpha * log(y)
end

function lotka_volterra_invariant(spec::LotkaVolterraSpec, x::Real, y::Real)
    return lotka_volterra_invariant(spec.alpha, spec.beta, spec.gamma, spec.delta, x, y)
end

lotka_volterra_local_frequency(spec::LotkaVolterraSpec) = sqrt(spec.alpha * spec.gamma)

## Fixed-step RK4 trajectory propagation

function lotka_volterra_times(spec::LotkaVolterraSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_lotka_volterra_step(
    alpha::Real,
    beta::Real,
    gamma::Real,
    delta::Real,
    dt::Real,
    x::Real,
    y::Real,
)
    k1_x, k1_y = lotka_volterra_rhs_components(alpha, beta, gamma, delta, x, y)
    k2_x, k2_y = lotka_volterra_rhs_components(
        alpha,
        beta,
        gamma,
        delta,
        x + 0.5 * dt * k1_x,
        y + 0.5 * dt * k1_y,
    )
    k3_x, k3_y = lotka_volterra_rhs_components(
        alpha,
        beta,
        gamma,
        delta,
        x + 0.5 * dt * k2_x,
        y + 0.5 * dt * k2_y,
    )
    k4_x, k4_y = lotka_volterra_rhs_components(alpha, beta, gamma, delta, x + dt * k3_x, y + dt * k3_y)

    next_x = x + dt * (k1_x + 2 * k2_x + 2 * k3_x + k4_x) / 6
    next_y = y + dt * (k1_y + 2 * k2_y + 2 * k3_y + k4_y) / 6
    return next_x, next_y
end

function generate_lotka_volterra_trajectory(spec::LotkaVolterraSpec, x0::AbstractVector{<:Real})
    validate_lotka_volterra_spec(spec)
    validate_lotka_volterra_state(spec, x0)

    times = lotka_volterra_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1] = rk4_lotka_volterra_step(
            spec.alpha,
            spec.beta,
            spec.gamma,
            spec.delta,
            spec.dt,
            X[1, m],
            X[2, m],
        )
    end

    return times, X
end

## System metadata helper

function lotka_volterra_metadata(spec::LotkaVolterraSpec)
    validate_lotka_volterra_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "gamma" => spec.gamma,
        "delta" => spec.delta,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "positive_equilibrium" => lotka_volterra_positive_equilibrium(spec),
        "local_frequency" => lotka_volterra_local_frequency(spec),
        "invariant" => "H(x,y) = delta*x - gamma*log(x) + beta*y - alpha*log(y)",
        "vector_field" => "x_dot = alpha*x - beta*x*y; y_dot = delta*x*y - gamma*y",
    )
end
