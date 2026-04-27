## 1. Define parameter container for diagonal linear systems

using LinearAlgebra
using Random

struct LinearDiagonalSpec
    system_id::String
    family::String
    state_dim::Int
    eigenvalues::Vector{Float64}
    dt::Float64
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function linear_diagonal_spec_from_config(config::AbstractDict)
    eigenvalues = Float64.(config["default_parameters"]["eigenvalues"])
    return LinearDiagonalSpec(
        String(config["system_id"]),
        String(config["family"]),
        Int(config["state_dim"]),
        eigenvalues,
        Float64(config["dt"]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## 2. Validate eigenvalues, dimension, time step, and trajectory length

function validate_linear_diagonal_spec(spec::LinearDiagonalSpec)
    spec.state_dim > 0 || throw(ArgumentError("state_dim must be positive"))
    length(spec.eigenvalues) == spec.state_dim ||
        throw(ArgumentError("number of eigenvalues must match state_dim"))
    all(isfinite, spec.eigenvalues) || throw(ArgumentError("eigenvalues must be finite"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    return true
end

## 3. Construct exact discrete propagator A_tau

exact_discrete_propagator(spec::LinearDiagonalSpec) = Diagonal(exp.(spec.eigenvalues .* spec.dt))

## 4. Define continuous-time RHS for SciML compatibility

function linear_diagonal_rhs!(du, u, eigenvalues, t)
    @inbounds for i in eachindex(u, eigenvalues)
        du[i] = eigenvalues[i] * u[i]
    end
    return nothing
end

## 5. Generate one trajectory by exact formula

function linear_diagonal_times(spec::LinearDiagonalSpec)
    return collect(range(0.0; step = spec.dt, length = spec.trajectory_length + 1))
end

function sample_initial_condition(
    rng::AbstractRNG,
    state_dim::Integer;
    lower::Real = -1.0,
    upper::Real = 1.0,
    min_abs::Real = 0.1,
    max_attempts::Integer = 10_000,
)
    lower < upper || throw(ArgumentError("lower must be smaller than upper"))
    min_abs >= 0 || throw(ArgumentError("min_abs must be nonnegative"))

    for _ in 1:max_attempts
        x0 = lower .+ (upper - lower) .* rand(rng, state_dim)
        if minimum(abs.(x0)) >= min_abs
            return Vector{Float64}(x0)
        end
    end

    throw(ArgumentError("could not sample an initial condition satisfying min_abs"))
end

function generate_linear_diagonal_trajectory(spec::LinearDiagonalSpec, x0::AbstractVector{<:Real})
    validate_linear_diagonal_spec(spec)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))

    times = linear_diagonal_times(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)

    @inbounds for (m, t) in enumerate(times)
        X[:, m] = Float64.(x0) .* exp.(spec.eigenvalues .* t)
    end

    return times, X
end

## 6. Compute analytic solution error and one-step residual

function analytic_solution(spec::LinearDiagonalSpec, x0::AbstractVector{<:Real}, times::AbstractVector)
    X_exact = Matrix{Float64}(undef, spec.state_dim, length(times))
    @inbounds for (m, t) in enumerate(times)
        X_exact[:, m] = Float64.(x0) .* exp.(spec.eigenvalues .* Float64(t))
    end
    return X_exact
end

function max_analytic_error(
    spec::LinearDiagonalSpec,
    x0::AbstractVector{<:Real},
    X::AbstractMatrix,
    times::AbstractVector,
)
    X_exact = analytic_solution(spec, x0, times)
    return maximum(abs.(X .- X_exact))
end

function max_one_step_residual(spec::LinearDiagonalSpec, X::AbstractMatrix)
    size(X) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("X must have size (state_dim, trajectory_length + 1)"))

    A = exact_discrete_propagator(spec)
    residual = 0.0
    @inbounds for m in 1:spec.trajectory_length
        residual = max(residual, maximum(abs.(X[:, m + 1] .- A * X[:, m])))
    end
    return residual
end

function linear_diagonal_metadata(spec::LinearDiagonalSpec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "state_dim" => spec.state_dim,
        "eigenvalues" => spec.eigenvalues,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "discrete_eigenvalues" => diag(exact_discrete_propagator(spec)),
    )
end
