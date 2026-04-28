## Linear oscillator parameter conventions

using LinearAlgebra

struct LinearOscillatorSpec
    system_id::String
    family::String
    variant::String
    state_dim::Int
    gamma::Float64
    omega0::Float64
    dt::Float64
    trajectory_length::Int
    solver_name::String
    solver_abstol::Float64
    solver_reltol::Float64
end

function linear_oscillator_spec_from_config(config::AbstractDict)
    params = config["default_parameters"]
    return LinearOscillatorSpec(
        String(config["system_id"]),
        String(config["family"]),
        String(config["variant"]),
        Int(config["state_dim"]),
        Float64(params["gamma"]),
        Float64(params["omega0"]),
        Float64(config["dt"]),
        Int(config["trajectory_length"]),
        String(config["solver_name"]),
        Float64(config["solver_abstol"]),
        Float64(config["solver_reltol"]),
    )
end

## Parameter validity checks for undamped and underdamped regimes

function validate_linear_oscillator_spec(spec::LinearOscillatorSpec)
    spec.system_id == "linear_oscillator" ||
        throw(ArgumentError("system_id must be linear_oscillator"))
    spec.state_dim == 2 || throw(ArgumentError("state_dim must be 2"))
    isfinite(spec.gamma) || throw(ArgumentError("gamma must be finite"))
    isfinite(spec.omega0) || throw(ArgumentError("omega0 must be finite"))
    spec.gamma >= 0 || throw(ArgumentError("gamma must be nonnegative"))
    spec.omega0 > 0 || throw(ArgumentError("omega0 must be positive"))
    spec.gamma < spec.omega0 || throw(ArgumentError("linear oscillator spec must be underdamped"))
    spec.dt > 0 || throw(ArgumentError("dt must be positive"))
    spec.trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    spec.solver_name == "exact_discrete_linear" ||
        throw(ArgumentError("solver_name must be exact_discrete_linear"))

    if spec.variant == "undamped_smoke"
        spec.gamma == 0.0 || throw(ArgumentError("undamped_smoke requires gamma=0"))
    end

    return true
end

## Continuous-time state matrix construction

function continuous_generator_matrix(spec::LinearOscillatorSpec)
    validate_linear_oscillator_spec(spec)
    return [
        0.0 1.0
        -(spec.omega0^2) -2.0 * spec.gamma
    ]
end

## Exact discrete propagator construction

function exact_discrete_propagator(spec::LinearOscillatorSpec)
    validate_linear_oscillator_spec(spec)
    omega_d = sqrt(spec.omega0^2 - spec.gamma^2)
    theta = omega_d * spec.dt
    c = cos(theta)
    s = sin(theta)
    damping = exp(-spec.gamma * spec.dt)

    return damping .* [
        c + (spec.gamma / omega_d) * s s / omega_d
        -(spec.omega0^2 / omega_d) * s c - (spec.gamma / omega_d) * s
    ]
end

## ODE right-hand side definition

function linear_oscillator_rhs(spec::LinearOscillatorSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("x length must match state_dim"))
    return continuous_generator_matrix(spec) * Float64.(x)
end

## Continuous spectrum and discrete spectrum metadata

function continuous_eigenvalues(spec::LinearOscillatorSpec)
    validate_linear_oscillator_spec(spec)
    omega_d = sqrt(spec.omega0^2 - spec.gamma^2)
    return ComplexF64[-spec.gamma + im * omega_d, -spec.gamma - im * omega_d]
end

function discrete_eigenvalues(spec::LinearOscillatorSpec)
    return exp.(continuous_eigenvalues(spec) .* spec.dt)
end

## Analytic energy and damping diagnostics

function linear_oscillator_energy(spec::LinearOscillatorSpec, x::AbstractVector{<:Real})
    length(x) == spec.state_dim || throw(ArgumentError("x length must match state_dim"))
    q = Float64(x[1])
    v = Float64(x[2])
    return 0.5 * v^2 + 0.5 * spec.omega0^2 * q^2
end

function linear_oscillator_energy_series(spec::LinearOscillatorSpec, X::AbstractMatrix)
    size(X, 1) == spec.state_dim || throw(ArgumentError("state matrix first dimension must be state_dim"))
    return [linear_oscillator_energy(spec, view(X, :, m)) for m in axes(X, 2)]
end

## Exact trajectory propagation

function linear_oscillator_times(spec::LinearOscillatorSpec)
    return collect(range(0.0; step = spec.dt, length = spec.trajectory_length + 1))
end

function generate_linear_oscillator_trajectory(spec::LinearOscillatorSpec, x0::AbstractVector{<:Real})
    validate_linear_oscillator_spec(spec)
    length(x0) == spec.state_dim || throw(ArgumentError("x0 length must match state_dim"))

    times = linear_oscillator_times(spec)
    F = exact_discrete_propagator(spec)
    X = Matrix{Float64}(undef, spec.state_dim, spec.trajectory_length + 1)
    X[:, 1] = Float64.(x0)

    @inbounds for m in 1:spec.trajectory_length
        X[:, m + 1] = F * X[:, m]
    end

    return times, X
end

function validate_raw_trajectory_dimensions(spec::LinearOscillatorSpec, traj)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    return true
end

## State dimension and variable-name metadata

function linear_oscillator_complex_metadata(z::Complex)
    return Dict(
        "real" => real(z),
        "imag" => imag(z),
        "abs" => abs(z),
        "angle" => angle(z),
    )
end

function linear_oscillator_metadata(spec::LinearOscillatorSpec)
    A = continuous_generator_matrix(spec)
    F = exact_discrete_propagator(spec)
    lambdas_c = continuous_eigenvalues(spec)
    lambdas_d = discrete_eigenvalues(spec)

    return Dict(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "state_variables" => ["q", "v"],
        "gamma" => spec.gamma,
        "omega0" => spec.omega0,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "continuous_matrix_A" => [A[i, :] for i in axes(A, 1)],
        "discrete_matrix_F" => [F[i, :] for i in axes(F, 1)],
        "continuous_eigenvalues" => Dict(
            "lambda_plus" => linear_oscillator_complex_metadata(lambdas_c[1]),
            "lambda_minus" => linear_oscillator_complex_metadata(lambdas_c[2]),
        ),
        "discrete_eigenvalues" => Dict(
            "rho_plus" => linear_oscillator_complex_metadata(lambdas_d[1]),
            "rho_minus" => linear_oscillator_complex_metadata(lambdas_d[2]),
        ),
    )
end
