## FitzHugh-Nagumo system identity and parameter convention

struct FitzHughNagumoSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    a::Float64
    b::Float64
    epsilon::Float64
    I::Float64
    dt::Float64
    tspan::Tuple{Float64,Float64}
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function fitzhugh_nagumo_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    tspan_values = Float64.(config["tspan"])
    return FitzHughNagumoSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["a"]),
        Float64(params["b"]),
        Float64(params["epsilon"]),
        Float64(params["I"]),
        Float64(config["dt"]),
        (tspan_values[1], tspan_values[2]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter and state validation

function validate_fitzhugh_nagumo_spec(spec::FitzHughNagumoSpec; atol::Real = 1e-10)
    spec.system_id == "fitzhugh_nagumo" || throw(ArgumentError("system_id must be fitzhugh_nagumo"))
    spec.family == "v1_core" || throw(ArgumentError("family must be v1_core"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    all(isfinite, (spec.a, spec.b, spec.epsilon, spec.I)) ||
        throw(ArgumentError("FitzHugh-Nagumo parameters must be finite"))
    spec.b > 0 || throw(ArgumentError("b must be positive"))
    spec.epsilon > 0 || throw(ArgumentError("epsilon must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    abs((spec.tspan[2] - spec.tspan[1]) - spec.dt * spec.trajectory_length) <= atol ||
        throw(ArgumentError("tspan, dt, and trajectory_length are not consistent"))
    spec.solver_name == "fixed_step_rk4" ||
        throw(ArgumentError("FitzHugh-Nagumo smoke generator expects solver_name=fixed_step_rk4"))
    return true
end

function validate_fitzhugh_nagumo_state(spec::FitzHughNagumoSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    all(isfinite, x) || throw(ArgumentError("state vector contains NaN or Inf"))
    return true
end

## Vector field, nullclines, Jacobian, and equilibrium helpers

function fitzhugh_nagumo_rhs_components(
    a::Real,
    b::Real,
    epsilon::Real,
    I::Real,
    v::Real,
    w::Real,
)
    return v - v^3 / 3 - w + I, epsilon * (v + a - b * w)
end

function fitzhugh_nagumo_vector_field(spec::FitzHughNagumoSpec, x::AbstractVector{<:Real})
    validate_fitzhugh_nagumo_state(spec, x)
    dv, dw = fitzhugh_nagumo_rhs_components(spec.a, spec.b, spec.epsilon, spec.I, x[1], x[2])
    return [dv, dw]
end

function fitzhugh_nagumo_v_nullcline(spec::FitzHughNagumoSpec, v::Real)
    return v - v^3 / 3 + spec.I
end

function fitzhugh_nagumo_w_nullcline(spec::FitzHughNagumoSpec, v::Real)
    return (v + spec.a) / spec.b
end

function fitzhugh_nagumo_equilibrium_scalar(spec::FitzHughNagumoSpec, v::Real)
    return fitzhugh_nagumo_v_nullcline(spec, v) - fitzhugh_nagumo_w_nullcline(spec, v)
end

function fitzhugh_nagumo_bisect_equilibrium(
    spec::FitzHughNagumoSpec,
    left::Real,
    right::Real;
    iterations::Integer = 80,
)
    a = Float64(left)
    b = Float64(right)
    fa = fitzhugh_nagumo_equilibrium_scalar(spec, a)
    fb = fitzhugh_nagumo_equilibrium_scalar(spec, b)
    fa == 0 && return a
    fb == 0 && return b
    fa * fb <= 0 || throw(ArgumentError("equilibrium bracket does not contain a sign change"))

    for _ in 1:iterations
        mid = 0.5 * (a + b)
        fm = fitzhugh_nagumo_equilibrium_scalar(spec, mid)
        if fa * fm <= 0
            b = mid
            fb = fm
        else
            a = mid
            fa = fm
        end
    end

    return 0.5 * (a + b)
end

function fitzhugh_nagumo_equilibria(spec::FitzHughNagumoSpec; vmin::Real = -4.0, vmax::Real = 4.0)
    validate_fitzhugh_nagumo_spec(spec)
    grid = collect(range(Float64(vmin), Float64(vmax); length = 1601))
    roots = Float64[]

    previous_v = first(grid)
    previous_value = fitzhugh_nagumo_equilibrium_scalar(spec, previous_v)
    for v in grid[2:end]
        value = fitzhugh_nagumo_equilibrium_scalar(spec, v)
        if previous_value == 0
            push!(roots, previous_v)
        elseif previous_value * value < 0
            push!(roots, fitzhugh_nagumo_bisect_equilibrium(spec, previous_v, v))
        end
        previous_v = v
        previous_value = value
    end

    unique_roots = Float64[]
    for root in roots
        if all(abs(root - existing) > 1e-8 for existing in unique_roots)
            push!(unique_roots, root)
        end
    end

    return [[v, fitzhugh_nagumo_w_nullcline(spec, v)] for v in unique_roots]
end

function fitzhugh_nagumo_equilibrium_residual(spec::FitzHughNagumoSpec, x::AbstractVector{<:Real})
    dv, dw = fitzhugh_nagumo_rhs_components(spec.a, spec.b, spec.epsilon, spec.I, x[1], x[2])
    return sqrt(dv^2 + dw^2)
end

function fitzhugh_nagumo_jacobian(spec::FitzHughNagumoSpec, x::AbstractVector{<:Real})
    validate_fitzhugh_nagumo_state(spec, x)
    v = x[1]
    return [
        1-v^2 -1
        spec.epsilon -spec.epsilon*spec.b
    ]
end

## Fixed-step RK4 trajectory propagation

function fitzhugh_nagumo_times(spec::FitzHughNagumoSpec)
    return collect(range(spec.tspan[1]; step = spec.dt, length = spec.trajectory_length + 1))
end

function rk4_fitzhugh_nagumo_step(
    a::Real,
    b::Real,
    epsilon::Real,
    I::Real,
    dt::Real,
    v::Real,
    w::Real,
)
    k1_v, k1_w = fitzhugh_nagumo_rhs_components(a, b, epsilon, I, v, w)
    k2_v, k2_w = fitzhugh_nagumo_rhs_components(a, b, epsilon, I, v + 0.5 * dt * k1_v, w + 0.5 * dt * k1_w)
    k3_v, k3_w = fitzhugh_nagumo_rhs_components(a, b, epsilon, I, v + 0.5 * dt * k2_v, w + 0.5 * dt * k2_w)
    k4_v, k4_w = fitzhugh_nagumo_rhs_components(a, b, epsilon, I, v + dt * k3_v, w + dt * k3_w)

    next_v = v + dt * (k1_v + 2 * k2_v + 2 * k3_v + k4_v) / 6
    next_w = w + dt * (k1_w + 2 * k2_w + 2 * k3_w + k4_w) / 6
    return next_v, next_w
end

function generate_fitzhugh_nagumo_trajectory(spec::FitzHughNagumoSpec, x0::AbstractVector{<:Real})
    validate_fitzhugh_nagumo_spec(spec)
    validate_fitzhugh_nagumo_state(spec, x0)

    times = fitzhugh_nagumo_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[1, m + 1], X[2, m + 1] = rk4_fitzhugh_nagumo_step(
            spec.a,
            spec.b,
            spec.epsilon,
            spec.I,
            spec.dt,
            X[1, m],
            X[2, m],
        )
    end

    return times, X
end

## System metadata helper

function fitzhugh_nagumo_metadata(spec::FitzHughNagumoSpec)
    validate_fitzhugh_nagumo_spec(spec)
    equilibria = fitzhugh_nagumo_equilibria(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "a" => spec.a,
        "b" => spec.b,
        "epsilon" => spec.epsilon,
        "I" => spec.I,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "equilibria" => equilibria,
        "vector_field" => "v_dot = v - v^3 / 3 - w + I; w_dot = epsilon * (v + a - b*w)",
        "v_nullcline" => "w = v - v^3 / 3 + I",
        "w_nullcline" => "w = (v + a) / b",
    )
end
