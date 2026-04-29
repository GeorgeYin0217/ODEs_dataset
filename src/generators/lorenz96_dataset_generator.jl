## Generator scope and path helpers

using Dates
using Random

function lorenz96_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Sample initial conditions around forced background state

function validate_lorenz96_initial_condition_domain(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    domain_type = String(domain["type"])
    if domain_type != "seeded_perturbations_around_forcing"
        throw(ArgumentError("unsupported Lorenz96 initial_condition_domain type: $(domain_type)"))
    end
    scale = Float64(domain["perturbation_scale"])
    isfinite(scale) && scale > 0 || throw(ArgumentError("perturbation_scale must be positive and finite"))
    Int(system_config["num_trajectories"]) >= 1 || throw(ArgumentError("num_trajectories must be positive"))
    return true
end

function lorenz96_initial_conditions(system_config::AbstractDict, spec::Lorenz96Spec)
    validate_lorenz96_initial_condition_domain(system_config)
    rng = MersenneTwister(Int(system_config["seed_policy"]["generation_seed"]))
    scale = Float64(system_config["initial_condition_domain"]["perturbation_scale"])
    num_trajectories = Int(system_config["num_trajectories"])
    base = lorenz96_uniform_state(spec)
    return [base .+ scale .* randn(rng, spec.state_dim) for _ in 1:num_trajectories]
end

## Integrate burn-in segment and retained trajectories

function lorenz96_burn_in_steps(spec::Lorenz96Spec)
    return Int(round(spec.burn_in_time / spec.dt))
end

function build_lorenz96_raw_trajectory(
    spec::Lorenz96Spec,
    trajectory_index::Integer,
    sampled_x0::AbstractVector{<:Real},
)
    burn_in_state = advance_lorenz96_state(spec, sampled_x0, lorenz96_burn_in_steps(spec))
    times, X = generate_lorenz96_trajectory(spec, burn_in_state)
    parameter_instance = Dict{String,Any}(
        "F" => spec.F,
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

function validate_lorenz96_raw_trajectory_dimensions(spec::Lorenz96Spec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    return true
end

function generate_lorenz96_raw_trajectories(system_config::AbstractDict)
    spec = lorenz96_spec_from_config(system_config)
    validate_lorenz96_spec(spec)
    validate_lorenz96_boundary_indices(spec)
    x0_values = lorenz96_initial_conditions(system_config, spec)

    raw_trajectories = RawTrajectory[]
    for (q, x0) in enumerate(x0_values)
        raw = build_lorenz96_raw_trajectory(spec, q, x0)
        validate_lorenz96_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

## Apply observation pipeline

function generate_lorenz96_observed_trajectories(
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

function build_lorenz96_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_lorenz96_window_summary(
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
            window_id = string("lorenz96_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("lorenz96_rollout_h", horizon),
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

## Write raw processed and manifest outputs

function lorenz96_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_lorenz96_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
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
        state_tensor = lorenz96_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_lorenz96_observed(
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
        state_tensor = lorenz96_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = lorenz96_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function lorenz96_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_lorenz96_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(lorenz96_csv_value.(values), ","))
    end
    return path
end

function write_lorenz96_coordinate_statistics_csv(path::AbstractString, diagnostics::AbstractDict)
    ensure_parent_dir(path)
    means = diagnostics["coordinate_mean"]
    variances = diagnostics["coordinate_variance"]
    open(path, "w") do io
        println(io, "coordinate,mean,variance")
        for i in eachindex(means)
            println(io, i, ",", means[i], ",", variances[i])
        end
    end
    return path
end

function write_lorenz96_split_window_counts_csv(
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

## Export smoke time-series and heatmap figures

function maybe_save_lorenz96_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping Lorenz96 plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping Lorenz96 plots because Plots.jl was not imported"
        end
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix[[1, 10, 20, 30, 40], :]';
            xlabel = "t",
            ylabel = "state",
            label = ["x1" "x10" "x20" "x30" "x40"],
            title = string("Lorenz96 ", run_label, " representative coordinates"),
        )
        time_path = joinpath(plot_dir, "lorenz96_representative_coordinates.png")
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_heatmap = Main.Plots.heatmap(
            first_raw.times,
            1:size(first_raw.state_matrix, 1),
            first_raw.state_matrix;
            xlabel = "t",
            ylabel = "coordinate",
            title = string("Lorenz96 ", run_label, " space-time heatmap"),
        )
        heatmap_path = joinpath(plot_dir, "lorenz96_space_time_heatmap.png")
        Main.Plots.savefig(p_heatmap, heatmap_path)
        push!(plot_files, heatmap_path)

        return plot_files
    catch err
        @warn "Skipping Lorenz96 plots because plot generation failed" exception = err
        return String[]
    end
end

function make_lorenz96_manifest(;
    configs::AbstractDict,
    spec::Lorenz96Spec,
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
        "F_default" => spec.F,
        "parameter_domain" => system_config["parameter_domain"],
        "dt" => spec.dt,
        "burn_in_time" => spec.burn_in_time,
        "burn_in_steps" => lorenz96_burn_in_steps(spec),
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
        "system_metadata" => lorenz96_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_lorenz96_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::Lorenz96Spec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = lorenz96_project_path(project_root, output_policy["raw_path"])
    processed_path = lorenz96_project_path(project_root, output_policy["processed_path"])
    split_path = lorenz96_project_path(project_root, output_policy["split_path"])
    windows_summary_path = lorenz96_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = lorenz96_project_path(project_root, output_policy["manifest_path"])
    release_index_path = lorenz96_project_path(project_root, output_policy["release_index_path"])

    table_dir = joinpath(project_root, "reports", "v1_core", "lorenz96_standard", "tables", run_label)
    table_path = joinpath(table_dir, "lorenz96_diagnostics.csv")
    coordinate_statistics_path = joinpath(table_dir, "lorenz96_coordinate_statistics.csv")
    split_window_counts_path = joinpath(table_dir, "lorenz96_split_window_counts.csv")
    plot_dir = joinpath(project_root, "reports", "v1_core", "lorenz96_standard", "plots", run_label)
    log_filename = run_label == "standard" ? "generate_lorenz96_standard.log" : "run_lorenz96_smoke.log"
    log_path = joinpath(project_root, "reports", "v1_core", "lorenz96_standard", "logs", run_label, log_filename)

    save_lorenz96_raw(raw_path, raw_trajectories)
    save_lorenz96_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_lorenz96_plots(raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "coordinate_statistics_table" => coordinate_statistics_path,
        "split_window_counts_table" => split_window_counts_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_lorenz96_manifest(
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
        "release_id" => string("lorenz96_fullobs_v1_", run_label),
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

    columns, values = lorenz96_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_lorenz96_single_row_csv(table_path, columns, values)
    write_lorenz96_coordinate_statistics_csv(coordinate_statistics_path, diagnostics)
    write_lorenz96_split_window_counts_csv(split_window_counts_path, split, window_summary)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(lorenz96_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "burn_in_time: ", spec.burn_in_time)
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "state range: [", diagnostics["state_min"], ", ", diagnostics["state_max"], "]")
        println(io, "energy_mean: ", diagnostics["energy_mean"])
        println(io, "coordinate_mean_range: ", diagnostics["coordinate_mean_range"])
        println(io, "coordinate_variance_range: ", diagnostics["coordinate_variance_range"])
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
        "coordinate_statistics_path" => coordinate_statistics_path,
        "split_window_counts_path" => split_window_counts_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end
