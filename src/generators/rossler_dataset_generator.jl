## Generator scope and path helpers

using Dates

function rossler_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Manual smoke initial-condition set

function validate_rossler_manual_initial_conditions(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    domain_type = String(domain["type"])
    if domain_type == "manual_smoke_set"
        values = domain["values"]
        length(values) == Int(system_config["num_trajectories"]) ||
            throw(ArgumentError("num_trajectories must equal the manual initial-condition count"))
        for x0 in values
            length(x0) == 3 || throw(ArgumentError("each Rossler initial condition must have three entries"))
            x0_float = Float64.(x0)
            all(isfinite, x0_float) || throw(ArgumentError("initial condition contains NaN or Inf"))
        end
    elseif domain_type == "manual_grid"
        x_values = Float64.(domain["x_values"])
        y_values = Float64.(domain["y_values"])
        z_values = Float64.(domain["z_values"])
        length(x_values) * length(y_values) * length(z_values) == Int(system_config["num_trajectories"]) ||
            throw(ArgumentError("num_trajectories must equal length(x_values) * length(y_values) * length(z_values)"))
        all(isfinite, x_values) || throw(ArgumentError("x_values contains NaN or Inf"))
        all(isfinite, y_values) || throw(ArgumentError("y_values contains NaN or Inf"))
        all(isfinite, z_values) || throw(ArgumentError("z_values contains NaN or Inf"))
    else
        throw(ArgumentError("unsupported Rossler initial_condition_domain type: $(domain_type)"))
    end
    return true
end

function rossler_manual_initial_conditions(system_config::AbstractDict)
    validate_rossler_manual_initial_conditions(system_config)
    domain = system_config["initial_condition_domain"]
    if String(domain["type"]) == "manual_grid"
        return [
            [x, y, z]
            for x in Float64.(domain["x_values"])
            for y in Float64.(domain["y_values"])
            for z in Float64.(domain["z_values"])
        ]
    else
        return [Float64.(x0) for x0 in domain["values"]]
    end
end

## Integrate burn-in segments and retained attractor trajectories

function rossler_burn_in_steps(spec::RosslerSpec)
    return Int(round(spec.burn_in_time / spec.dt))
end

function build_rossler_raw_trajectory(
    spec::RosslerSpec,
    trajectory_index::Integer,
    sampled_x0::AbstractVector{<:Real},
)
    burn_in_state = advance_rossler_state(spec, sampled_x0, rossler_burn_in_steps(spec))
    times, X = generate_rossler_trajectory(spec, burn_in_state)
    parameter_instance = Dict{String,Any}(
        "a" => spec.a,
        "b" => spec.b,
        "c" => spec.c,
        "pre_burn_in_initial_condition" => Float64.(sampled_x0),
        "burn_in_time" => spec.burn_in_time,
    )
    return RawTrajectory(
        make_trajectory_id(spec.system_id, trajectory_index),
        spec.system_id,
        parameter_instance,
        burn_in_state,
        times,
        X,
    )
end

function validate_rossler_raw_trajectory_dimensions(spec::RosslerSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    return true
end

function generate_rossler_raw_trajectories(system_config::AbstractDict)
    spec = rossler_spec_from_config(system_config)
    validate_rossler_spec(spec)
    x0_values = rossler_manual_initial_conditions(system_config)

    raw_trajectories = RawTrajectory[]
    for (q, x0) in enumerate(x0_values)
        raw = build_rossler_raw_trajectory(spec, q, x0)
        validate_rossler_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

function generate_rossler_observed_trajectories(
    raw_trajectories::AbstractVector{RawTrajectory},
    observation_config::AbstractDict,
    state_dim::Integer,
)
    observation_spec = full_state_observation_spec_from_config(observation_config)
    validate_full_state_observation_spec(observation_spec, state_dim)
    observed = [apply_full_state_observation(raw, observation_spec) for raw in raw_trajectories]
    foreach(validate_observed_trajectory, observed)
    return observation_spec, observed
end

## Generate trajectory-level split indices and windows

function build_rossler_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
    trajectory_ids = [traj.trajectory_id for traj in raw_trajectories]
    return build_trajectory_split(
        trajectory_ids;
        train_ratio = Float64(split_config["train_ratio"]),
        val_ratio = Float64(split_config["val_ratio"]),
        test_ratio = Float64(split_config["test_ratio"]),
        seed = Int(split_config["seed"]),
        split_id = split_config["split_id"],
        split_type = split_config["split_type"],
    )
end

function build_rossler_window_summary(
    split::AbstractDict,
    trajectory_length::Integer,
    window_config::AbstractDict,
)
    one_step = window_config["one_step"]
    one_step_windows = build_one_step_windows(
        split,
        trajectory_length;
        window_id = one_step["window_id"],
        lag = Int(one_step["lag"]),
    )
    validate_window_indices(one_step_windows, split, trajectory_length)

    rollout_summaries = Dict{String,Any}()
    for horizon in Int.(window_config["rollout"]["horizons"])
        rollout_windows = build_rollout_windows(
            split,
            trajectory_length;
            window_id = string("rossler_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("rossler_rollout_h", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => trajectory_length + 1 - horizon,
        )
    end

    statistics_config = window_config["statistics"]
    statistics_windows = build_statistics_windows(
        split,
        trajectory_length;
        window_id = statistics_config["window_id"],
        horizon = Int(statistics_config["horizon"]),
    )
    validate_window_indices(statistics_windows, split, trajectory_length)

    return Dict(
        "window_id" => window_config["window_id"],
        "one_step" => Dict(
            "window_id" => one_step["window_id"],
            "lag" => Int(one_step["lag"]),
            "counts" => window_counts(one_step_windows),
            "samples_per_trajectory" => trajectory_length,
        ),
        "rollout" => Dict(
            "window_id" => window_config["rollout"]["window_id"],
            "horizons" => Int.(window_config["rollout"]["horizons"]),
            "by_horizon" => rollout_summaries,
        ),
        "statistics" => Dict(
            "window_id" => statistics_config["window_id"],
            "horizon" => Int(statistics_config["horizon"]),
            "counts" => window_counts(statistics_windows),
            "starts_per_trajectory" => trajectory_length + 2 - Int(statistics_config["horizon"]),
        ),
    )
end

## Save raw, processed, split, and manifest outputs

function rossler_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_rossler_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        retained_initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        pre_burn_in_initial_conditions = hcat(
            [traj.parameter_instance["pre_burn_in_initial_condition"] for traj in raw_trajectories]...,
        ),
        times = first(raw_trajectories).times,
        state_tensor = rossler_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_rossler_observed(
    path::AbstractString,
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in observed_trajectories],
        system_id = first(observed_trajectories).system_id,
        observation_id = first(observed_trajectories).observation_id,
        parameter_instances = [traj.parameter_instance for traj in observed_trajectories],
        retained_initial_conditions = hcat([traj.initial_condition_instance for traj in observed_trajectories]...),
        state_tensor = rossler_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = rossler_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function rossler_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_rossler_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(rossler_csv_value.(values), ","))
    end
    return path
end

function write_rossler_state_ranges_csv(path::AbstractString, diagnostics::AbstractDict)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, "coordinate,min,max,span")
        println(io, "x,", diagnostics["x_min"], ",", diagnostics["x_max"], ",", diagnostics["x_span"])
        println(io, "y,", diagnostics["y_min"], ",", diagnostics["y_max"], ",", diagnostics["y_span"])
        println(io, "z,", diagnostics["z_min"], ",", diagnostics["z_max"], ",", diagnostics["z_span"])
    end
    return path
end

function write_rossler_statistics_csv(path::AbstractString, diagnostics::AbstractDict)
    ensure_parent_dir(path)
    means = diagnostics["state_mean"]
    variances = diagnostics["state_variance"]
    covariance = diagnostics["state_covariance"]
    open(path, "w") do io
        println(io, "quantity,x,y,z")
        println(io, "mean,", join(means, ","))
        println(io, "variance,", join(variances, ","))
        for i in 1:3
            println(io, "covariance_row_", i, ",", join(covariance[i, :], ","))
        end
        println(io, "divergence_min,", diagnostics["divergence_min"], ",,")
        println(io, "divergence_mean,", diagnostics["divergence_mean"], ",,")
        println(io, "divergence_max,", diagnostics["divergence_max"], ",,")
    end
    return path
end

function write_rossler_split_window_counts_csv(
    path::AbstractString,
    split::AbstractDict,
    window_summary::AbstractDict,
)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, "object,split,count")
        for split_name in ("train", "val", "test")
            println(io, "trajectories,", split_name, ",", length(split[string(split_name, "_trajectory_ids")]))
        end
        for split_name in ("train", "val", "test")
            println(io, "one_step,", split_name, ",", window_summary["one_step"]["counts"][split_name])
        end
        for (horizon_key, summary) in sort(collect(window_summary["rollout"]["by_horizon"]); by = first)
            for split_name in ("train", "val", "test")
                println(io, "rollout_", horizon_key, ",", split_name, ",", summary["counts"][split_name])
            end
        end
        for split_name in ("train", "val", "test")
            println(io, "statistics,", split_name, ",", window_summary["statistics"]["counts"][split_name])
        end
    end
    return path
