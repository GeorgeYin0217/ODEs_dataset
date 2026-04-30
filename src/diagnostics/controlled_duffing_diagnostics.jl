## Data scale and dimension diagnostics

using LinearAlgebra
using Statistics

function controlled_duffing_rms_value(A::AbstractArray{<:Real})
    return sqrt(mean(abs2, Float64.(A)))
end

function controlled_duffing_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    tensor = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        tensor[:, :, q] = matrix
    end
    return tensor
end

function controlled_duffing_all_finite(raw_trajectories::AbstractVector{RawControlledTrajectory})
    return all(traj -> all(isfinite, traj.state_matrix) && all(isfinite, traj.input_matrix), raw_trajectories)
end

function controlled_duffing_state_range(raw_trajectories::AbstractVector{RawControlledTrajectory})
    q_values = reduce(vcat, [vec(traj.state_matrix[1, :]) for traj in raw_trajectories])
    v_values = reduce(vcat, [vec(traj.state_matrix[2, :]) for traj in raw_trajectories])
    return Dict(
        "q_min" => minimum(q_values),
        "q_max" => maximum(q_values),
        "v_min" => minimum(v_values),
        "v_max" => maximum(v_values),
    )
end

function controlled_duffing_state_norm_max(raw_trajectories::AbstractVector{RawControlledTrajectory})
    return maximum(
        maximum(norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2))
        for traj in raw_trajectories
    )
end

## Input excitation diagnostics

function controlled_duffing_input_values(raw_trajectories::AbstractVector{RawControlledTrajectory})
    return reduce(vcat, [vec(traj.input_matrix) for traj in raw_trajectories])
end

function controlled_duffing_input_diagnostics(raw_trajectories::AbstractVector{RawControlledTrajectory})
    values = controlled_duffing_input_values(raw_trajectories)
    input_changes = Int[
        count(!=(0.0), diff(vec(traj.input_matrix)))
        for traj in raw_trajectories
    ]
    return Dict(
        "input_mean" => mean(values),
        "input_std" => std(values),
        "input_rms" => controlled_duffing_rms_value(values),
        "input_abs_max" => maximum(abs.(values)),
        "input_change_count_min" => minimum(input_changes),
        "input_change_count_total" => sum(input_changes),
    )
end

function controlled_duffing_parameter_diagnostics(
    raw_trajectories::AbstractVector{RawControlledTrajectory},
)
    beta_values = sort(unique(Float64(traj.parameter_instance["beta"]) for traj in raw_trajectories))
    counts_by_beta = Dict(
        string(beta) => count(traj -> Float64(traj.parameter_instance["beta"]) == beta, raw_trajectories)
        for beta in beta_values
    )
    return Dict(
        "beta_values" => beta_values,
        "beta_count" => length(beta_values),
        "trajectory_counts_by_beta" => counts_by_beta,
    )
end

## RK4 and alignment diagnostics

function controlled_duffing_rk4_self_residual_max(
    spec::ControlledDuffingSpec,
    raw_trajectories::AbstractVector{RawControlledTrajectory},
)
    residual = 0.0
    for traj in raw_trajectories
        delta = Float64(traj.parameter_instance["delta"])
        alpha = Float64(traj.parameter_instance["alpha"])
        beta = Float64(traj.parameter_instance["beta"])
        input_gain = Float64(traj.parameter_instance["input_gain"])
        @inbounds for m in 1:spec.trajectory_length
            next_q, next_v = rk4_controlled_duffing_step(
                delta,
                alpha,
                beta,
                input_gain,
                spec.dt,
                traj.state_matrix[1, m],
                traj.state_matrix[2, m],
                traj.input_matrix[1, m],
            )
            residual = max(
                residual,
                norm([traj.state_matrix[1, m + 1] - next_q, traj.state_matrix[2, m + 1] - next_v]),
            )
        end
    end
    return residual
end

function controlled_duffing_dimension_checks(
    spec::ControlledDuffingSpec,
    raw_trajectories::AbstractVector{RawControlledTrajectory},
)
    raw_ok = all(raw_trajectories) do traj
        size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) &&
            size(traj.input_matrix) == (spec.input_dim, spec.trajectory_length)
    end
    return Dict(
        "raw_state_size" => collect(size(first(raw_trajectories).state_matrix)),
        "raw_input_size" => collect(size(first(raw_trajectories).input_matrix)),
        "state_columns_equal_input_columns_plus_one" =>
            size(first(raw_trajectories).state_matrix, 2) == size(first(raw_trajectories).input_matrix, 2) + 1,
        "all_raw_dimensions_ok" => raw_ok,
    )
end

