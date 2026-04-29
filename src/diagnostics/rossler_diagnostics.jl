## Diagnostic scope for Rossler trajectories

using LinearAlgebra
using Statistics

## Finite-value and array-size checks

function rossler_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function rossler_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

## State range diagnostics

function rossler_coordinate_values(raw_trajectories::AbstractVector{RawTrajectory}, index::Integer)
    return reduce(vcat, [vec(traj.state_matrix[index, :]) for traj in raw_trajectories])
end

function rossler_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    x_values = rossler_coordinate_values(raw_trajectories, 1)
    y_values = rossler_coordinate_values(raw_trajectories, 2)
    z_values = rossler_coordinate_values(raw_trajectories, 3)
    return Dict(
        "x_min" => minimum(x_values),
        "x_max" => maximum(x_values),
        "y_min" => minimum(y_values),
        "y_max" => maximum(y_values),
        "z_min" => minimum(z_values),
        "z_max" => maximum(z_values),
        "x_span" => maximum(x_values) - minimum(x_values),
        "y_span" => maximum(y_values) - minimum(y_values),
        "z_span" => maximum(z_values) - minimum(z_values),
    )
end

function rossler_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function rossler_velocity_norm_max(spec::RosslerSpec, raw_trajectories::AbstractVector{RawTrajectory})
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dx, dy, dz = rossler_rhs_components(
                spec.a,
                spec.b,
                spec.c,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
                traj.state_matrix[3, m],
            )
            max_velocity = max(max_velocity, norm([dx, dy, dz]))
        end
    end
    return max_velocity
end

function rossler_step_increment_summary(raw_trajectories::AbstractVector{RawTrajectory})
    increments = Float64[]
    for traj in raw_trajectories
        @inbounds for m in 1:(size(traj.state_matrix, 2) - 1)
            push!(increments, norm(view(traj.state_matrix, :, m + 1) .- view(traj.state_matrix, :, m)))
        end
    end
    return Dict(
        "step_increment_min" => minimum(increments),
        "step_increment_mean" => mean(increments),
        "step_increment_max" => maximum(increments),
    )
end

