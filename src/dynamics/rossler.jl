## Rossler system identity and default parameters

struct RosslerSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    a::Float64
    b::Float64
    c::Float64
    dt::Float64
    burn_in_time::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function rossler_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return RosslerSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["a"]),
        Float64(params["b"]),
        Float64(params["c"]),
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

function validate_rossler_spec(spec::RosslerSpec; atol::Real = 1e-10)
    spec.system_id == "rossler_standard" || throw(ArgumentError("system_id must be rossler_standard"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 3 || throw(ArgumentError("state_dim must be 3"))
    all(isfinite, (spec.a, spec.b, spec.c)) ||
        throw(ArgumentError("Rossler parameters must be finite"))
    spec.a > 0 || throw(ArgumentError("a must be positive"))
    spec.b > 0 || throw(ArgumentError("b must be positive"))
    spec.c > 0 || throw(ArgumentError("c must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.burn_in_time >= 0 || throw(ArgumentError("burn_in_time must be nonnegative"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    abs(round(spec.burn_in_time / spec.dt) * spec.dt - spec.burn_in_time) <= atol ||
        throw(ArgumentError("burn_in_time must be an integer multiple of dt"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("Rossler smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_rossler_state(spec::RosslerSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

## Rossler vector field

function rossler_rhs_components(
    a::Real,
    b::Real,
    c::Real,
    x::Real,
    y::Real,
    z::Real,
)
    return -y - z, x + a * y, b + z * (x - c)
end

function rossler_vector_field(spec::RosslerSpec, x::AbstractVector{<:Real})
    validate_rossler_state(spec, x)
    dx, dy, dz = rossler_rhs_components(spec.a, spec.b, spec.c, x[1], x[2], x[3])
    return [dx, dy, dz]
end

function rossler_divergence(spec::RosslerSpec, x::Real)
    validate_rossler_spec(spec)
    return x + spec.a - spec.c
end

## Fixed-step RK4 trajectory propagation

function rossler_times(spec::RosslerSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_rossler_step(
    a::Real,
    b::Real,
    c::Real,
    dt::Real,
    x::Real,
    y::Real,
    z::Real,
)
    k1x, k1y, k1z = rossler_rhs_components(a, b, c, x, y, z)
    k2x, k2y, k2z = rossler_rhs_components(
        a,
        b,
        c,
        x + 0.5 * dt * k1x,
        y + 0.5 * dt * k1y,
        z + 0.5 * dt * k1z,
    )
    k3x, k3y, k3z = rossler_rhs_components(
        a,
        b,
        c,
        x + 0.5 * dt * k2x,
        y + 0.5 * dt * k2y,
        z + 0.5 * dt * k2z,
    )
    k4x, k4y, k4z = rossler_rhs_components(
        a,
        b,
        c,
        x + dt * k3x,
        y + dt * k3y,
        z + dt * k3z,
    )

    next_x = x + dt * (k1x + 2 * k2x + 2 * k3x + k4x) / 6
    next_y = y + dt * (k1y + 2 * k2y + 2 * k3y + k4y) / 6
    next_z = z + dt * (k1z + 2 * k2z + 2 * k3z + k4z) / 6
    return next_x, next_y, next_z
end

function advance_rossler_state(spec::RosslerSpec, x0::AbstractVector{<:Real}, steps::Integer)
    validate_rossler_spec(spec)
    validate_rossler_state(spec, x0)
    steps >= 0 || throw(ArgumentError("steps must be nonnegative"))

    x = Float64(x0[1])
    y = Float64(x0[2])
    z = Float64(x0[3])
    @inbounds for _ in 1:steps
        x, y, z = rk4_rossler_step(spec.a, spec.b, spec.c, spec.dt, x, y, z)
    end
    return [x, y, z]
end

function generate_rossler_trajectory(spec::RosslerSpec, x0::AbstractVector{<:Real})
    validate_rossler_spec(spec)
    validate_rossler_state(spec, x0)

    times = rossler_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1], X[3, m + 1] = rk4_rossler_step(
            spec.a,
            spec.b,
            spec.c,
            spec.dt,
            X[1, m],
            X[2, m],
            X[3, m],
        )
    end

    return times, X
end

## System registration payload

function rossler_metadata(spec::RosslerSpec)
    validate_rossler_spec(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "a" => spec.a,
        "b" => spec.b,
        "c" => spec.c,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "divergence" => "x + a - c",
        "vector_field" => "x_dot = -y-z; y_dot = x+a*y; z_dot = b+z*(x-c)",
    )
end
