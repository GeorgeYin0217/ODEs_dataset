## Diagnostic scope for Van der Pol trajectories

using LinearAlgebra
using Statistics

## Full-state and finite-value checks

function vanderpol_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function vanderpol_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

## State-range and trajectory-scale checks

function vanderpol_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    x1_values = reduce(vcat, [vec(traj.state_matrix[1, :]) for traj in raw_trajectories])
    x2_values = reduce(vcat, [vec(traj.state_matrix[2, :]) for traj in raw_trajectories])
    return Dict(
        "x1_min" => minimum(x1_values),
        "x1_max" => maximum(x1_values),
        "x2_min" => minimum(x2_values),
        "x2_max" => maximum(x2_values),
    )
end

function vanderpol_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function vanderpol_mu_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    mu_values = [Float64(traj.parameter_instance["mu"]) for traj in raw_trajectories]
    return Dict(
        "mu_min" => minimum(mu_values),
        "mu_max" => maximum(mu_values),
        "mu_mean" => mean(mu_values),
        "mu_values" => mu_values,
    )
end

function vanderpol_velocity_norm_max(spec::VanDerPolUnforcedSpec, raw_trajectories::AbstractVector{RawTrajectory})
    max_velocity = 0.0
    for traj in raw_trajectories
        mu = Float64(traj.parameter_instance["mu"])
        for m in axes(traj.state_matrix, 2)
            dx1, dx2 = vanderpol_rhs_components(mu, traj.state_matrix[1, m], traj.state_matrix[2, m])
            max_velocity = max(max_velocity, norm([dx1, dx2]))
        end
    end
    return max_velocity
end

## RK4 self-consistency and oscillation diagnostics

function vanderpol_rk4_self_residual_max(spec::VanDerPolUnforcedSpec, raw_trajectories::AbstractVector{RawTrajectory})
    residual = 0.0
    for traj in raw_trajectories
        mu = Float64(traj.parameter_instance["mu"])
        @inbounds for m in 1:spec.trajectory_length
            next_x1, next_x2 = rk4_vanderpol_step(mu, spec.dt, traj.state_matrix[1, m], traj.state_matrix[2, m])
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_x1, traj.state_matrix[2, m + 1] - next_x2]),
            )
        end
    end
    return residual
end

function x1_sign_changes(values::AbstractVector{<:Real})
    count = 0
    previous = sign(first(values))
    for value in values[2:end]
        current = sign(value)
        if current != 0 && previous != 0 && current != previous
            count += 1
        end
        current != 0 && (previous = current)
    end
    return count
end

function vanderpol_tail_oscillation_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    tail_radius_means = Float64[]
    tail_radius_stds = Float64[]
    sign_changes = Int[]

    for traj in raw_trajectories
        start_index = max(1, fld(size(traj.state_matrix, 2), 2))
        tail = view(traj.state_matrix, :, start_index:size(traj.state_matrix, 2))
        radii = [norm(view(tail, :, m)) for m in axes(tail, 2)]
        push!(tail_radius_means, mean(radii))
        push!(tail_radius_stds, std(radii))
        push!(sign_changes, x1_sign_changes(view(tail, 1, :)))
    end

    return Dict(
        "tail_radius_mean_min" => minimum(tail_radius_means),
        "tail_radius_mean_max" => maximum(tail_radius_means),
        "tail_radius_std_max" => maximum(tail_radius_stds),
        "tail_x1_sign_changes_min" => minimum(sign_changes),
        "tail_x1_sign_changes_max" => maximum(sign_changes),
    )
end

## Split and window count summaries

function enrich_vanderpol_diagnostics!(
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

function vanderpol_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 20.0 &&
        diagnostics["velocity_norm_max"] < 80.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["tail_x1_sign_changes_min"] >= 1
end

function vanderpol_formal_passed(diagnostics::AbstractDict)
    return vanderpol_smoke_passed(diagnostics) &&
        diagnostics["mu_min"] >= 1.0 &&
        diagnostics["mu_max"] <= 3.0 &&
        diagnostics["mu_max"] > diagnostics["mu_min"]
end

## Diagnostic table assembly

function summarize_vanderpol_dataset(
    spec::VanDerPolUnforcedSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "mu" => spec.mu,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => vanderpol_all_finite(raw_trajectories),
        "state_norm_max" => vanderpol_state_norm_max(raw_trajectories),
        "velocity_norm_max" => vanderpol_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => vanderpol_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => vanderpol_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, vanderpol_state_range(raw_trajectories))
    merge!(diagnostics, vanderpol_mu_diagnostics(raw_trajectories))
    merge!(diagnostics, vanderpol_tail_oscillation_diagnostics(raw_trajectories))
    diagnostics["smoke_passed"] = vanderpol_smoke_passed(diagnostics)
    diagnostics["formal_passed"] = vanderpol_formal_passed(diagnostics)
    return diagnostics
end

function vanderpol_diagnostics_csv_row(
    spec::VanDerPolUnforcedSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "mu",
        "mu_min",
        "mu_max",
        "dt",
        "num_trajectories",
        "trajectory_length",
        "x1_min",
        "x1_max",
        "x2_min",
        "x2_max",
        "state_norm_max",
        "velocity_norm_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "tail_x1_sign_changes_min",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.mu,
        diagnostics["mu_min"],
        diagnostics["mu_max"],
        spec.dt,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["x1_min"],
        diagnostics["x1_max"],
        diagnostics["x2_min"],
        diagnostics["x2_max"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["tail_x1_sign_changes_min"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
