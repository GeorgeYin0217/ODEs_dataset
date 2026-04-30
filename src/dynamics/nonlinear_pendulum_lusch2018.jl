## System identity and parameter policy

struct NonlinearPendulumLusch2018Spec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    x1_min::Float64
    x1_max::Float64
    x2_min::Float64
    x2_max::Float64
    energy_threshold::Float64
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function nonlinear_pendulum_lusch2018_spec_from_config(config::AbstractDict)
    domain = config["initial_condition_domain"]
    bounds = domain["bounds"]
    tspan_values = Float64.(config["tspan"])
    return NonlinearPendulumLusch2018Spec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        Float64(bounds["x1"][1]),
        Float64(bounds["x1"][2]),
        Float64(bounds["x2"][1]),
        Float64(bounds["x2"][2]),
        Float64(domain["energy_threshold"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## State variables and dimensional conventions

function validate_nonlinear_pendulum_lusch2018_spec(
    spec::NonlinearPendulumLusch2018Spec;
    atol::Real = 1e-10,
)
    spec.system_id == "nonlinear_pendulum_lusch2018" ||
        throw(ArgumentError("system_id must be nonlinear_pendulum_lusch2018"))
    spec.family == "v1_plus" || throw(ArgumentError("family must be v1_plus"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 2 || throw(ArgumentError("trajectory_length must be at least 2 snapshots"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * (spec.trajectory_length - 1)) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent with snapshot count"))
    spec.x1_min < spec.x1_max || throw(ArgumentError("x1 bounds are invalid"))
    spec.x2_min < spec.x2_max || throw(ArgumentError("x2 bounds are invalid"))
    spec.energy_threshold < 1.0 ||
        throw(ArgumentError("energy_threshold must stay below the separatrix energy 1"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("pendulum smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_nonlinear_pendulum_state(
    spec::NonlinearPendulumLusch2018Spec,
    x::AbstractVector{<:Real},
)
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

pendulum_transition_count(spec::NonlinearPendulumLusch2018Spec) = spec.trajectory_length - 1

## Vector field for the Lusch-aligned nonlinear pendulum

function nonlinear_pendulum_rhs_components(x1::Real, x2::Real)
    return x2, -sin(x1)
end

function nonlinear_pendulum_vector_field(
    spec::NonlinearPendulumLusch2018Spec,
    x::AbstractVector{<:Real},
)
    validate_nonlinear_pendulum_state(spec, x)
    dx1, dx2 = nonlinear_pendulum_rhs_components(x[1], x[2])
    return [dx1, dx2]
end

## Hamiltonian energy function

nonlinear_pendulum_hamiltonian(x1::Real, x2::Real) = 0.5 * x2^2 - cos(x1)

function nonlinear_pendulum_hamiltonian(
    spec::NonlinearPendulumLusch2018Spec,
    x::AbstractVector{<:Real},
)
    validate_nonlinear_pendulum_state(spec, x)
    return nonlinear_pendulum_hamiltonian(x[1], x[2])
end

## Initial-condition admissibility test

function nonlinear_pendulum_initial_condition_is_admissible(
    spec::NonlinearPendulumLusch2018Spec,
    x::AbstractVector{<:Real},
)
    validate_nonlinear_pendulum_state(spec, x)
    in_box = spec.x1_min <= x[1] <= spec.x1_max && spec.x2_min <= x[2] <= spec.x2_max
    return in_box && nonlinear_pendulum_hamiltonian(spec, x) < spec.energy_threshold
end

## Time-grid and trajectory-length conventions

function nonlinear_pendulum_times(spec::NonlinearPendulumLusch2018Spec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length))
end

function rk4_nonlinear_pendulum_step(dt::Real, x1::Real, x2::Real)
    k1_x1, k1_x2 = nonlinear_pendulum_rhs_components(x1, x2)
    k2_x1, k2_x2 = nonlinear_pendulum_rhs_components(
        x1 + 0.5 * dt * k1_x1,
        x2 + 0.5 * dt * k1_x2,
    )
    k3_x1, k3_x2 = nonlinear_pendulum_rhs_components(
        x1 + 0.5 * dt * k2_x1,
        x2 + 0.5 * dt * k2_x2,
    )
    k4_x1, k4_x2 = nonlinear_pendulum_rhs_components(x1 + dt * k3_x1, x2 + dt * k3_x2)

    next_x1 = x1 + dt * (k1_x1 + 2 * k2_x1 + 2 * k3_x1 + k4_x1) / 6
    next_x2 = x2 + dt * (k1_x2 + 2 * k2_x2 + 2 * k3_x2 + k4_x2) / 6
    return next_x1, next_x2
end

function generate_nonlinear_pendulum_lusch2018_trajectory(
    spec::NonlinearPendulumLusch2018Spec,
    x0::AbstractVector{<:Real},
)
    validate_nonlinear_pendulum_lusch2018_spec(spec)
    nonlinear_pendulum_initial_condition_is_admissible(spec, x0) ||
        throw(ArgumentError("initial condition is outside the Lusch-aligned admissible domain"))

    times = nonlinear_pendulum_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:pendulum_transition_count(spec)
        X[1, m + 1], X[2, m + 1] = rk4_nonlinear_pendulum_step(
            spec.dt,
            X[1, m],
            X[2, m],
        )
    end

    return times, X
end

function nonlinear_pendulum_lusch2018_metadata(spec::NonlinearPendulumLusch2018Spec)
    validate_nonlinear_pendulum_lusch2018_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "transition_count" => pendulum_transition_count(spec),
        "initial_condition_bounds" => Dict(
            "x1" => [spec.x1_min, spec.x1_max],
            "x2" => [spec.x2_min, spec.x2_max],
        ),
        "energy_threshold" => spec.energy_threshold,
        "separatrix_energy" => 1.0,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "hamiltonian" => "H(x1,x2) = 0.5*x2^2 - cos(x1)",
        "vector_field" => "x1_dot = x2; x2_dot = -sin(x1)",
    )
end
