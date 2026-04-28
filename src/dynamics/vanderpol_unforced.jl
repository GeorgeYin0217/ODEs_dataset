## Van der Pol system overview and identifiers

struct VanDerPolUnforcedSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    mu::Float64
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function vanderpol_unforced_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return VanDerPolUnforcedSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["mu"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

function vanderpol_unforced_spec_with_mu(spec::VanDerPolUnforcedSpec, mu::Real)
    return VanDerPolUnforcedSpec(
        spec.system_id,
        spec.family,
        spec.variant,
        spec.state_dim,
        Float64(mu),
        spec.dt,
        spec.tspan,
        spec.trajectory_length,
        spec.solver_name,
        spec.solver_abstol,
        spec.solver_reltol,
    )
end

## State variables and parameter validation

function validate_vanderpol_unforced_spec(spec::VanDerPolUnforcedSpec; atol::Real = 1e-10)
    spec.system_id == "vanderpol_unforced" ||
        throw(ArgumentError("system_id must be vanderpol_unforced"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    isfinite(spec.mu) || throw(ArgumentError("mu must be finite"))
    spec.mu > 0 || throw(ArgumentError("mu must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("first Van der Pol smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

## Unforced Van der Pol vector field

function vanderpol_rhs_components(mu::Real, x1::Real, x2::Real)
    return x2, mu * (1 - x1^2) * x2 - x1
end

function vanderpol_unforced_vector_field(spec::VanDerPolUnforcedSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    dx1, dx2 = vanderpol_rhs_components(spec.mu, x[1], x[2])
    return [dx1, dx2]
end

## Fixed-step RK4 trajectory propagation

function vanderpol_times(spec::VanDerPolUnforcedSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_vanderpol_step(mu::Real, dt::Real, x1::Real, x2::Real)
    k1_1, k1_2 = vanderpol_rhs_components(mu, x1, x2)
    k2_1, k2_2 = vanderpol_rhs_components(mu, x1 + 0.5 * dt * k1_1, x2 + 0.5 * dt * k1_2)
    k3_1, k3_2 = vanderpol_rhs_components(mu, x1 + 0.5 * dt * k2_1, x2 + 0.5 * dt * k2_2)
    k4_1, k4_2 = vanderpol_rhs_components(mu, x1 + dt * k3_1, x2 + dt * k3_2)

    next_x1 = x1 + dt * (k1_1 + 2 * k2_1 + 2 * k3_1 + k4_1) / 6
    next_x2 = x2 + dt * (k1_2 + 2 * k2_2 + 2 * k3_2 + k4_2) / 6
    return next_x1, next_x2
end

function generate_vanderpol_unforced_trajectory(
    spec::VanDerPolUnforcedSpec,
    x0::AbstractVector{<:Real},
)
    validate_vanderpol_unforced_spec(spec)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))

    times = vanderpol_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1] = rk4_vanderpol_step(spec.mu, spec.dt, X[1, m], X[2, m])
    end

    return times, X
end

## System metadata helpers

function vanderpol_unforced_metadata(spec::VanDerPolUnforcedSpec)
    validate_vanderpol_unforced_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "mu" => spec.mu,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "vector_field" => "x1_dot = x2; x2_dot = mu * (1 - x1^2) * x2 - x1",
    )
end