## State and input noise diagnostics

function controlled_duffing_observation_diagnostics(
    observed_by_id::AbstractDict{String,<:AbstractVector{ObservedControlledTrajectory}},
)
    by_observation = Dict{String,Any}()
    for (observation_id, trajectories) in observed_by_id
        state_rel = Float64[]
        input_rel = Float64[]
        state_abs = Float64[]
        input_abs = Float64[]
        max_state_error = 0.0
        max_input_error = 0.0

        for traj in trajectories
            state_ref = max(controlled_duffing_rms_value(traj.state_matrix), eps(Float64))
            input_ref = max(controlled_duffing_rms_value(traj.input_matrix), eps(Float64))
            state_noise_rms = controlled_duffing_rms_value(traj.state_noise_matrix)
            input_noise_rms = controlled_duffing_rms_value(traj.input_noise_matrix)
            push!(state_abs, state_noise_rms)
            push!(input_abs, input_noise_rms)
            push!(state_rel, state_noise_rms / state_ref)
            push!(input_rel, input_noise_rms / input_ref)
            max_state_error = max(
                max_state_error,
                maximum(abs.(traj.observation_matrix .- traj.state_matrix .- traj.state_noise_matrix)),
            )
            max_input_error = max(
                max_input_error,
                maximum(abs.(traj.observed_input_matrix .- traj.input_matrix .- traj.input_noise_matrix)),
            )
        end

        by_observation[observation_id] = Dict(
            "noise_level_id" => first(trajectories).noise_level_id,
            "num_trajectories" => length(trajectories),
            "state_noise_relative_rms_mean" => mean(state_rel),
            "state_noise_relative_rms_max" => maximum(state_rel),
            "input_noise_relative_rms_mean" => mean(input_rel),
            "input_noise_relative_rms_max" => maximum(input_rel),
            "state_noise_rms_mean" => mean(state_abs),
            "input_noise_rms_mean" => mean(input_abs),
            "state_noise_reconstruction_error_max" => max_state_error,
            "input_noise_reconstruction_error_max" => max_input_error,
        )
    end
    return by_observation
end

## Split and window summary diagnostics

function enrich_controlled_duffing_diagnostics!(
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
    return diagnostics
end

## Smoke pass policy

function controlled_duffing_smoke_passed(diagnostics::AbstractDict)
    clean = diagnostics["observations"]["duffing_controlled_fullstate_clean"]
    noisy = diagnostics["observations"]["duffing_controlled_fullstate_noise_s1"]
    return diagnostics["all_states_and_inputs_finite"] &&
        diagnostics["all_raw_dimensions_ok"] &&
        diagnostics["state_columns_equal_input_columns_plus_one"] &&
        diagnostics["input_std"] > 1e-3 &&
        diagnostics["input_change_count_total"] > 0 &&
        diagnostics["state_norm_max"] < 20.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        clean["state_noise_relative_rms_max"] <= 1e-12 &&
        clean["input_noise_relative_rms_max"] <= 1e-12 &&
        5e-4 <= noisy["state_noise_relative_rms_mean"] <= 2e-3 &&
        5e-4 <= noisy["input_noise_relative_rms_mean"] <= 2e-3
end

function controlled_duffing_formal_passed(diagnostics::AbstractDict)
    required_observations = [
        "duffing_controlled_fullstate_clean",
        "duffing_controlled_fullstate_noise_s1",
        "duffing_controlled_fullstate_noise_s2",
        "duffing_controlled_fullstate_noise_s3",
        "duffing_controlled_fullstate_noise_s4",
    ]
    has_all_observations = all(id -> haskey(diagnostics["observations"], id), required_observations)
    has_all_observations || return false

    clean = diagnostics["observations"]["duffing_controlled_fullstate_clean"]
    s1 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s1"]
    s2 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s2"]
    s3 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s3"]
    s4 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s4"]

    return diagnostics["all_states_and_inputs_finite"] &&
        diagnostics["all_raw_dimensions_ok"] &&
        diagnostics["state_columns_equal_input_columns_plus_one"] &&
        diagnostics["beta_count"] == 3 &&
        minimum(values(diagnostics["trajectory_counts_by_beta"])) > 0 &&
        diagnostics["input_std"] > 1e-3 &&
        diagnostics["input_change_count_total"] > 0 &&
        diagnostics["state_norm_max"] < 20.0 &&
        diagnostics["rk4_self_residual_max"] <= 1e-12 &&
        clean["state_noise_relative_rms_max"] <= 1e-12 &&
        clean["input_noise_relative_rms_max"] <= 1e-12 &&
        5e-4 <= s1["state_noise_relative_rms_mean"] <= 2e-3 &&
        5e-4 <= s1["input_noise_relative_rms_mean"] <= 2e-3 &&
        5e-3 <= s2["state_noise_relative_rms_mean"] <= 2e-2 &&
        5e-3 <= s2["input_noise_relative_rms_mean"] <= 2e-2 &&
        2.5e-2 <= s3["state_noise_relative_rms_mean"] <= 7.5e-2 &&
        2.5e-2 <= s3["input_noise_relative_rms_mean"] <= 7.5e-2 &&
        1.0e-1 <= s4["state_noise_relative_rms_mean"] <= 2.0e-1 &&
        1.0e-1 <= s4["input_noise_relative_rms_mean"] <= 2.0e-1
end

## Diagnostic table assembly

function summarize_controlled_duffing_dataset(
    spec::ControlledDuffingSpec,
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    observed_by_id::AbstractDict{String,<:AbstractVector{ObservedControlledTrajectory}},
)
    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "input_gain" => spec.input_gain,
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "num_raw_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "array_layout" => "state_dim_by_time_by_trajectory and input_dim_by_step_by_trajectory",
        "all_states_and_inputs_finite" => controlled_duffing_all_finite(raw_trajectories),
        "state_norm_max" => controlled_duffing_state_norm_max(raw_trajectories),
        "rk4_self_residual_max" => controlled_duffing_rk4_self_residual_max(spec, raw_trajectories),
    )

    merge!(diagnostics, controlled_duffing_dimension_checks(spec, raw_trajectories))
    merge!(diagnostics, controlled_duffing_state_range(raw_trajectories))
    merge!(diagnostics, controlled_duffing_input_diagnostics(raw_trajectories))
    merge!(diagnostics, controlled_duffing_parameter_diagnostics(raw_trajectories))
    diagnostics["observations"] = controlled_duffing_observation_diagnostics(observed_by_id)
    diagnostics["smoke_passed"] = controlled_duffing_smoke_passed(diagnostics)
    diagnostics["formal_passed"] = controlled_duffing_formal_passed(diagnostics)
    return diagnostics
