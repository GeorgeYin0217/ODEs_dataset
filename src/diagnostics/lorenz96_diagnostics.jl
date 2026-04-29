## Diagnostic scope for Lorenz96 trajectories

using LinearAlgebra
using Statistics

## Validate trajectory array shapes

function lorenz96_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function lorenz96_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

function lorenz96_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function lorenz96_velocity_norm_max(spec::Lorenz96Spec, raw_trajectories::AbstractVector{RawTrajectory})
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            max_velocity = max(max_velocity, norm(lorenz96_vector_field(spec, view(traj.state_matrix, :, m))))
        end
    end
    return max_velocity
end

function lorenz96_rk4_self_residual_max(
    spec::Lorenz96Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_x = rk4_lorenz96_step(spec.F, spec.dt, view(traj.state_matrix, :, m))
            residual = max(residual, norm(view(traj.state_matrix, :, m + 1) .- next_x))
        end
    end
    return residual
end

## Compute coordinate-wise summary statistics

function lorenz96_state_statistics(raw_trajectories::AbstractVector{RawTrajectory})
    X = hcat([traj.state_matrix for traj in raw_trajectories]...)
    means = vec(mean(X; dims = 2))
    variances = vec(var(X; dims = 2))
    covariance = cov(X; dims = 2)
    return Dict(
        "state_min" => minimum(X),
        "state_max" => maximum(X),
        "state_span" => maximum(X) - minimum(X),
        "coordinate_mean" => means,
        "coordinate_variance" => variances,
        "coordinate_mean_min" => minimum(means),
        "coordinate_mean_max" => maximum(means),
        "coordinate_mean_range" => maximum(means) - minimum(means),
        "coordinate_variance_min" => minimum(variances),
        "coordinate_variance_max" => maximum(variances),
        "coordinate_variance_range" => maximum(variances) - minimum(variances),
        "state_covariance" => covariance,
    )
end

## Compute spatial mean variance and energy-like quantities

function lorenz96_energy_summary(raw_trajectories::AbstractVector{RawTrajectory})
    energies = Float64[]
    spatial_means = Float64[]
    step_increments = Float64[]
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            x = view(traj.state_matrix, :, m)
            push!(energies, sum(abs2, x) / length(x))
            push!(spatial_means, mean(x))
        end
        @inbounds for m in 1:(size(traj.state_matrix, 2) - 1)
            push!(step_increments, norm(view(traj.state_matrix, :, m + 1) .- view(traj.state_matrix, :, m)))
        end
    end
    return Dict(
        "energy_min" => minimum(energies),
        "energy_mean" => mean(energies),
        "energy_max" => maximum(energies),
        "spatial_mean_min" => minimum(spatial_means),
        "spatial_mean_mean" => mean(spatial_means),
        "spatial_mean_max" => maximum(spatial_means),
        "step_increment_min" => minimum(step_increments),
        "step_increment_mean" => mean(step_increments),
        "step_increment_max" => maximum(step_increments),
    )
end

function lorenz96_cross_trajectory_statistics(raw_trajectories::AbstractVector{RawTrajectory})
    energy_means = Float64[]
    variance_means = Float64[]
    state_spans = Float64[]
    for traj in raw_trajectories
        X = traj.state_matrix
        push!(energy_means, mean(sum(abs2, view(X, :, m)) / size(X, 1) for m in axes(X, 2)))
        push!(variance_means, mean(vec(var(X; dims = 2))))
        push!(state_spans, maximum(X) - minimum(X))
    end
    return Dict(
        "energy_mean_by_trajectory" => energy_means,
        "variance_mean_by_trajectory" => variance_means,
        "state_span_by_trajectory" => state_spans,
        "active_trajectory_count" => count(i -> energy_means[i] > 1.0 && state_spans[i] > 1.0, eachindex(energy_means)),
    )
end

## Split and window count diagnostics

function enrich_lorenz96_diagnostics!(
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

function lorenz96_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["boundary_index_check_passed"] &&
        diagnostics["uniform_state_residual"] <= 1e-10 &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 300.0 &&
        diagnostics["velocity_norm_max"] < 10000.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["state_span"] > 1.0 &&
        diagnostics["energy_mean"] > 1.0 &&
        diagnostics["active_trajectory_count"] >= 1
end

function lorenz96_standard_passed(diagnostics::AbstractDict)
    return lorenz96_smoke_passed(diagnostics) &&
        diagnostics["num_trajectories"] >= 48 &&
        diagnostics["trajectory_length"] >= 4000 &&
        diagnostics["active_trajectory_count"] >= 24 &&
        diagnostics["state_span"] > 5.0 &&
        diagnostics["coordinate_variance_max"] > 1.0
end

## Diagnostic table assembly

function summarize_lorenz96_dataset(
    spec::Lorenz96Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    boundary_passed = try
        validate_lorenz96_boundary_indices(spec)
        true
    catch
        false
    end

    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "F" => spec.F,
        "state_dim" => spec.state_dim,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => lorenz96_all_finite(raw_trajectories),
        "boundary_index_check_passed" => boundary_passed,
        "uniform_state_residual" => lorenz96_uniform_residual(spec),
        "divergence" => lorenz96_divergence(spec),
        "state_norm_max" => lorenz96_state_norm_max(raw_trajectories),
        "velocity_norm_max" => lorenz96_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => lorenz96_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => lorenz96_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, lorenz96_state_statistics(raw_trajectories))
    merge!(diagnostics, lorenz96_energy_summary(raw_trajectories))
    merge!(diagnostics, lorenz96_cross_trajectory_statistics(raw_trajectories))
    diagnostics["smoke_passed"] = lorenz96_smoke_passed(diagnostics)
    diagnostics["standard_passed"] = lorenz96_standard_passed(diagnostics)
    diagnostics["formal_passed"] = diagnostics["standard_passed"]
    return diagnostics
end

function lorenz96_diagnostics_csv_row(
    spec::Lorenz96Spec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "state_dim",
        "F",
        "dt",
        "burn_in_time",
        "num_trajectories",
        "trajectory_length",
        "state_min",
        "state_max",
        "state_span",
        "state_norm_max",
        "velocity_norm_max",
        "step_increment_max",
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "uniform_state_residual",
        "energy_mean",
        "coordinate_mean_range",
        "coordinate_variance_range",
        "active_trajectory_count",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.state_dim,
        spec.F,
        spec.dt,
        spec.burn_in_time,
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["state_min"],
        diagnostics["state_max"],
        diagnostics["state_span"],
        diagnostics["state_norm_max"],
        diagnostics["velocity_norm_max"],
        diagnostics["step_increment_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["uniform_state_residual"],
        diagnostics["energy_mean"],
        diagnostics["coordinate_mean_range"],
        diagnostics["coordinate_variance_range"],
        diagnostics["active_trajectory_count"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
