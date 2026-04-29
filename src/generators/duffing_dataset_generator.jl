## Generator scope and entry points

using Dates

function duffing_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Manual smoke initial-condition set

function validate_duffing_manual_initial_conditions(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    String(domain["type"]) == "manual_smoke_set" ||
        throw(ArgumentError("Duffing smoke expects initial_condition_domain type manual_smoke_set"))
    values = domain["values"]
    length(values) == Int(system_config["num_trajectories"]) ||
        throw(ArgumentError("num_trajectories must equal the manual smoke initial-condition count"))
    for x0 in values
        length(x0) == 2 || throw(ArgumentError("each Duffing initial condition must have two entries"))
        all(isfinite, Float64.(x0)) || throw(ArgumentError("initial condition contains NaN or Inf"))
    end
    return true
end

function duffing_manual_initial_conditions(system_config::AbstractDict)
    validate_duffing_manual_initial_conditions(system_config)
    return [Float64.(x0) for x0 in system_config["initial_condition_domain"]["values"]]
end

## Raw and observed trajectory generation

function build_duffing_raw_trajectory(
    spec::DuffingUnforcedDoubleWellSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_duffing_unforced_double_well_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
    )
    return RawTrajectory(
        make_trajectory_id(spec.system_id, trajectory_index),
        spec.system_id,
        parameter_instance,
        Float64.(x0),
        times,
        X,
    )
end

function validate_duffing_raw_trajectory_dimensions(spec::DuffingUnforcedDoubleWellSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    return true
end

function generate_duffing_raw_trajectories(system_config::AbstractDict)
    spec = duffing_unforced_double_well_spec_from_config(system_config)
    validate_duffing_unforced_double_well_spec(spec)
    x0_values = duffing_manual_initial_conditions(system_config)

    raw_trajectories = RawTrajectory[]
    for (q, x0) in enumerate(x0_values)
        raw = build_duffing_raw_trajectory(spec, q, x0)
        validate_duffing_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

function generate_duffing_observed_trajectories(
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

## Split and window summary construction

function build_duffing_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_duffing_window_summary(
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
            window_id = string("duffing_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("duffing_rollout_h", horizon),
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

## Raw, processed, manifest, report saving

function duffing_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_duffing_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = duffing_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_duffing_observed(
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
        initial_conditions = hcat([traj.initial_condition_instance for traj in observed_trajectories]...),
        state_tensor = duffing_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = duffing_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function duffing_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_duffing_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(duffing_csv_value.(values), ","))
    end
    return path
end

## Prepare phase portrait and energy diagnostic plots

function maybe_save_duffing_plots(
    spec::DuffingUnforcedDoubleWellSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping Duffing plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping Duffing plots because Plots.jl was not imported"
        end
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["q(t)" "v(t)"],
            title = string("Duffing ", run_label, " time series"),
        )
        time_path = joinpath(plot_dir, string(run_label, "_time_series.png"))
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_phase = Main.Plots.plot(; xlabel = "q", ylabel = "v", title = string("Duffing ", run_label, " phase portrait"))
        for traj in raw_trajectories
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, string(run_label, "_phase_portrait.png"))
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        p_energy = Main.Plots.plot(; xlabel = "t", ylabel = "E(q,v)", title = string("Duffing ", run_label, " energy curves"))
        for traj in raw_trajectories
            energies = duffing_energy_sequence(spec, traj)
            Main.Plots.plot!(p_energy, traj.times, energies; label = false)
        end
        energy_path = joinpath(plot_dir, string(run_label, "_energy_curves.png"))
        Main.Plots.savefig(p_energy, energy_path)
        push!(plot_files, energy_path)

        q0 = [traj.initial_condition_instance[1] for traj in raw_trajectories]
        v0 = [traj.initial_condition_instance[2] for traj in raw_trajectories]
        p_initial = Main.Plots.scatter(
            q0,
            v0;
            xlabel = "q0",
            ylabel = "v0",
            label = false,
            title = string("Duffing ", run_label, " initial conditions"),
        )
        initial_path = joinpath(plot_dir, string(run_label, "_initial_conditions.png"))
        Main.Plots.savefig(p_initial, initial_path)
        push!(plot_files, initial_path)

        final_labels = [duffing_well_label(traj.state_matrix[1, end]) for traj in raw_trajectories]
        counts = duffing_well_counts(final_labels)
        p_well = Main.Plots.bar(
            ["left", "right", "near_barrier"],
            [counts["left"], counts["right"], counts["near_barrier"]];
            xlabel = "final well",
            ylabel = "count",
            label = false,
            title = string("Duffing ", run_label, " final well distribution"),
        )
        well_path = joinpath(plot_dir, string(run_label, "_final_well_distribution.png"))
        Main.Plots.savefig(p_well, well_path)
        push!(plot_files, well_path)

        return plot_files
    catch err
        @warn "Skipping Duffing plots because plot generation failed" exception = err
        return String[]
    end
end

function make_duffing_manifest(;
    configs::AbstractDict,
    spec::DuffingUnforcedDoubleWellSpec,
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
        "delta_default" => spec.delta,
        "alpha_default" => spec.alpha,
        "beta_default" => spec.beta,
        "parameter_domain" => system_config["parameter_domain"],
        "dt" => spec.dt,
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
        "system_metadata" => duffing_unforced_double_well_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_duffing_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::DuffingUnforcedDoubleWellSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = duffing_project_path(project_root, output_policy["raw_path"])
    processed_path = duffing_project_path(project_root, output_policy["processed_path"])
    split_path = duffing_project_path(project_root, output_policy["split_path"])
    windows_summary_path = duffing_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = duffing_project_path(project_root, output_policy["manifest_path"])
    release_index_path = duffing_project_path(project_root, output_policy["release_index_path"])

    task_dir = run_label == "formal" ? "duffing_unforced_double_well_formal" : "duffing_unforced_double_well_smoke"
    report_root = joinpath(project_root, "reports", "v1_core", task_dir)
    table_path = joinpath(report_root, "tables", "diagnostics.csv")
    plot_dir = joinpath(report_root, "plots")
    log_path = joinpath(report_root, "logs", string(run_label, ".log"))

    save_duffing_raw(raw_path, raw_trajectories)
    save_duffing_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_duffing_plots(spec, raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_duffing_manifest(
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
        "release_id" => string("duffing_unforced_double_well_fullobs_v1_", run_label),
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

    columns, values = duffing_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_duffing_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(duffing_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "max positive energy jump: ", diagnostics["max_positive_energy_jump"])
        println(io, "positive energy jump count total: ", diagnostics["positive_energy_jump_count_total"])
        println(io, "energy drop min: ", diagnostics["energy_drop_min"])
        println(io, "initial well counts: ", diagnostics["initial_well_counts"])
        println(io, "final well counts: ", diagnostics["final_well_counts"])
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
