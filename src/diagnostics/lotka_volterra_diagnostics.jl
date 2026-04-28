## Diagnostic scope for Lotka-Volterra trajectories

using LinearAlgebra
using Statistics

## Full-state, finite-value, and positivity checks

function lotka_volterra_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function lotka_volterra_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

function lotka_volterra_all_positive(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(>(0), traj.state_matrix), raw_trajectories)
end

## Invariant diagnostics

function lotka_volterra_invariant_sequence(spec::LotkaVolterraSpec, traj::RawTrajectory)
    return [
        lotka_volterra_invariant(spec, traj.state_matrix[1, m], traj.state_matrix[2, m])
        for m in axes(traj.state_matrix, 2)
    ]
end

function lotka_volterra_invariant_diagnostics(
    spec::LotkaVolterraSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    initial_values = Float64[]
    max_absolute_drifts = Float64[]
    max_relative_drifts = Float64[]
    final_drifts = Float64[]

    for traj in raw_trajectories
        values = lotka_volterra_invariant_sequence(spec, traj)
        all(isfinite, values) || throw(ArgumentError("Lotka-Volterra invariant contains NaN or Inf"))
        initial = first(values)
        drifts = values .- initial
        push!(initial_values, initial)
        push!(max_absolute_drifts, maximum(abs.(drifts)))
        push!(max_relative_drifts, maximum(abs.(drifts)) / (abs(initial) + eps(Float64)))
        push!(final_drifts, last(values) - initial)
    end

    return Dict(
        "invariant_initial_min" => minimum(initial_values),
        "invariant_initial_max" => maximum(initial_values),
        "invariant_initial_std" => std(initial_values),
        "invariant_max_abs_drift" => maximum(max_absolute_drifts),
        "invariant_max_rel_drift" => maximum(max_relative_drifts),
        "invariant_final_abs_drift_max" => maximum(abs.(final_drifts)),
        "invariant_max_abs_drift_by_trajectory" => max_absolute_drifts,
        "invariant_max_rel_drift_by_trajectory" => max_relative_drifts,
    )
end

## State range, scale, and vector-field diagnostics

function lotka_volterra_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    x_values = reduce(vcat, [vec(traj.state_matrix[1, :]) for traj in raw_trajectories])
    y_values = reduce(vcat, [vec(traj.state_matrix[2, :]) for traj in raw_trajectories])
    return Dict(
        "x_min" => minimum(x_values),
        "x_max" => maximum(x_values),
        "y_min" => minimum(y_values),
        "y_max" => maximum(y_values),
    )
end

function lotka_volterra_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function lotka_volterra_velocity_norm_max(
    spec::LotkaVolterraSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dx, dy = lotka_volterra_rhs_components(
                spec.alpha,
                spec.beta,
                spec.gamma,
                spec.delta,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            max_velocity = max(max_velocity, norm([dx, dy]))
        end
    end
    return max_velocity
end

function lotka_volterra_rk4_self_residual_max(
    spec::LotkaVolterraSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_x, next_y = rk4_lotka_volterra_step(
                spec.alpha,
                spec.beta,
                spec.gamma,
                spec.delta,
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_x, traj.state_matrix[2, m + 1] - next_y]),
            )
        end
    end
    return residual
end

## Split and window count summaries

function enrich_lotka_volterra_diagnostics!(
    diagnostics::AbstractDict,
    split::AbstractDict,
    window_summary::AbstractDict,
)
    diagnostics["split_counts"] = Dict(
        "train" => length(split["train_trajectory_ids"]),
        "val" => length(split["val_trajectory_ids"]),
        "test" => length(split["test_trajectory_ids"]),
    )
    diagnostics["one_step_window_counts"] = window_summary["one_step"]["counts"]
    diagnostics["rollout_window_counts"] = Dict(
        horizon_key => summary["counts"]
        for (horizon_key, summary) in window_summary["rollout"]["by_horizon"]
    )
    diagnostics["statistics_window_counts"] = window_summary["statistics"]["counts"]
    return diagnostics
end

## Diagnostic threshold policy

function lotka_volterra_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["all_states_positive"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 20.0 &&
        diagnostics["velocity_norm_max"] < 80.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["invariant_max_rel_drift"] <= 1e-8
end

## Diagnostic table assembly

function summarize_lotka_volterra_dataset(
    spec::LotkaVolterraSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "gamma" => spec.gamma,
        "delta" => spec.delta,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "positive_equilibrium" => lotka_volterra_positive_equilibrium(spec),
        "local_frequency" => lotka_volterra_local_frequency(spec),
        "all_states_finite" => lotka_volterra_all_finite(raw_trajectories),
        "all_states_positive" => lotka_volterra_all_positive(raw_trajectories),
        "state_norm_max" => lotka_volterra_state_norm_max(raw_trajectories),
        "velocity_norm_max" => lotka_volterra_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => lotka_volterra_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => lotka_volterra_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, lotka_volterra_state_range(raw_trajectories))
    merge!(diagnostics, lotka_volterra_invariant_diagnostics(spec, raw_trajectories))
    diagnostics["smoke_passed"] = lotka_volterra_smoke_passed(diagnostics)
    return diagnostics
end

function lotka_volterra_diagnostics_csv_row(
    spec::LotkaVolterraSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "alpha",
        "beta",
        "gamma",
        "delta",
        "dt",
        "num_trajectories",
        "trajectory_length",
        "x_min",
        "x_max",
        "y_min",
        "y_max",
        "state_norm_max",
        "velocity_norm_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "invariant_initial_min",
        "invariant_initial_max",
        "invariant_max_abs_drift",
        "invariant_max_rel_drift",
        "all_states_positive",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.alpha,
        spec.beta,
        spec.gamma,
        spec.delta,
        spec.dt,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["x_min"],
        diagnostics["x_max"],
        diagnostics["y_min"],
        diagnostics["y_max"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["invariant_initial_min"],
        diagnostics["invariant_initial_max"],
        diagnostics["invariant_max_abs_drift"],
        diagnostics["invariant_max_rel_drift"],
        diagnostics["all_states_positive"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
