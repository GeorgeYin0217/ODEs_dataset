## Diagnostic role for Jordan nonnormal systems

using LinearAlgebra
using Statistics

## Matrix structure diagnostics

function jordan_matrix_structure_diagnostic(spec::JordanNonnormalLinearSpec)
    A = continuous_generator_matrix(spec)
    K = exact_discrete_propagator(spec)
    shifted_rank, geom_mult = jordan_rank_and_geometric_multiplicity(spec)
    lambda = discrete_eigenvalue(spec)
    eigen_error = maximum(abs.(eigvals(K) .- lambda))
    return Dict(
        "state_dim" => spec.state_dim,
        "rank_A_minus_alphaI" => shifted_rank,
        "geom_mult" => geom_mult,
        "lambda_discrete" => lambda,
        "discrete_eigenvalue_max_abs_error" => eigen_error,
        "generator_matrix_size" => collect(size(A)),
        "discrete_matrix_size" => collect(size(K)),
    )
end

## One-step closure residual diagnostics

function jordan_max_one_step_residual(spec::JordanNonnormalLinearSpec, X::AbstractMatrix)
    size(X) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("X must have size (state_dim, trajectory_length + 1)"))

    K = exact_discrete_propagator(spec)
    residual = 0.0
    @inbounds for m in 1:spec.trajectory_length
        residual = max(residual, norm(X[:, m + 1] - K * X[:, m]))
    end
    return residual
end

## Multi-step rollout residual diagnostics

function jordan_rollout_residual_diagnostic(
    spec::JordanNonnormalLinearSpec,
    raw_trajectories::AbstractVector{RawTrajectory};
    horizons::AbstractVector{<:Integer} = [5, 10, 20],
)
    K = exact_discrete_propagator(spec)
    by_horizon = Dict{String,Any}()
    global_max = 0.0

    for horizon in horizons
        horizon <= spec.trajectory_length ||
            throw(ArgumentError("rollout horizon cannot exceed trajectory_length"))
        residuals = Float64[]
        Kh = Matrix{Float64}(I, spec.state_dim, spec.state_dim)

        for ell in 1:horizon
            Kh = K * Kh
            for traj in raw_trajectories
                max_start = spec.trajectory_length + 1 - ell
                for s in 1:max_start
                    push!(residuals, norm(traj.state_matrix[:, s + ell] - Kh * traj.state_matrix[:, s]))
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
        "max_rollout_residual" => global_max,
        "by_horizon" => by_horizon,
    )
end

## Nonnormal transient amplification diagnostics

function jordan_transient_amplification_diagnostic(raw_trajectories::AbstractVector{RawTrajectory})
    amplification = Float64[]
    for traj in raw_trajectories
        norms = [norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2)]
        push!(amplification, maximum(norms) / norms[1])
    end
    return Dict(
        "max_norm_amplification" => maximum(amplification),
        "mean_norm_amplification" => mean(amplification),
    )
end

## Initial condition activation diagnostics

function jordan_x2_activation_diagnostic(raw_trajectories::AbstractVector{RawTrajectory})
    initial_x2 = abs.([traj.initial_condition_instance[2] for traj in raw_trajectories])
    return Dict(
        "x2_activation_min_abs" => minimum(initial_x2),
        "x2_activation_mean_abs" => mean(initial_x2),
    )
end

## Diagnostic summary table construction

function jordan_max_closed_form_error(
    spec::JordanNonnormalLinearSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    err = 0.0
    for traj in raw_trajectories
        for (m, t) in enumerate(traj.times)
            err = max(err, norm(traj.state_matrix[:, m] - jordan_closed_form_state(spec, traj.initial_condition_instance, t)))
        end
    end
    return err
end

function jordan_smoke_passed(diagnostics::AbstractDict; atol::Real = 1e-10)
    return diagnostics["rank_A_minus_alphaI"] == 1 &&
        diagnostics["geom_mult"] == 1 &&
        diagnostics["max_closed_form_error"] <= atol &&
        diagnostics["max_one_step_residual"] <= atol &&
        diagnostics["max_rollout_residual"] <= atol &&
        diagnostics["discrete_eigenvalue_max_abs_error"] <= atol &&
        diagnostics["max_norm_amplification"] > 1.0 &&
        diagnostics["x2_activation_min_abs"] > 0.0
end

function summarize_jordan_nonnormal_dataset(
    spec::JordanNonnormalLinearSpec,
    raw_trajectories::AbstractVector{RawTrajectory};
    horizons::AbstractVector{<:Integer} = [5, 10, 20],
)
    matrix_stats = jordan_matrix_structure_diagnostic(spec)
    rollout = jordan_rollout_residual_diagnostic(spec, raw_trajectories; horizons = horizons)
    amplification = jordan_transient_amplification_diagnostic(raw_trajectories)
    activation = jordan_x2_activation_diagnostic(raw_trajectories)
    one_step = maximum(jordan_max_one_step_residual(spec, traj.state_matrix) for traj in raw_trajectories)

    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "alpha" => spec.alpha,
        "gamma" => spec.gamma,
        "dt" => spec.dt,
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "max_closed_form_error" => jordan_max_closed_form_error(spec, raw_trajectories),
        "max_one_step_residual" => one_step,
    )

    merge!(diagnostics, matrix_stats)
    merge!(diagnostics, rollout)
    merge!(diagnostics, amplification)
    merge!(diagnostics, activation)
    diagnostics["smoke_passed"] = jordan_smoke_passed(diagnostics)
    return diagnostics
end

function jordan_diagnostics_csv_row(
    spec::JordanNonnormalLinearSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "alpha",
        "gamma",
        "dt",
        "lambda_discrete",
        "rank_A_minus_alphaI",
        "geom_mult",
        "max_closed_form_error",
        "max_one_step_residual",
        "max_rollout_residual",
        "max_norm_amplification",
        "x2_activation_min_abs",
        "x2_activation_mean_abs",
        "num_trajectories",
        "trajectory_length",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.alpha,
        spec.gamma,
        spec.dt,
        diagnostics["lambda_discrete"],
        diagnostics["rank_A_minus_alphaI"],
        diagnostics["geom_mult"],
        diagnostics["max_closed_form_error"],
        diagnostics["max_one_step_residual"],
        diagnostics["max_rollout_residual"],
        diagnostics["max_norm_amplification"],
        diagnostics["x2_activation_min_abs"],
        diagnostics["x2_activation_mean_abs"],
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