end

function controlled_duffing_diagnostics_csv_row(spec::ControlledDuffingSpec, diagnostics::AbstractDict)
    observations = diagnostics["observations"]
    noise_state_mean(id) = haskey(observations, id) ? observations[id]["state_noise_relative_rms_mean"] : NaN
    noise_input_mean(id) = haskey(observations, id) ? observations[id]["input_noise_relative_rms_mean"] : NaN
    columns = [
        "system_id",
        "variant",
        "delta",
        "alpha",
        "beta",
        "input_gain",
        "dt",
        "num_raw_trajectories",
        "trajectory_length",
        "q_min",
        "q_max",
        "v_min",
        "v_max",
        "input_mean",
        "input_std",
        "input_abs_max",
        "input_change_count_total",
        "state_norm_max",
        "rk4_self_residual_max",
        "beta_count",
        "s1_state_relative_rms_mean",
        "s1_input_relative_rms_mean",
        "s2_state_relative_rms_mean",
        "s2_input_relative_rms_mean",
        "s3_state_relative_rms_mean",
        "s3_input_relative_rms_mean",
        "s4_state_relative_rms_mean",
        "s4_input_relative_rms_mean",
        "smoke_passed",
        "formal_passed",
    ]
    values = [
        spec.system_id,
        spec.variant,
        spec.delta,
        spec.alpha,
        spec.beta,
        spec.input_gain,
        spec.dt,
        diagnostics["num_raw_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["q_min"],
        diagnostics["q_max"],
        diagnostics["v_min"],
        diagnostics["v_max"],
        diagnostics["input_mean"],
        diagnostics["input_std"],
        diagnostics["input_abs_max"],
        diagnostics["input_change_count_total"],
        diagnostics["state_norm_max"],
        diagnostics["rk4_self_residual_max"],
        diagnostics["beta_count"],
        noise_state_mean("duffing_controlled_fullstate_noise_s1"),
        noise_input_mean("duffing_controlled_fullstate_noise_s1"),
        noise_state_mean("duffing_controlled_fullstate_noise_s2"),
        noise_input_mean("duffing_controlled_fullstate_noise_s2"),
        noise_state_mean("duffing_controlled_fullstate_noise_s3"),
        noise_input_mean("duffing_controlled_fullstate_noise_s3"),
        noise_state_mean("duffing_controlled_fullstate_noise_s4"),
        noise_input_mean("duffing_controlled_fullstate_noise_s4"),
        diagnostics["smoke_passed"],
        diagnostics["formal_passed"],
    ]
    return columns, values
end
