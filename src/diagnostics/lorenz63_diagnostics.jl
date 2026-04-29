## Diagnostic scope for Lorenz '63 trajectories

using LinearAlgebra
using Statistics

## Finite-value and array-size checks

function lorenz63_full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

function lorenz63_all_finite(raw_trajectories::AbstractVector{RawTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix), raw_trajectories)
end

## State range diagnostics

function lorenz63_coordinate_values(raw_trajectories::AbstractVector{RawTrajectory}, index::Integer)
    return reduce(vcat, [vec(traj.state_matrix[index, :]) for traj in raw_trajectories])
end

function lorenz63_state_range(raw_trajectories::AbstractVector{RawTrajectory})
    x_values = lorenz63_coordinate_values(raw_trajectories, 1)
    y_values = lorenz63_coordinate_values(raw_trajectories, 2)
    z_values = lorenz63_coordinate_values(raw_trajectories, 3)
    return Dict(
        "x_min" => minimum(x_values),
        "x_max" => maximum(x_values),
        "y_min" => minimum(y_values),
        "y_max" => maximum(y_values),
        "z_min" => minimum(z_values),
        "z_max" => maximum(z_values),
    )
end

function lorenz63_state_norm_max(raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

function lorenz63_velocity_norm_max(spec::Lorenz63Spec, raw_trajectories::AbstractVector{RawTrajectory})
    max_velocity = 0.0
    for traj in raw_trajectories
        @inbounds for m in axes(traj.state_matrix, 2)
            dx, dy, dz = lorenz63_rhs_components(
                spec.sigma,
                spec.rho,
                spec.beta,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
                traj.state_matrix[3, m],
            )
            max_velocity = max(max_velocity, norm([dx, dy, dz]))
        end
    end
    return max_velocity
end

function lorenz63_rk4_self_residual_max(
    spec::Lorenz63Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        @inbounds for m in 1:spec.trajectory_length
            next_x, next_y, next_z = rk4_lorenz63_step(
                spec.sigma,
                spec.rho,
                spec.beta,
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

function lorenz63_equilibrium_diagnostics(spec::Lorenz63Spec)
    equilibria = lorenz63_equilibria(spec)
    residuals = [lorenz63_equilibrium_residual(spec, eq) for eq in equilibria]
    return Dict(
        "equilibrium_count" => length(equilibria),
        "equilibria" => equilibria,
        "equilibrium_residual_max" => maximum(residuals),
        "equilibrium_jacobian_traces" => [tr(lorenz63_jacobian(spec, eq)) for eq in equilibria],
        "equilibrium_jacobian_determinants" => [det(lorenz63_jacobian(spec, eq)) for eq in equilibria],
        "divergence" => lorenz63_divergence(spec),
        "is_dissipative" => lorenz63_divergence(spec) < 0,
    )
end

function lorenz63_state_statistics(raw_trajectories::AbstractVector{RawTrajectory})
    X = hcat([traj.state_matrix for traj in raw_trajectories]...)
    covariance = cov(X; dims = 2)
    return Dict(
        "state_mean" => vec(mean(X; dims = 2)),
        "state_variance" => vec(var(X; dims = 2)),
        "state_covariance" => covariance,
    )
end

function lorenz63_wing_switch_count(values::AbstractVector{<:Real}; threshold::Real = 1.0)
    labels = Int[]
    for value in values
        if value > threshold
            push!(labels, 1)
        elseif value < -threshold
            push!(labels, -1)
        end
    end
    isempty(labels) && return 0

    switches = 0
    previous = first(labels)
    for label in labels[2:end]
        if label != previous
            switches += 1
            previous = label
        end
    end
    return switches
end

function lorenz63_wing_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    x_minima = Float64[]
    x_maxima = Float64[]
    switch_counts = Int[]
    for traj in raw_trajectories
        x_values = view(traj.state_matrix, 1, :)
        push!(x_minima, minimum(x_values))
        push!(x_maxima, maximum(x_values))
        push!(switch_counts, lorenz63_wing_switch_count(x_values))
    end
    return Dict(
        "x_min_by_trajectory" => x_minima,
        "x_max_by_trajectory" => x_maxima,
        "wing_switch_counts" => switch_counts,
        "double_wing_trajectory_count" => count(i -> x_minima[i] < -1.0 && x_maxima[i] > 1.0, eachindex(x_minima)),
        "max_wing_switch_count" => maximum(switch_counts),
    )
end

function lorenz63_short_separation_diagnostics(raw_trajectories::AbstractVector{RawTrajectory})
    length(raw_trajectories) >= 2 ||
        return Dict("separation_initial" => 0.0, "separation_final" => 0.0, "separation_growth" => 0.0)
    first_traj = raw_trajectories[1]
    second_traj = raw_trajectories[2]
    initial_distance = norm(first_traj.state_matrix[:, 1] - second_traj.state_matrix[:, 1])
    final_index = min(size(first_traj.state_matrix, 2), 301)
    final_distance = norm(first_traj.state_matrix[:, final_index] - second_traj.state_matrix[:, final_index])
    return Dict(
        "separation_initial" => initial_distance,
        "separation_final_t3" => final_distance,
        "separation_growth_t3" => final_distance / max(initial_distance, eps(Float64)),
    )
end

## Split and window count diagnostics

function enrich_lorenz63_diagnostics!(
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

function lorenz63_smoke_passed(diagnostics::AbstractDict)
    return diagnostics["all_states_finite"] &&
        diagnostics["full_state_observation_error_max"] <= 1e-12 &&
        diagnostics["state_norm_max"] < 80.0 &&
        diagnostics["velocity_norm_max"] < 2000.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        diagnostics["is_dissipative"] &&
        diagnostics["equilibrium_count"] == 3 &&
        diagnostics["equilibrium_residual_max"] <= 1e-10 &&
        diagnostics["z_min"] > -5.0 &&
        diagnostics["z_max"] < 60.0 &&
        diagnostics["double_wing_trajectory_count"] >= 1
end

function lorenz63_formal_passed(diagnostics::AbstractDict)
    return lorenz63_smoke_passed(diagnostics) &&
        diagnostics["num_trajectories"] >= 48 &&
        diagnostics["trajectory_length"] >= 4000 &&
        diagnostics["double_wing_trajectory_count"] >= 24 &&
        diagnostics["max_wing_switch_count"] >= 2
end

## Diagnostic table assembly

function summarize_lorenz63_dataset(
    spec::Lorenz63Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "sigma" => spec.sigma,
        "rho" => spec.rho,
        "beta" => spec.beta,
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "tspan" => collect(spec.tspan),
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "all_states_finite" => lorenz63_all_finite(raw_trajectories),
        "state_norm_max" => lorenz63_state_norm_max(raw_trajectories),
        "velocity_norm_max" => lorenz63_velocity_norm_max(spec, raw_trajectories),
        "rk4_self_residual_max" => lorenz63_rk4_self_residual_max(spec, raw_trajectories),
        "full_state_observation_error_max" => lorenz63_full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, lorenz63_equilibrium_diagnostics(spec))
    merge!(diagnostics, lorenz63_state_range(raw_trajectories))
    merge!(diagnostics, lorenz63_state_statistics(raw_trajectories))
    merge!(diagnostics, lorenz63_wing_diagnostics(raw_trajectories))
    merge!(diagnostics, lorenz63_short_separation_diagnostics(raw_trajectories))
    diagnostics["smoke_passed"] = lorenz63_smoke_passed(diagnostics)
    diagnostics["formal_passed"] = lorenz63_formal_passed(diagnostics)
    diagnostics["standard_passed"] = diagnostics["formal_passed"]
    return diagnostics
end

function lorenz63_diagnostics_csv_row(
    spec::Lorenz63Spec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "sigma",
        "rho",
        "beta",
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
        "rk4_self_residual_max",
        "full_state_observation_error_max",
        "divergence",
        "equilibrium_count",
        "double_wing_trajectory_count",
        "max_wing_switch_count",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.sigma,
        spec.rho,
        spec.beta,
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
        diagnostics["rk4_self_residual_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["divergence"],
        diagnostics["equilibrium_count"],
        diagnostics["double_wing_trajectory_count"],
        diagnostics["max_wing_switch_count"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
