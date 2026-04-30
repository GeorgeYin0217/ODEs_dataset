## Energy drift diagnostics

using LinearAlgebra
using Statistics

function pendulum_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function pendulum_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

function pendulum_energy_sequence(
    spec::NonlinearPendulumLusch2018Spec,
    traj::RawTrajectory,
)
    return [
        nonlinear_pendulum_hamiltonian(traj.state_matrix[1, m], traj.state_matrix[2, m])
        for m in axes(traj.state_matrix, 2)
    ]
end

function pendulum_energy_diagnostics(
    spec::NonlinearPendulumLusch2018Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    initial_energies = Float64[]
    max_abs_drifts = Float64[]
    max_energies = Float64[]

    for traj in raw_trajectories
        energies = pendulum_energy_sequence(spec, traj)
        initial_energy = first(energies)
        push!(initial_energies, initial_energy)
        push!(max_abs_drifts, maximum(abs.(energies .- initial_energy)))
        push!(max_energies, maximum(energies))
    end

    sorted_drifts = sort(max_abs_drifts)
    p95_index = max(1, ceil(Int, 0.95 * length(sorted_drifts)))
    return Dict(
        "initial_energy_min" => minimum(initial_energies),
        "initial_energy_max" => maximum(initial_energies),
        "initial_energy_mean" => mean(initial_energies),
        "initial_energy_std" => std(initial_energies),
        "max_energy_seen" => maximum(max_energies),
        "energy_drift_max" => maximum(max_abs_drifts),
        "energy_drift_mean" => mean(max_abs_drifts),
        "energy_drift_p95" => sorted_drifts[p95_index],
        "separatrix_violation_count" => count(>=(1.0), max_energies),
    )
end

## Initial-energy distribution diagnostics

function pendulum_energy_band_counts(raw_trajectories::AbstractVector{RawTrajectory})
    energies = [
        nonlinear_pendulum_hamiltonian(traj.initial_condition_instance[1], traj.initial_condition_instance[2])
        for traj in raw_trajectories
    ]
    return Dict(
        "low_energy_count" => count(<(-0.5), energies),
        "mid_energy_count" => count(energy -> -0.5 <= energy < 0.5, energies),
        "high_energy_count" => count(energy -> 0.5 <= energy < 0.99, energies),
        "near_separatrix_count" => count(energy -> 0.9 <= energy < 0.99, energies),
    )
end

## Phase-portrait coverage diagnostics

function pendulum_coordinate_values(raw_trajectories::AbstractVector{RawTrajectory}, index::Integer)
    return reduce(vcat, [vec(traj.state_matrix[index, :]) for traj in raw_trajectories])
end

function pendulum_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    x1_values = pendulum_coordinate_values(raw_trajectories, 1)
    x2_values = pendulum_coordinate_values(raw_trajectories, 2)
    return Dict(
        "x1_min" => minimum(x1_values),
        "x1_max" => maximum(x1_values),
        "x2_min" => minimum(x2_values),
        "x2_max" => maximum(x2_values),
    )
end

function pendulum_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function pendulum_velocity_norm_max(
    spec::NonlinearPendulumLusch2018Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dx1, dx2 = nonlinear_pendulum_rhs_components(
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            max_velocity = max(max_velocity, norm([dx1, dx2]))
        end
    end
    return max_velocity
end

## Small-amplitude degeneracy checks

function pendulum_small_amplitude_count(
    raw_trajectories::AbstractVector{RawTrajectory};
    angle_threshold::Real = 0.35,
    velocity_threshold::Real = 0.35,
)
    return count(raw_trajectories) do traj
        abs(traj.initial_condition_instance[1]) <= angle_threshold &&
            abs(traj.initial_condition_instance[2]) <= velocity_threshold
    end
end

## Separatrix proximity checks

function pendulum_rk4_self_residual_max(
    spec::NonlinearPendulumLusch2018Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:pendulum_transition_count(spec)
            next_x1, next_x2 = rk4_nonlinear_pendulum_step(
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_x1, traj.state_matrix[2, m + 1] - next_x2]),
            )
        end
    end
    return residual
end

## Split and window count summaries

function enrich_pendulum_diagnostics!(
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

## Pendulum summary table construction

function pendulum_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_matrix_size"] == [2, 51] &&
        diagnostics["state_norm_max"] < 4.0 &&
        diagnostics["velocity_norm_max"] < 3.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["initial_energy_max"] < 0.99 &&
        diagnostics["separatrix_violation_count"] == 0 &&
        diagnostics["energy_drift_max"] <= 1e-8 &&
        diagnostics["low_energy_count"] >= 1 &&
        diagnostics["mid_energy_count"] >= 1 &&
        diagnostics["high_energy_count"] >= 1 &&
        diagnostics["small_amplitude_initial_count"] < diagnostics["num_trajectories"] ÷ 2
end

function pendulum_medium_passed(diagnostics::AbstractDict)
    return pendulum_smoke_passed(diagnostics) &&
        diagnostics["num_trajectories"] >= 512 &&
        diagnostics["transition_count"] == 50 &&
        diagnostics["low_energy_count"] >= 20 &&
        diagnostics["mid_energy_count"] >= 20 &&
        diagnostics["high_energy_count"] >= 20 &&
        diagnostics["near_separatrix_count"] >= 5
end

function summarize_pendulum_dataset(
    spec::NonlinearPendulumLusch2018Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    sampling_statistics::AbstractDict,
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "transition_count" => pendulum_transition_count(spec),
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => pendulum_all_finite(raw_trajectories),
        "state_norm_max" => pendulum_state_norm_max(raw_trajectories),
        "velocity_norm_max" => pendulum_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => pendulum_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => pendulum_full_state_observation_error(observed_trajectories),
        "small_amplitude_initial_count" => pendulum_small_amplitude_count(raw_trajectories),
        "sampling_statistics" => sampling_statistics,
        "acceptance_rate" => sampling_statistics["acceptance_rate"],
    )

    merge!(diagnostics, pendulum_state_range(raw_trajectories))
    merge!(diagnostics, pendulum_energy_diagnostics(spec, raw_trajectories))
    merge!(diagnostics, pendulum_energy_band_counts(raw_trajectories))
    diagnostics["smoke_passed"] = pendulum_smoke_passed(diagnostics)
    diagnostics["medium_passed"] = pendulum_medium_passed(diagnostics)
    return diagnostics
end

function pendulum_diagnostics_csv_row(
    spec::NonlinearPendulumLusch2018Spec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "dt",
        "num_trajectories",
        "trajectory_length",
        "transition_count",
        "x1_min",
        "x1_max",
        "x2_min",
        "x2_max",
        "initial_energy_min",
        "initial_energy_max",
        "initial_energy_mean",
        "energy_drift_max",
        "energy_drift_mean",
        "separatrix_violation_count",
        "acceptance_rate",
        "low_energy_count",
        "mid_energy_count",
        "high_energy_count",
        "near_separatrix_count",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.dt,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["transition_count"],
        diagnostics["x1_min"],
        diagnostics["x1_max"],
        diagnostics["x2_min"],
        diagnostics["x2_max"],
        diagnostics["initial_energy_min"],
        diagnostics["initial_energy_max"],
        diagnostics["initial_energy_mean"],
        diagnostics["energy_drift_max"],
        diagnostics["energy_drift_mean"],
        diagnostics["separatrix_violation_count"],
        diagnostics["acceptance_rate"],
        diagnostics["low_energy_count"],
        diagnostics["mid_energy_count"],
        diagnostics["high_energy_count"],
        diagnostics["near_separatrix_count"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
