## System identity and parameter conventions

using LinearAlgebra

struct LinearRotationContraction2DSpec
    system_id::String
    family::String
    state_dim::Int
    gamma::Float64
    omega::Float64
    dt::Float64
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function linear_rotation_contraction_2d_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    return LinearRotationContraction2DSpec(
        String(config["system_id"]),
        String(config["family"]),
        Int(config["state_dim"]),
        Float64(params["gamma"]),
        Float64(params["omega"]),
        Float64(config["dt"]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter validation for contraction and rotation

function validate_linear_rotation_contraction_2d_spec(spec::LinearRotationContraction2DSpec)
    spec.system_id == "linear_rotation_contraction_2d" ||
        throw(ArgumentError("system_id must be linear_rotation_contraction_2d"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    isfinite(spec.gamma) || throw(ArgumentError("gamma must be finite"))
    isfinite(spec.omega) || throw(ArgumentError("omega must be finite"))
    spec.gamma > 0 || throw(ArgumentError("gamma must be positive"))
    spec.omega != 0 || throw(ArgumentError("omega must be nonzero"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    spec.solver_name == "exact_discrete_linear" ||
        throw(ArgumentError("solver_name must be exact_discrete_linear"))
    return true
end

## Continuous generator matrix construction

function continuous_generator_matrix(spec::LinearRotationContraction2DSpec)
    validate_linear_rotation_contraction_2d_spec(spec)
    return [
        -spec.gamma -spec.omega
        spec.omega -spec.gamma
    ]
end

## Exact discrete propagator construction

function exact_discrete_propagator(spec::LinearRotationContraction2DSpec)
    validate_linear_rotation_contraction_2d_spec(spec)
    rho = exp(-spec.gamma * spec.dt)
    theta = spec.omega * spec.dt
    return rho .* [
        cos(theta) -sin(theta)
        sin(theta) cos(theta)
    ]
end

## Continuous and discrete spectrum metadata

function continuous_eigenvalues(spec::LinearRotationContraction2DSpec)
    validate_linear_rotation_contraction_2d_spec(spec)
    return ComplexF64[-spec.gamma + im * spec.omega, -spec.gamma - im * spec.omega]
end

function discrete_eigenvalues(spec::LinearRotationContraction2DSpec)
    return exp.(continuous_eigenvalues(spec) .* spec.dt)
end

contraction_factor(spec::LinearRotationContraction2DSpec) = exp(-spec.gamma * spec.dt)

rotation_angle_per_step(spec::LinearRotationContraction2DSpec) = spec.omega * spec.dt

## Exact one-step state propagation

function propagate_one_step(spec::LinearRotationContraction2DSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("state vector length must match state_dim"))
    return exact_discrete_propagator(spec) * Float64.(x)
end

## Exact trajectory propagation

function linear_rotation_contraction_2d_times(spec::LinearRotationContraction2DSpec)
    return collect(range(0.0; step = spec.dt, length = spec.trajectory_length + 1))
end

function generate_linear_rotation_contraction_2d_trajectory(
    spec::LinearRotationContraction2DSpec,
    x0::AbstractVector{<:Real},
)
    validate_linear_rotation_contraction_2d_spec(spec)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))

    times = linear_rotation_contraction_2d_times(spec)
    F = exact_discrete_propagator(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[:, m + 1] = F * X[:, m]
    end

    return times, X
end

## Polar-coordinate diagnostic quantities

function radii_from_state_matrix(X::AbstractMatrix)
    size(X, 1) == 2 || throw(ArgumentError("state_matrix first dimension must be 2"))
    return [norm(view(X, :, m)) for m in axes(X, 2)]
end

function unwrapped_angles_from_state_matrix(X::AbstractMatrix)
    size(X, 1) == 2 || throw(ArgumentError("state_matrix first dimension must be 2"))
    angles = [atan(X[2, m], X[1, m]) for m in axes(X, 2)]

    unwrapped = copy(angles)
    for m in 2:length(unwrapped)
        delta = unwrapped[m] - unwrapped[m - 1]
        if delta > pi
            unwrapped[m:end] .-= 2pi
        elseif delta < -pi
            unwrapped[m:end] .+= 2pi
        end
    end

    return unwrapped
end

## Truth metadata assembly

function complex_metadata(z::Complex)
    return Dict(
        "real" => real(z),
        "imag" => imag(z),
        "abs" => abs(z),
        "angle" => angle(z),
    )
end

function linear_rotation_contraction_2d_metadata(spec::LinearRotationContraction2DSpec)
    A = continuous_generator_matrix(spec)
    F = exact_discrete_propagator(spec)
    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "state_dim" => spec.state_dim,
        "gamma" => spec.gamma,
        "omega" => spec.omega,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "continuous_matrix_A" => [A[i, :] for i in axes(A, 1)],
        "discrete_matrix_F" => [F[i, :] for i in axes(F, 1)],
        "continuous_eigenvalues" => Dict(
            "nu_plus" => complex_metadata(continuous_eigenvalues(spec)[1]),
            "nu_minus" => complex_metadata(continuous_eigenvalues(spec)[2]),
        ),
        "discrete_eigenvalues" => Dict(
            "lambda_plus" => complex_metadata(discrete_eigenvalues(spec)[1]),
            "lambda_minus" => complex_metadata(discrete_eigenvalues(spec)[2]),
        ),
        "contraction_factor" => contraction_factor(spec),
        "rotation_angle_per_step" => rotation_angle_per_step(spec),
    )
end
