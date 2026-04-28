## Duffing system identity and parameter convention

struct DuffingUnforcedDoubleWellSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    delta::Float64
    alpha::Float64
    beta::Float64
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function duffing_unforced_double_well_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return DuffingUnforcedDoubleWellSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["delta"]),
        Float64(params["alpha"]),
        Float64(params["beta"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## State dimension and parameter validation

function validate_duffing_unforced_double_well_spec(
    spec::DuffingUnforcedDoubleWellSpec;
    atol::Real = 1e-10,
)
    spec.system_id == "duffing_unforced_double_well" ||
        throw(ArgumentError("system_id must be duffing_unforced_double_well"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    isfinite(spec.delta) || throw(ArgumentError("delta must be finite"))
    isfinite(spec.alpha) || throw(ArgumentError("alpha must be finite"))
    isfinite(spec.beta) || throw(ArgumentError("beta must be finite"))
    spec.delta > 0 || throw(ArgumentError("damped Duffing smoke requires delta > 0"))
    spec.alpha < 0 || throw(ArgumentError("double-well Duffing smoke requires alpha < 0"))
    spec.beta > 0 || throw(ArgumentError("double-well Duffing smoke requires beta > 0"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("Duffing smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_duffing_state(spec::DuffingUnforcedDoubleWellSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

## Duffing vector field for unforced damped double-well system

function duffing_rhs_components(delta::Real, alpha::Real, beta::Real, q::Real, v::Real)
    return v, -delta * v - alpha * q - beta * q^3
end

function duffing_vector_field(spec::DuffingUnforcedDoubleWellSpec, x::AbstractVector{<:Real})
    validate_duffing_state(spec, x)
    dq, dv = duffing_rhs_components(spec.delta, spec.alpha, spec.beta, x[1], x[2])
    return [dq, dv]
end

## Duffing potential energy and total energy

duffing_potential_energy(alpha::Real, beta::Real, q::Real) = 0.5 * alpha * q^2 + 0.25 * beta * q^4

function duffing_total_energy(alpha::Real, beta::Real, q::Real, v::Real)
    return 0.5 * v^2 + duffing_potential_energy(alpha, beta, q)
end

function duffing_total_energy(spec::DuffingUnforcedDoubleWellSpec, q::Real, v::Real)
    return duffing_total_energy(spec.alpha, spec.beta, q, v)
end

duffing_energy_derivative(delta::Real, v::Real) = -delta * v^2

function duffing_energy_derivative(spec::DuffingUnforcedDoubleWellSpec, v::Real)
    return duffing_energy_derivative(spec.delta, v)
end

## Equilibrium points for double-well parameter regime

function duffing_equilibrium_points(spec::DuffingUnforcedDoubleWellSpec)
    validate_duffing_unforced_double_well_spec(spec)
    well_center = sqrt(-spec.alpha / spec.beta)
    return [[-well_center, 0.0], [0.0, 0.0], [well_center, 0.0]]
end

## Local Jacobian and linearization diagnostics

function duffing_jacobian(spec::DuffingUnforcedDoubleWellSpec, x::AbstractVector{<:Real})
    validate_duffing_state(spec, x)
    q = x[1]
    return [
        0.0 1.0
        -spec.alpha-3.0*spec.beta*q^2 -spec.delta
    ]
end

## Fixed-step RK4 trajectory propagation

function duffing_times(spec::DuffingUnforcedDoubleWellSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_duffing_step(delta::Real, alpha::Real, beta::Real, dt::Real, q::Real, v::Real)
    k1_q, k1_v = duffing_rhs_components(delta, alpha, beta, q, v)
    k2_q, k2_v = duffing_rhs_components(
        delta,
        alpha,
        beta,
        q + 0.5 * dt * k1_q,
        v + 0.5 * dt * k1_v,
    )
    k3_q, k3_v = duffing_rhs_components(
        delta,
        alpha,
        beta,
        q + 0.5 * dt * k2_q,
        v + 0.5 * dt * k2_v,
    )
    k4_q, k4_v = duffing_rhs_components(delta, alpha, beta, q + dt * k3_q, v + dt * k3_v)

    next_q = q + dt * (k1_q + 2 * k2_q + 2 * k3_q + k4_q) / 6
    next_v = v + dt * (k1_v + 2 * k2_v + 2 * k3_v + k4_v) / 6
    return next_q, next_v
end

function generate_duffing_unforced_double_well_trajectory(
    spec::DuffingUnforcedDoubleWellSpec,
    x0::AbstractVector{<:Real},
)
    validate_duffing_unforced_double_well_spec(spec)
    validate_duffing_state(spec, x0)

    times = duffing_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1] = rk4_duffing_step(
            spec.delta,
            spec.alpha,
            spec.beta,
            spec.dt,
            X[1, m],
            X[2, m],
        )
    end

    return times, X
end

## Basic numerical sanity checks for Duffing states

function duffing_unforced_double_well_metadata(spec::DuffingUnforcedDoubleWellSpec)
    validate_duffing_unforced_double_well_spec(spec)
    equilibria = duffing_equilibrium_points(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "equilibrium_points" => equilibria,
        "potential_energy" => "V(q) = alpha*q^2/2 + beta*q^4/4",
        "total_energy" => "E(q,v) = v^2/2 + V(q)",
        "energy_derivative" => "dE/dt = -delta*v^2",
        "vector_field" => "q_dot = v; v_dot = -delta*v - alpha*q - beta*q^3",
    )
end
