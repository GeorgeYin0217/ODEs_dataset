## Lorenz96 system metadata

struct Lorenz96Spec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    F::Float64
    dt::Float64
    burn_in_time::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function lorenz96_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return Lorenz96Spec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["F"]),
        Float64(config["dt"]),
        Float64(config["burn_in_time"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## State dimension and forcing parameter validation

function validate_lorenz96_spec(spec::Lorenz96Spec; atol::Real = 1e-10)
    spec.system_id == "lorenz96" || throw(ArgumentError("system_id must be lorenz96"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 40 || throw(ArgumentError("Lorenz96 smoke spec must use state_dim=40"))
    isfinite(spec.F) || throw(ArgumentError("forcing F must be finite"))
    spec.F > 0 || throw(ArgumentError("forcing F must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.burn_in_time >= 0 || throw(ArgumentError("burn_in_time must be nonnegative"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    abs(round(spec.burn_in_time / spec.dt) * spec.dt - spec.burn_in_time) <= atol ||
        throw(ArgumentError("burn_in_time must be an integer multiple of dt"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("Lorenz96 smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_lorenz96_state(spec::Lorenz96Spec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

## Cyclic index convention

lorenz96_cyclic_index(i::Integer, n::Integer) = mod1(i, n)

function lorenz96_boundary_terms(F::Real, x::AbstractVector{<:Real})
    n = length(x)
    return Dict(
        "i1" => (x[lorenz96_cyclic_index(2, n)] - x[lorenz96_cyclic_index(-1, n)]) *
            x[lorenz96_cyclic_index(0, n)] - x[1] + F,
        "i2" => (x[lorenz96_cyclic_index(3, n)] - x[lorenz96_cyclic_index(0, n)]) *
            x[lorenz96_cyclic_index(1, n)] - x[2] + F,
        "iK" => (x[lorenz96_cyclic_index(n + 1, n)] - x[lorenz96_cyclic_index(n - 2, n)]) *
            x[lorenz96_cyclic_index(n - 1, n)] - x[n] + F,
    )
end

## Lorenz96 right-hand side

function lorenz96_rhs!(dx::AbstractVector{<:Real}, F::Real, x::AbstractVector{<:Real})
    n = length(x)
    length(dx) == n || throw(ArgumentError("dx and x must have the same length"))
    @inbounds for i in 1:n
        im2 = lorenz96_cyclic_index(i - 2, n)
        im1 = lorenz96_cyclic_index(i - 1, n)
        ip1 = lorenz96_cyclic_index(i + 1, n)
        dx[i] = (x[ip1] - x[im2]) * x[im1] - x[i] + F
    end
    return dx
end

function lorenz96_vector_field(spec::Lorenz96Spec, x::AbstractVector{<:Real})
    validate_lorenz96_state(spec, x)
    dx = Vector{Float64}(undef, spec.state_dim)
    lorenz96_rhs!(dx, spec.F, x)
    return dx
end

## Equilibrium and reference-state helpers

function lorenz96_uniform_state(spec::Lorenz96Spec)
    validate_lorenz96_spec(spec)
    return fill(spec.F, spec.state_dim)
end

function lorenz96_uniform_residual(spec::Lorenz96Spec)
    return norm(lorenz96_vector_field(spec, lorenz96_uniform_state(spec)))
end

function lorenz96_divergence(spec::Lorenz96Spec)
    validate_lorenz96_spec(spec)
    return -Float64(spec.state_dim)
end

## Fixed-step RK4 propagation

function lorenz96_times(spec::Lorenz96Spec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_lorenz96_step(F::Real, dt::Real, x::AbstractVector{<:Real})
    n = length(x)
    x0 = Float64.(x)
    k1 = similar(x0)
    k2 = similar(x0)
    k3 = similar(x0)
    k4 = similar(x0)
    temp = similar(x0)

    lorenz96_rhs!(k1, F, x0)
    @. temp = x0 + 0.5 * dt * k1
    lorenz96_rhs!(k2, F, temp)
    @. temp = x0 + 0.5 * dt * k2
    lorenz96_rhs!(k3, F, temp)
    @. temp = x0 + dt * k3
    lorenz96_rhs!(k4, F, temp)

    next_x = Vector{Float64}(undef, n)
    @. next_x = x0 + dt * (k1 + 2 * k2 + 2 * k3 + k4) / 6
    return next_x
end

function advance_lorenz96_state(spec::Lorenz96Spec, x0::AbstractVector{<:Real}, steps::Integer)
    validate_lorenz96_spec(spec)
    validate_lorenz96_state(spec, x0)
    steps >= 0 || throw(ArgumentError("steps must be nonnegative"))

    x = Float64.(x0)
    for _ in 1:steps
        x = rk4_lorenz96_step(spec.F, spec.dt, x)
    end
    return x
end

function generate_lorenz96_trajectory(spec::Lorenz96Spec, x0::AbstractVector{<:Real})
    validate_lorenz96_spec(spec)
    validate_lorenz96_state(spec, x0)

    times = lorenz96_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[:, m + 1] = rk4_lorenz96_step(spec.F, spec.dt, view(X, :, m))
    end

    return times, X
end

## Sanity checks for boundary indices

function validate_lorenz96_boundary_indices(spec::Lorenz96Spec)
    validate_lorenz96_spec(spec)
    x = collect(1.0:Float64(spec.state_dim))
    dx = lorenz96_vector_field(spec, x)
    terms = lorenz96_boundary_terms(spec.F, x)
    abs(dx[1] - terms["i1"]) <= 1e-12 || throw(ArgumentError("boundary RHS mismatch at i=1"))
    abs(dx[2] - terms["i2"]) <= 1e-12 || throw(ArgumentError("boundary RHS mismatch at i=2"))
    abs(dx[end] - terms["iK"]) <= 1e-12 || throw(ArgumentError("boundary RHS mismatch at i=K"))
    return true
end

## System registration payload

function lorenz96_metadata(spec::Lorenz96Spec)
    validate_lorenz96_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "F" => spec.F,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "divergence" => lorenz96_divergence(spec),
        "uniform_state_residual" => lorenz96_uniform_residual(spec),
        "vector_field" => "dx_i = (x_{i+1} - x_{i-2}) * x_{i-1} - x_i + F with cyclic indices",
    )
end
