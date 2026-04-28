## Diagnostic scope for Duffing trajectories

using LinearAlgebra
using Statistics

## Full-state and finite-value checks

function duffing_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function duffing_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

## Compute trajectory-wise energy sequences

function duffing_energy_sequence(spec::DuffingUnforcedDoubleWellSpec, traj::RawTrajectory)
    return [
        duffing_total_energy(spec, traj.state_matrix[1, m], traj.state_matrix[2, m])
        for m in axes(traj.state_matrix, 2)
    ]
end

function duffing_energy_diagnostics(
    spec::DuffingUnforcedDoubleWellSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    initial_energies = Float64[]
    final_energies = Float64[]
    max_positive_jumps = Float64[]
    positive_jump_counts = Int[]
    mean_energy_drops = Float64[]

    for traj in raw_trajectories
        energies = duffing_energy_sequence(spec, traj)
        diffs = diff(energies)
        push!(initial_energies, first(energies))
        push!(final_energies, last(energies))
        push!(max_positive_jumps, maximum(max.(diffs, 0.0)))
        push!(positive_jump_counts, count(>(1e-10), diffs))
        push!(mean_energy_drops, mean(-diffs))
    end

    return Dict(
        "energy_initial_min" => minimum(initial_energies),
        "energy_initial_max" => maximum(initial_energies),
        "energy_final_min" => minimum(final_energies),
        "energy_final_max" => maximum(final_energies),
        "energy_drop_min" => minimum(initial_energies .- final_energies),
        "energy_drop_max" => maximum(initial_energies .- final_energies),
        "mean_energy_drop_mean" => mean(mean_energy_drops),
        "max_positive_energy_jump" => maximum(max_positive_jumps),
        "positive_energy_jump_count_total" => sum(positive_jump_counts),
    )
end

## Classify well membership and coverage

function duffing_well_label(q::Real; barrier_tol::Real = 0.05)
    if q < -barrier_tol
        return "left"
    elseif q > barrier_tol
        return "right"
    else
        return "near_barrier"
    end
end

function duffing_well_counts(labels::AbstractVector{<:AbstractString})
    return Dict(
        "left" => count(==("left"), labels),
        "right" => count(==("right"), labels),
        "near_barrier" => count(==("near_barrier"), labels),
    )
end

function duffing_well_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    initial_labels = [
        duffing_well_label(traj.initial_condition_instance[1])
        for traj in raw_trajectories
    ]
    final_labels = [
        duffing_well_label(traj.state_matrix[1, end])
        for traj in raw_trajectories
    ]

    return Dict(
        "initial_well_counts" => duffing_well_counts(initial_labels),
        "final_well_counts" => duffing_well_counts(final_labels),
        "initial_well_labels" => initial_labels,
        "final_well_labels" => final_labels,
    )
end

## Summarize state ranges and trajectory statistics

function duffing_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    q_values = reduce(vcat, [vec(traj.state_matrix[1, :]) for traj in raw_trajectories])
    v_values = reduce(vcat, [vec(traj.state_matrix[2, :]) for traj in raw_trajectories])
    return Dict(
        "q_min" => minimum(q_values),
        "q_max" => maximum(q_values),
        "v_min" => minimum(v_values),
        "v_max" => maximum(v_values),
    )
end

function duffing_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function duffing_velocity_norm_max(
    spec::DuffingUnforcedDoubleWellSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dq, dv = duffing_rhs_components(
                spec.delta,
                spec.alpha,
                spec.beta,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            max_velocity = max(max_velocity, norm([dq, dv]))
        end
    end
    return max_velocity
end

## Check RK4 self consistency

function duffing_rk4_self_residual_max(
    spec::DuffingUnforcedDoubleWellSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_q, next_v = rk4_duffing_step(
                spec.delta,
                spec.alpha,
                spec.beta,
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_q, traj.state_matrix[2, m + 1] - next_v]),
            )
        end
    end
    return residual
end

## Split and window count summaries

function enrich_duffing_diagnostics!(
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

function duffing_smoke_passed(diagnostics::AbstractDict)
    final_counts = diagnostics["final_well_counts"]
    initial_counts = diagnostics["initial_well_counts"]
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 10.0 &&
        diagnostics["velocity_norm_max"] < 20.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["max_positive_energy_jump"] <= 1e-7 &&
        initial_counts["left"] >= 1 &&
        initial_counts["right"] >= 1 &&
        initial_counts["near_barrier"] >= 1 &&
        final_counts["left"] >= 1 &&
        final_counts["right"] >= 1
end

## Diagnostic table assembly

function summarize_duffing_dataset(
    spec::DuffingUnforcedDoubleWellSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => duffing_all_finite(raw_trajectories),
        "state_norm_max" => duffing_state_norm_max(raw_trajectories),
        "velocity_norm_max" => duffing_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => duffing_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => duffing_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, duffing_state_range(raw_trajectories))
    merge!(diagnostics, duffing_energy_diagnostics(spec, raw_trajectories))
    merge!(diagnostics, duffing_well_diagnostics(raw_trajectories))
    diagnostics["smoke_passed"] = duffing_smoke_passed(diagnostics)
    return diagnostics
end

function duffing_diagnostics_csv_row(
    spec::DuffingUnforcedDoubleWellSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "delta",
        "alpha",
        "beta",
        "dt",
        "num_trajectories",
        "trajectory_length",
        "q_min",
        "q_max",
        "v_min",
        "v_max",
        "state_norm_max",
        "velocity_norm_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "max_positive_energy_jump",
        "positive_energy_jump_count_total",
        "energy_drop_min",
        "left_well_count",
        "right_well_count",
        "near_barrier_count",
        "smoke_passed",
    ]
    final_counts = diagnostics["final_well_counts"]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.delta,
        spec.alpha,
        spec.beta,
        spec.dt,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["q_min"],
        diagnostics["q_max"],
        diagnostics["v_min"],
        diagnostics["v_max"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["max_positive_energy_jump"],
        diagnostics["positive_energy_jump_count_total"],
        diagnostics["energy_drop_min"],
        final_counts["left"],
        final_counts["right"],
        final_counts["near_barrier"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
