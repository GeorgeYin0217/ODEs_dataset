## Lorenz '63 system identity and default parameters

struct Lorenz63Spec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    sigma::Float64
    rho::Float64
    beta::Float64
    dt::Float64
    burn_in_time::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function lorenz63_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return Lorenz63Spec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["sigma"]),
        Float64(params["rho"]),
        Float64(params["beta"]),
        Float64(config["dt"]),
        Float64(config["burn_in_time"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter validation rules

function validate_lorenz63_spec(spec::Lorenz63Spec; atol::Real = 1e-10)
    spec.system_id == "lorenz63" || throw(ArgumentError("system_id must be lorenz63"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 3 || throw(ArgumentError("state_dim must be 3"))
    all(isfinite, (spec.sigma, spec.rho, spec.beta)) ||
        throw(ArgumentError("Lorenz63 parameters must be finite"))
    spec.sigma > 0 || throw(ArgumentError("sigma must be positive"))
    spec.rho > 0 || throw(ArgumentError("rho must be positive"))
    spec.beta > 0 || throw(ArgumentError("beta must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.burn_in_time >= 0 || throw(ArgumentError("burn_in_time must be nonnegative"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    abs(round(spec.burn_in_time / spec.dt) * spec.dt - spec.burn_in_time) <= atol ||
        throw(ArgumentError("burn_in_time must be an integer multiple of dt"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("Lorenz63 smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_lorenz63_state(spec::Lorenz63Spec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

## Lorenz '63 vector field

function lorenz63_rhs_components(
    sigma::Real,
    rho::Real,
    beta::Real,
    x::Real,
    y::Real,
    z::Real,
)
    return sigma * (y - x), x * (rho - z) - y, x * y - beta * z
end

function lorenz63_vector_field(spec::Lorenz63Spec, x::AbstractVector{<:Real})
    validate_lorenz63_state(spec, x)
    dx, dy, dz = lorenz63_rhs_components(spec.sigma, spec.rho, spec.beta, x[1], x[2], x[3])
    return [dx, dy, dz]
end

## Lorenz '63 Jacobian for diagnostics

function lorenz63_jacobian(spec::Lorenz63Spec, x::AbstractVector{<:Real})
    validate_lorenz63_state(spec, x)
    return [
        -spec.sigma spec.sigma 0.0
        spec.rho-x[3] -1.0 -x[1]
        x[2] x[1] -spec.beta
    ]
end

function lorenz63_divergence(spec::Lorenz63Spec)
    validate_lorenz63_spec(spec)
    return -spec.sigma - 1.0 - spec.beta
end

## Equilibrium points under standard parameters

function lorenz63_equilibria(spec::Lorenz63Spec)
    validate_lorenz63_spec(spec)
    equilibria = [[0.0, 0.0, 0.0]]
    if spec.rho > 1.0
        a = sqrt(spec.beta * (spec.rho - 1.0))
        push!(equilibria, [a, a, spec.rho - 1.0])
        push!(equilibria, [-a, -a, spec.rho - 1.0])
    end
    return equilibria
end

function lorenz63_equilibrium_residual(spec::Lorenz63Spec, x::AbstractVector{<:Real})
    dx, dy, dz = lorenz63_rhs_components(spec.sigma, spec.rho, spec.beta, x[1], x[2], x[3])
    return sqrt(dx^2 + dy^2 + dz^2)
end

## Fixed-step RK4 trajectory propagation

function lorenz63_times(spec::Lorenz63Spec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_lorenz63_step(
    sigma::Real,
    rho::Real,
    beta::Real,
    dt::Real,
    x::Real,
    y::Real,
    z::Real,
)
    k1x, k1y, k1z = lorenz63_rhs_components(sigma, rho, beta, x, y, z)
    k2x, k2y, k2z = lorenz63_rhs_components(
        sigma,
        rho,
        beta,
        x + 0.5 * dt * k1x,
        y + 0.5 * dt * k1y,
        z + 0.5 * dt * k1z,
    )
    k3x, k3y, k3z = lorenz63_rhs_components(
        sigma,
        rho,
        beta,
        x + 0.5 * dt * k2x,
        y + 0.5 * dt * k2y,
        z + 0.5 * dt * k2z,
    )
    k4x, k4y, k4z = lorenz63_rhs_components(
        sigma,
        rho,
        beta,
        x + dt * k3x,
        y + dt * k3y,
        z + dt * k3z,
    )

    next_x = x + dt * (k1x + 2 * k2x + 2 * k3x + k4x) / 6
    next_y = y + dt * (k1y + 2 * k2y + 2 * k3y + k4y) / 6
    next_z = z + dt * (k1z + 2 * k2z + 2 * k3z + k4z) / 6
    return next_x, next_y, next_z
end

function advance_lorenz63_state(spec::Lorenz63Spec, x0::AbstractVector{<:Real}, steps::Integer)
    validate_lorenz63_spec(spec)
    validate_lorenz63_state(spec, x0)
    steps >= 0 || throw(ArgumentError("steps must be nonnegative"))

    x = Float64(x0[1])
    y = Float64(x0[2])
    z = Float64(x0[3])
    @inbounds for _ in 1:steps
        x, y, z = rk4_lorenz63_step(spec.sigma, spec.rho, spec.beta, spec.dt, x, y, z)
    end
    return [x, y, z]
end

function generate_lorenz63_trajectory(spec::Lorenz63Spec, x0::AbstractVector{<:Real})
    validate_lorenz63_spec(spec)
    validate_lorenz63_state(spec, x0)

    times = lorenz63_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1], X[3, m + 1] = rk4_lorenz63_step(
            spec.sigma,
            spec.rho,
            spec.beta,
            spec.dt,
            X[1, m],
            X[2, m],
            X[3, m],
        )
    end

    return times, X
end

## System registration payload

function lorenz63_metadata(spec::Lorenz63Spec)
    validate_lorenz63_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "sigma" => spec.sigma,
        "rho" => spec.rho,
        "beta" => spec.beta,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "divergence" => lorenz63_divergence(spec),
        "equilibria" => lorenz63_equilibria(spec),
        "vector_field" => "x_dot = sigma*(y-x); y_dot = x*(rho-z)-y; z_dot = x*y-beta*z",
        "jacobian" => "[-sigma sigma 0; rho-z -1 -x; y x -beta]",
    )
end