end

## Export smoke phase-space figure

function maybe_save_rossler_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping Rossler plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping Rossler plots because Plots.jl was not imported"
        end
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)
        selected = raw_trajectories[1:min(6, length(raw_trajectories))]

        p_phase3d = Main.Plots.plot(;
            xlabel = "x",
            ylabel = "y",
            zlabel = "z",
            title = string("Rossler ", run_label, " phase space"),
            legend = false,
            camera = (45, 25),
        )
        for traj in selected
            Main.Plots.plot!(p_phase3d, traj.state_matrix[1, :], traj.state_matrix[2, :], traj.state_matrix[3, :])
        end
        phase3d_path = joinpath(plot_dir, "rossler_phase3d.png")
        Main.Plots.savefig(p_phase3d, phase3d_path)
        push!(plot_files, phase3d_path)

        projections = (
            ("xy", 1, 2, "x", "y"),
            ("xz", 1, 3, "x", "z"),
            ("yz", 2, 3, "y", "z"),
        )
        for (name, i, j, xlabel, ylabel) in projections
            p = Main.Plots.plot(;
                xlabel = xlabel,
                ylabel = ylabel,
                title = string("Rossler ", run_label, " ", name, " projection"),
                legend = false,
            )
            for traj in selected
                Main.Plots.plot!(p, traj.state_matrix[i, :], traj.state_matrix[j, :])
            end
            path = joinpath(plot_dir, string("rossler_projection_", name, ".png"))
            Main.Plots.savefig(p, path)
            push!(plot_files, path)
        end

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["x(t)" "y(t)" "z(t)"],
            title = string("Rossler ", run_label, " time series"),
        )
        time_path = joinpath(plot_dir, "rossler_timeseries_xyz.png")
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        return plot_files
    catch err
        @warn "Skipping Rossler plots because plot generation failed" exception = err
        return String[]
    end