function rossler_rk4_self_residual_max(
    spec::RosslerSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_x, next_y, next_z = rk4_rossler_step(
                spec.a,
                spec.b,
                spec.c,
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
                traj.state_matrix[3, m],
            )
            residual = max(
                residual,
                norm([
                    traj.state_matrix[1, m + 1] - next_x,
                    traj.state_matrix[2, m + 1] - next_y,
                    traj.state_matrix[3, m + 1] - next_z,
                ]),
            )
        end
    end
    return residual
end

## Dissipativity and attractor statistics diagnostics

function rossler_divergence_statistics(spec::RosslerSpec, raw_trajectories::AbstractVector{RawTrajectory})
    values = Float64[]
    for traj in raw_trajectories
        append!(values, [rossler_divergence(spec, x) for x in view(traj.state_matrix, 1, :)])
    end
    return Dict(
        "divergence_min" => minimum(values),
        "divergence_mean" => mean(values),
        "divergence_max" => maximum(values),
        "is_mean_dissipative" => mean(values) < 0,
    )
end

function rossler_state_statistics(raw_trajectories::AbstractVector{RawTrajectory})
    X = hcat([traj.state_matrix for traj in raw_trajectories]...)
    covariance = cov(X; dims = 2)
    return Dict(
        "state_mean" => vec(mean(X; dims = 2)),
        "state_variance" => vec(var(X; dims = 2)),
        "state_covariance" => covariance,
    )
end

function rossler_revolve_count(values::AbstractVector{<:Real})
    count_crossings = 0
    previous = first(values)
    for value in values[2:end]
        if previous < 0 <= value
            count_crossings += 1
        end
        previous = value
    end
    return count_crossings
end

function rossler_attractor_geometry_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    x_spans = Float64[]
    y_spans = Float64[]
    z_spans = Float64[]
    y_crossings = Int[]
    for traj in raw_trajectories
        x_values = view(traj.state_matrix, 1, :)
        y_values = view(traj.state_matrix, 2, :)
        z_values = view(traj.state_matrix, 3, :)
        push!(x_spans, maximum(x_values) - minimum(x_values))
        push!(y_spans, maximum(y_values) - minimum(y_values))
        push!(z_spans, maximum(z_values) - minimum(z_values))
        push!(y_crossings, rossler_revolve_count(y_values))
    end
    return Dict(
        "x_span_by_trajectory" => x_spans,
        "y_span_by_trajectory" => y_spans,
        "z_span_by_trajectory" => z_spans,
        "y_positive_crossing_counts" => y_crossings,
        "max_y_positive_crossing_count" => maximum(y_crossings),
        "active_attractor_trajectory_count" => count(i -> x_spans[i] > 5.0 && y_spans[i] > 5.0 && z_spans[i] > 2.0, eachindex(x_spans)),
    )
end

## Split and window count diagnostics

function enrich_rossler_diagnostics!(
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

function rossler_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 80.0 &&
        diagnostics["velocity_norm_max"] < 2000.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["is_mean_dissipative"] &&
        diagnostics["z_min"] > -2.0 &&
        diagnostics["z_max"] < 80.0 &&
        diagnostics["x_span"] > 5.0 &&
        diagnostics["y_span"] > 5.0 &&
        diagnostics["z_span"] > 2.0 &&
        diagnostics["active_attractor_trajectory_count"] >= 1
end

function rossler_standard_passed(diagnostics::AbstractDict)
    return rossler_smoke_passed(diagnostics) &&
        diagnostics["num_trajectories"] >= 48 &&
        diagnostics["trajectory_length"] >= 4000 &&
        diagnostics["active_attractor_trajectory_count"] >= 24 &&
        diagnostics["max_y_positive_crossing_count"] >= 8
end

## Diagnostic table assembly

function summarize_rossler_dataset(
    spec::RosslerSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "a" => spec.a,
        "b" => spec.b,
        "c" => spec.c,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => rossler_all_finite(raw_trajectories),
        "state_norm_max" => rossler_state_norm_max(raw_trajectories),
        "velocity_norm_max" => rossler_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => rossler_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => rossler_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, rossler_state_range(raw_trajectories))
    merge!(diagnostics, rossler_state_statistics(raw_trajectories))
    merge!(diagnostics, rossler_step_increment_summary(raw_trajectories))
    merge!(diagnostics, rossler_divergence_statistics(spec, raw_trajectories))
    merge!(diagnostics, rossler_attractor_geometry_diagnostics(raw_trajectories))
    diagnostics["smoke_passed"] = rossler_smoke_passed(diagnostics)
    diagnostics["standard_passed"] = rossler_standard_passed(diagnostics)
    diagnostics["formal_passed"] = diagnostics["standard_passed"]
    return diagnostics
end

function rossler_diagnostics_csv_row(
    spec::RosslerSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "a",
        "b",
        "c",
        "dt",
        "burn_in_time",
        "num_trajectories",
        "trajectory_length",
        "x_min",
        "x_max",
        "y_min",
        "y_max",
        "z_min",
        "z_max",
        "state_norm_max",
        "velocity_norm_max",
        "step_increment_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "divergence_mean",
        "active_attractor_trajectory_count",
        "max_y_positive_crossing_count",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.a,
        spec.b,
        spec.c,
        spec.dt,
        spec.burn_in_time,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["x_min"],
        diagnostics["x_max"],
        diagnostics["y_min"],
        diagnostics["y_max"],
        diagnostics["z_min"],
        diagnostics["z_max"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["step_increment_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["divergence_mean"],
        diagnostics["active_attractor_trajectory_count"],
        diagnostics["max_y_positive_crossing_count"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
