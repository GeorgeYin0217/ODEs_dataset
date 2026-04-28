## Module role and mathematical definition

using LinearAlgebra

struct JordanNonnormalLinearSpec
    system_id::String
    family::String
    state_dim::Int
    alpha::Float64
    gamma::Float64
    dt::Float64
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function jordan_nonnormal_linear_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    return JordanNonnormalLinearSpec(
        String(config["system_id"]),
        String(config["family"]),
        Int(config["state_dim"]),
        Float64(params["alpha"]),
        Float64(params["gamma"]),
        Float64(config["dt"]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter validation for Jordan nonnormal system

function validate_jordan_nonnormal_linear_spec(spec::JordanNonnormalLinearSpec)
    spec.system_id == "jordan_nonnormal_linear" ||
        throw(ArgumentError("system_id must be jordan_nonnormal_linear"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    isfinite(spec.alpha) || throw(ArgumentError("alpha must be finite"))
    isfinite(spec.gamma) || throw(ArgumentError("gamma must be finite"))
    spec.alpha < 0 || throw(ArgumentError("alpha must be negative"))
    spec.gamma > 0 || throw(ArgumentError("gamma must be positive"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 2 || throw(ArgumentError("trajectory_length must be at least 2"))
    spec.solver_name == "exact_jordan_closed_form" ||
        throw(ArgumentError("solver_name must be exact_jordan_closed_form"))
    return true
end

## Continuous-time generator matrix construction

function continuous_generator_matrix(spec::JordanNonnormalLinearSpec)
    validate_jordan_nonnormal_linear_spec(spec)
    return [
        spec.alpha spec.gamma
        0.0 spec.alpha
    ]
end

## Discrete-time flow matrix construction

function exact_discrete_propagator(spec::JordanNonnormalLinearSpec)
    validate_jordan_nonnormal_linear_spec(spec)
    scale = exp(spec.alpha * spec.dt)
    return scale .* [
        1.0 spec.gamma * spec.dt
        0.0 1.0
    ]
end

## Closed-form trajectory evaluation

function jordan_closed_form_state(
    spec::JordanNonnormalLinearSpec,
    x0::AbstractVector{<:Real},
    t::Real,
)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))
    scale = exp(spec.alpha * Float64(t))
    x0_float = Float64.(x0)
    return scale .* [
        x0_float[1] + spec.gamma * Float64(t) * x0_float[2],
        x0_float[2],
    ]
end

function jordan_nonnormal_linear_times(spec::JordanNonnormalLinearSpec)
    return collect(range(0.0; step = spec.dt, length = spec.trajectory_length + 1))
end

## Trajectory batch construction

function generate_jordan_nonnormal_linear_trajectory(
    spec::JordanNonnormalLinearSpec,
    x0::AbstractVector{<:Real},
)
    validate_jordan_nonnormal_linear_spec(spec)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))

    times = jordan_nonnormal_linear_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    @inbounds for (m, t) in enumerate(times)
        X[:, m] = jordan_closed_form_state(spec, x0, t)
    end
    return times, X
end

## Jordan structure metadata

function jordan_rank_and_geometric_multiplicity(spec::JordanNonnormalLinearSpec)
    A = continuous_generator_matrix(spec)
    shifted = A - spec.alpha * Matrix{Float64}(I, spec.state_dim, spec.state_dim)
    shifted_rank = rank(shifted)
    return shifted_rank, spec.state_dim - shifted_rank
end

function discrete_eigenvalue(spec::JordanNonnormalLinearSpec)
    return exp(spec.alpha * spec.dt)
end

## Numerical consistency checks

function jordan_nonnormal_linear_metadata(spec::JordanNonnormalLinearSpec)
    A = continuous_generator_matrix(spec)
    K = exact_discrete_propagator(spec)
    shifted_rank, geom_mult = jordan_rank_and_geometric_multiplicity(spec)
    lambda = discrete_eigenvalue(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "state_dim" => spec.state_dim,
        "alpha" => spec.alpha,
        "gamma" => spec.gamma,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "continuous_matrix_A" => [A[i, :] for i in axes(A, 1)],
        "discrete_matrix_K" => [K[i, :] for i in axes(K, 1)],
        "lambda_discrete" => lambda,
        "rank_A_minus_alphaI" => shifted_rank,
        "geom_mult" => geom_mult,
    )
end