end

function make_rossler_manifest(;
    configs::AbstractDict,
    spec::RosslerSpec,
    observation_spec::FullStateObservationSpec,
    split::AbstractDict,
    window_summary::AbstractDict,
    generated_files::AbstractDict,
    diagnostics::AbstractDict,
)
    system_config = configs["system"]
    benchmark_config = configs["benchmark"]
    return Dict(
        "dataset_version" => benchmark_config["release_version"],
        "created_at" => string(now()),
        "benchmark_id" => benchmark_config["benchmark_id"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "observation_dim" => observation_spec.output_dim,
        "a_default" => spec.a,
        "b_default" => spec.b,
        "c_default" => spec.c,
        "parameter_domain" => system_config["parameter_domain"],
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "burn_in_steps" => rossler_burn_in_steps(spec),
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "num_trajectories" => Int(system_config["num_trajectories"]),
        "initial_condition_policy" => system_config["initial_condition_domain"],
        "observation_id" => observation_spec.observation_id,
        "split_id" => split["split_id"],
        "window_ids" => benchmark_config["window_ids"],
        "task_ids" => benchmark_config["task_ids"],
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "seed" => system_config["seed_policy"]["generation_seed"],
        "array_layout" => "state_dim_by_time_by_trajectory",
        "system_metadata" => rossler_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_rossler_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::RosslerSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = rossler_project_path(project_root, output_policy["raw_path"])
    processed_path = rossler_project_path(project_root, output_policy["processed_path"])
    split_path = rossler_project_path(project_root, output_policy["split_path"])
    windows_summary_path = rossler_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = rossler_project_path(project_root, output_policy["manifest_path"])
    release_index_path = rossler_project_path(project_root, output_policy["release_index_path"])

    table_dir = joinpath(project_root, "reports", "tables", "rossler_standard", run_label)
    table_path = joinpath(table_dir, "rossler_diagnostics.csv")
    state_ranges_path = joinpath(table_dir, "rossler_state_ranges.csv")
    statistics_path = joinpath(table_dir, "rossler_statistics.csv")
    split_window_counts_path = joinpath(table_dir, "rossler_split_window_counts.csv")
    plot_dir = joinpath(project_root, "reports", "plots", "rossler_standard", run_label)
    log_filename = run_label == "standard" ? "generate_rossler_standard.log" : "run_rossler_smoke.log"
    log_path = joinpath(project_root, "reports", "logs", "rossler_standard", run_label, log_filename)

    save_rossler_raw(raw_path, raw_trajectories)
    save_rossler_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_rossler_plots(raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "state_ranges_table" => state_ranges_path,
        "statistics_table" => statistics_path,
        "split_window_counts_table" => split_window_counts_path,
        "release_index" => release_index_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_rossler_manifest(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        split = split,
        window_summary = window_summary,
        generated_files = generated_files,
        diagnostics = diagnostics,
    )
    write_json_file(manifest_path, manifest)

    release_index = Dict(
        "release_id" => string("rossler_fullobs_v1_", run_label),
        "release_version" => configs["benchmark"]["release_version"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "manifest_path" => manifest_path,
        "created_at" => string(now()),
    )
    write_json_file(release_index_path, release_index)

    columns, values = rossler_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_rossler_single_row_csv(table_path, columns, values)
    write_rossler_state_ranges_csv(state_ranges_path, diagnostics)
    write_rossler_statistics_csv(statistics_path, diagnostics)
    write_rossler_split_window_counts_csv(split_window_counts_path, split, window_summary)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(rossler_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "burn_in_time: ", spec.burn_in_time)
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "state range x: [", diagnostics["x_min"], ", ", diagnostics["x_max"], "]")
        println(io, "state range y: [", diagnostics["y_min"], ", ", diagnostics["y_max"], "]")
        println(io, "state range z: [", diagnostics["z_min"], ", ", diagnostics["z_max"], "]")
        println(io, "divergence mean: ", diagnostics["divergence_mean"])
        println(io, "active attractor trajectory count: ", diagnostics["active_attractor_trajectory_count"])
        println(io, "plot files: ", plot_files)
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "manifest_path: ", manifest_path)
    end

    return Dict(
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "split_path" => split_path,
        "windows_summary_path" => windows_summary_path,
        "manifest_path" => manifest_path,
        "release_index_path" => release_index_path,
        "table_path" => table_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end
