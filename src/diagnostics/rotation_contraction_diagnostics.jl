## Diagnostic scope and required inputs

using LinearAlgebra
using Statistics

## Radius contraction diagnostic

function radius_contraction_diagnostic(
    spec::LinearRotationContraction2DSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    rho_true = contraction_factor(spec)
    ratios = Float64[]

    for traj in raw_trajectories
        radii = radii_from_state_matrix(traj.state_matrix)
        append!(ratios, radii[2:end] ./ radii[1:(end - 1)])
    end

    errors = abs.(ratios .- rho_true)
    return Dict(
        "rho_true" => rho_true,
        "rho_empirical_mean" => mean(ratios),
        "rho_empirical_std" => std(ratios),
        "rho_empirical_max_abs_error" => maximum(errors),
    )
end

## Angle increment diagnostic with phase unwrapping

function angle_increment_diagnostic(
    spec::LinearRotationContraction2DSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    theta_true = rotation_angle_per_step(spec)
    increments = Float64[]

    for traj in raw_trajectories
        angles = unwrapped_angles_from_state_matrix(traj.state_matrix)
        append!(increments, diff(angles))
    end

    errors = abs.(increments .- theta_true)
    return Dict(
        "theta_step_true" => theta_true,
        "theta_step_empirical_mean" => mean(increments),
        "theta_step_empirical_std" => std(increments),
        "theta_step_max_abs_error" => maximum(errors),
    )
end

## Discrete spectrum diagnostic

function spectrum_abs_error_max(spec::LinearRotationContraction2DSpec)
    observed = eigvals(exact_discrete_propagator(spec))
    truth = discrete_eigenvalues(spec)
    return maximum([
        minimum(abs.(z .- truth))
        for z in observed
    ])
end

## Exact rollout residual diagnostic

function max_one_step_residual(spec::LinearRotationContraction2DSpec, X::AbstractMatrix)
    size(X) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("X must have size (state_dim, trajectory_length + 1)"))

    F = exact_discrete_propagator(spec)
    residual = 0.0
    @inbounds for m in 1:spec.trajectory_length
        residual = max(residual, norm(X[:, m + 1] - F * X[:, m]))
    end
    return residual
end

function rollout_residual_diagnostic(
    spec::LinearRotationContraction2DSpec,
    raw_trajectories::AbstractVector{RawTrajectory};
    horizons::AbstractVector{<:Integer} = [10, 50, 100],
)
    F = exact_discrete_propagator(spec)
    by_horizon = Dict{String,Any}()
    global_max = 0.0

    for horizon in horizons
        horizon <= spec.trajectory_length ||
            throw(ArgumentError("rollout horizon cannot exceed trajectory_length"))
        residuals = Float64[]
        Fh = Matrix{Float64}(I, spec.state_dim, spec.state_dim)

        for ell in 1:horizon
            Fh = F * Fh
            for traj in raw_trajectories
                max_start = spec.trajectory_length + 1 - ell
                for s in 1:max_start
                    push!(residuals, norm(traj.state_matrix[:, s + ell] - Fh * traj.state_matrix[:, s]))
                end
            end
        end

        residual_max = maximum(residuals)
        global_max = max(global_max, residual_max)
        by_horizon[string("h", horizon)] = Dict(
            "rollout_horizon" => Int(horizon),
            "rollout_residual_mean" => mean(residuals),
            "rollout_residual_max" => residual_max,
        )
    end

    return Dict(
        "rollout_residual_max" => global_max,
        "by_horizon" => by_horizon,
    )
end

## Diagnostic threshold policy

function rotation_contraction_smoke_passed(diagnostics::AbstractDict; atol::Real = 1e-10)
    return diagnostics["rho_empirical_max_abs_error"] <= atol &&
        diagnostics["theta_step_max_abs_error"] <= atol &&
        diagnostics["rollout_residual_max"] <= atol &&
        diagnostics["spectrum_abs_error_max"] <= atol
end

## Diagnostic table assembly

function summarize_rotation_contraction_dataset(
    spec::LinearRotationContraction2DSpec,
    raw_trajectories::AbstractVector{RawTrajectory};
    horizons::AbstractVector{<:Integer} = [10, 50, 100],
)
    radius = radius_contraction_diagnostic(spec, raw_trajectories)
    angle_stats = angle_increment_diagnostic(spec, raw_trajectories)
    rollout = rollout_residual_diagnostic(spec, raw_trajectories; horizons = horizons)
    one_step = maximum(max_one_step_residual(spec, traj.state_matrix) for traj in raw_trajectories)

    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "gamma" => spec.gamma,
        "omega" => spec.omega,
        "dt" => spec.dt,
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "max_one_step_residual" => one_step,
        "spectrum_abs_error_max" => spectrum_abs_error_max(spec),
    )

    merge!(diagnostics, radius)
    merge!(diagnostics, angle_stats)
    merge!(diagnostics, rollout)
    diagnostics["smoke_passed"] = rotation_contraction_smoke_passed(diagnostics)
    return diagnostics
end

function rotation_contraction_diagnostics_csv_row(
    spec::LinearRotationContraction2DSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "gamma",
        "omega",
        "dt",
        "rho_true",
        "rho_empirical_mean",
        "rho_empirical_max_abs_error",
        "theta_step_true",
        "theta_step_empirical_mean",
        "theta_step_max_abs_error",
        "rollout_residual_max",
        "spectrum_abs_error_max",
        "num_trajectories",
        "trajectory_length",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.gamma,
        spec.omega,
        spec.dt,
        diagnostics["rho_true"],
        diagnostics["rho_empirical_mean"],
        diagnostics["rho_empirical_max_abs_error"],
        diagnostics["theta_step_true"],
        diagnostics["theta_step_empirical_mean"],
        diagnostics["theta_step_max_abs_error"],
        diagnostics["rollout_residual_max"],
        diagnostics["spectrum_abs_error_max"],
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
