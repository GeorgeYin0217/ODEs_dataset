## Diagnostic scope for FitzHugh-Nagumo trajectories

using LinearAlgebra
using Statistics

## Full-state and finite-value checks

function fitzhugh_nagumo_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function fitzhugh_nagumo_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

## Equilibrium, state-range, and vector-field diagnostics

function fitzhugh_nagumo_equilibrium_diagnostics(spec::FitzHughNagumoSpec)
    equilibria = fitzhugh_nagumo_equilibria(spec)
    residuals = [fitzhugh_nagumo_equilibrium_residual(spec, eq) for eq in equilibria]
    return Dict(
        "equilibrium_count" => length(equilibria),
        "equilibria" => equilibria,
        "equilibrium_residual_max" => isempty(residuals) ? Inf : maximum(residuals),
        "equilibrium_jacobian_traces" => [tr(fitzhugh_nagumo_jacobian(spec, eq)) for eq in equilibria],
        "equilibrium_jacobian_determinants" => [det(fitzhugh_nagumo_jacobian(spec, eq)) for eq in equilibria],
    )
end

function fitzhugh_nagumo_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    v_values = reduce(vcat, [vec(traj.state_matrix[1, :]) for traj in raw_trajectories])
    w_values = reduce(vcat, [vec(traj.state_matrix[2, :]) for traj in raw_trajectories])
    return Dict(
        "v_min" => minimum(v_values),
        "v_max" => maximum(v_values),
        "w_min" => minimum(w_values),
        "w_max" => maximum(w_values),
    )
end

function fitzhugh_nagumo_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function fitzhugh_nagumo_velocity_norm_max(
    spec::FitzHughNagumoSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dv, dw = fitzhugh_nagumo_rhs_components(
                spec.a,
                spec.b,
                spec.epsilon,
                spec.I,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            max_velocity = max(max_velocity, norm([dv, dw]))
        end
    end
    return max_velocity
end

function fitzhugh_nagumo_rk4_self_residual_max(
    spec::FitzHughNagumoSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_v, next_w = rk4_fitzhugh_nagumo_step(
                spec.a,
                spec.b,
                spec.epsilon,
                spec.I,
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
            )
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_v, traj.state_matrix[2, m + 1] - next_w]),
            )
        end
    end
    return residual
end

## Spike and excursion diagnostics

function count_upward_threshold_crossings(values::AbstractVector{<:Real}, threshold::Real)
    crossings = 0
    previous = first(values)
    for value in values[2:end]
        if previous < threshold && value >= threshold
            crossings += 1
        end
        previous = value
    end
    return crossings
end

function fitzhugh_nagumo_excursion_diagnostics(
    raw_trajectories::AbstractVector{RawTrajectory};
    threshold::Real = 1.0,
)
    v_max_values = Float64[]
    v_min_values = Float64[]
    w_max_values = Float64[]
    w_min_values = Float64[]
    crossing_counts = Int[]

    for traj in raw_trajectories
        v = view(traj.state_matrix, 1, :)
        w = view(traj.state_matrix, 2, :)
        push!(v_max_values, maximum(v))
        push!(v_min_values, minimum(v))
        push!(w_max_values, maximum(w))
        push!(w_min_values, minimum(w))
        push!(crossing_counts, count_upward_threshold_crossings(v, threshold))
    end

    return Dict(
        "spike_threshold" => Float64(threshold),
        "v_peak_min" => minimum(v_max_values),
        "v_peak_max" => maximum(v_max_values),
        "v_trough_min" => minimum(v_min_values),
        "v_trough_max" => maximum(v_min_values),
        "w_peak_min" => minimum(w_max_values),
        "w_peak_max" => maximum(w_max_values),
        "w_trough_min" => minimum(w_min_values),
        "w_trough_max" => maximum(w_min_values),
        "threshold_crossing_counts" => crossing_counts,
        "excursion_trajectory_count" => count(>(0), crossing_counts),
        "max_threshold_crossings" => maximum(crossing_counts),
    )
end

## Split and window count summaries

function enrich_fitzhugh_nagumo_diagnostics!(
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

function fitzhugh_nagumo_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 20.0 &&
        diagnostics["velocity_norm_max"] < 20.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["equilibrium_count"] >= 1 &&
        diagnostics["equilibrium_residual_max"] <= 1e-10 &&
        diagnostics["excursion_trajectory_count"] >= 4 &&
        diagnostics["v_peak_max"] > 1.4 &&
        diagnostics["v_trough_min"] < -1.5
end

function fitzhugh_nagumo_formal_passed(diagnostics::AbstractDict)
    return fitzhugh_nagumo_smoke_passed(diagnostics) &&
        diagnostics["num_trajectories"] >= 48 &&
        diagnostics["trajectory_length"] >= 6000 &&
        diagnostics["excursion_trajectory_count"] >= 16
end

## Diagnostic table assembly

function summarize_fitzhugh_nagumo_dataset(
    spec::FitzHughNagumoSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "a" => spec.a,
        "b" => spec.b,
        "epsilon" => spec.epsilon,
        "I" => spec.I,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => fitzhugh_nagumo_all_finite(raw_trajectories),
        "state_norm_max" => fitzhugh_nagumo_state_norm_max(raw_trajectories),
        "velocity_norm_max" => fitzhugh_nagumo_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => fitzhugh_nagumo_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => fitzhugh_nagumo_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, fitzhugh_nagumo_equilibrium_diagnostics(spec))
    merge!(diagnostics, fitzhugh_nagumo_state_range(raw_trajectories))
    merge!(diagnostics, fitzhugh_nagumo_excursion_diagnostics(raw_trajectories))
    diagnostics["smoke_passed"] = fitzhugh_nagumo_smoke_passed(diagnostics)
    diagnostics["formal_passed"] = fitzhugh_nagumo_formal_passed(diagnostics)
    return diagnostics
end

function fitzhugh_nagumo_diagnostics_csv_row(
    spec::FitzHughNagumoSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "a",
        "b",
        "epsilon",
        "I",
        "dt",
        "num_trajectories",
        "trajectory_length",
        "v_min",
        "v_max",
        "w_min",
        "w_max",
        "state_norm_max",
        "velocity_norm_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "equilibrium_count",
        "equilibrium_residual_max",
        "excursion_trajectory_count",
        "max_threshold_crossings",
        "smoke_passed",
        "formal_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.a,
        spec.b,
        spec.epsilon,
        spec.I,
        spec.dt,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["v_min"],
        diagnostics["v_max"],
        diagnostics["w_min"],
        diagnostics["w_max"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["equilibrium_count"],
        diagnostics["equilibrium_residual_max"],
        diagnostics["excursion_trajectory_count"],
        diagnostics["max_threshold_crossings"],
        diagnostics["smoke_passed"],
        diagnostics["formal_passed"],
    ]
    return columns, values
end
