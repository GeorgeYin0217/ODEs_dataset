## Generator scope and path helpers

using Dates

function lotka_volterra_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Manual smoke initial-condition set

function validate_lotka_volterra_manual_initial_conditions(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    String(domain["type"]) == "manual_smoke_set" ||
        throw(ArgumentError("Lotka-Volterra smoke expects initial_condition_domain type manual_smoke_set"))
    values = domain["values"]
    length(values) == Int(system_config["num_trajectories"]) ||
        throw(ArgumentError("num_trajectories must equal the manual smoke initial-condition count"))
    for x0 in values
        length(x0) == 2 || throw(ArgumentError("each Lotka-Volterra initial condition must have two entries"))
        x0_float = Float64.(x0)
        all(isfinite, x0_float) || throw(ArgumentError("initial condition contains NaN or Inf"))
        all(>(0), x0_float) || throw(ArgumentError("Lotka-Volterra initial conditions must be positive"))
    end
    return true
end

function lotka_volterra_manual_initial_conditions(system_config::AbstractDict)
    validate_lotka_volterra_manual_initial_conditions(system_config)
    return [Float64.(x0) for x0 in system_config["initial_condition_domain"]["values"]]
end

## Raw and observed trajectory generation

function build_lotka_volterra_raw_trajectory(
    spec::LotkaVolterraSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_lotka_volterra_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "gamma" => spec.gamma,
        "delta" => spec.delta,
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

function validate_lotka_volterra_raw_trajectory_dimensions(spec::LotkaVolterraSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    all(>(0), traj.state_matrix) || throw(ArgumentError("state_matrix left the positive quadrant"))
    return true
end

function generate_lotka_volterra_raw_trajectories(system_config::AbstractDict)
    spec = lotka_volterra_spec_from_config(system_config)
    validate_lotka_volterra_spec(spec)
    x0_values = lotka_volterra_manual_initial_conditions(system_config)

    raw_trajectories = RawTrajectory[]
    for (q, x0) in enumerate(x0_values)
        raw = build_lotka_volterra_raw_trajectory(spec, q, x0)
        validate_lotka_volterra_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

function generate_lotka_volterra_observed_trajectories(
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

function build_lotka_volterra_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_lotka_volterra_window_summary(
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
            window_id = string("lotka_volterra_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("lotka_volterra_rollout_h", horizon),
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

## Raw, processed, manifest, and report saving

function lotka_volterra_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_lotka_volterra_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = lotka_volterra_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_lotka_volterra_observed(
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
        state_tensor = lotka_volterra_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = lotka_volterra_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function lotka_volterra_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_lotka_volterra_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(lotka_volterra_csv_value.(values), ","))
    end
    return path
end

## Prepare phase portrait, time-series, and invariant plots

function maybe_save_lotka_volterra_plots(
    spec::LotkaVolterraSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping Lotka-Volterra plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping Lotka-Volterra plots because Plots.jl was not imported"
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
            label = ["x(t)" "y(t)"],
            title = string("Lotka-Volterra ", run_label, " time series"),
        )
        time_path = joinpath(plot_dir, string(run_label, "_time_series.png"))
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        equilibrium = lotka_volterra_positive_equilibrium(spec)
        p_phase = Main.Plots.plot(;
            xlabel = "prey x",
            ylabel = "predator y",
            title = string("Lotka-Volterra ", run_label, " phase portrait"),
        )
        for traj in raw_trajectories
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        Main.Plots.scatter!(p_phase, [equilibrium[1]], [equilibrium[2]]; label = "equilibrium", markersize = 4)
        phase_path = joinpath(plot_dir, string(run_label, "_phase_portrait.png"))
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        p_invariant = Main.Plots.plot(;
            xlabel = "t",
            ylabel = "H(t) - H(0)",
            title = string("Lotka-Volterra ", run_label, " invariant drift"),
        )
        for traj in raw_trajectories
            values = lotka_volterra_invariant_sequence(spec, traj)
            Main.Plots.plot!(p_invariant, traj.times, values .- first(values); label = false)
        end
        invariant_path = joinpath(plot_dir, string(run_label, "_invariant_drift.png"))
        Main.Plots.savefig(p_invariant, invariant_path)
        push!(plot_files, invariant_path)

        return plot_files
    catch err
        @warn "Skipping Lotka-Volterra plots because plot generation failed" exception = err
        return String[]
    end
end

function make_lotka_volterra_manifest(;
    configs::AbstractDict,
    spec::LotkaVolterraSpec,
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
        "alpha_default" => spec.alpha,
        "beta_default" => spec.beta,
        "gamma_default" => spec.gamma,
        "delta_default" => spec.delta,
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
        "system_metadata" => lotka_volterra_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_lotka_volterra_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::LotkaVolterraSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = lotka_volterra_project_path(project_root, output_policy["raw_path"])
    processed_path = lotka_volterra_project_path(project_root, output_policy["processed_path"])
    split_path = lotka_volterra_project_path(project_root, output_policy["split_path"])
    windows_summary_path = lotka_volterra_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = lotka_volterra_project_path(project_root, output_policy["manifest_path"])
    release_index_path = lotka_volterra_project_path(project_root, output_policy["release_index_path"])

    table_path = joinpath(project_root, "reports", "tables", "v1_core", "lotka_volterra", run_label, "diagnostics.csv")
    plot_dir = joinpath(project_root, "reports", "plots", "v1_core", "lotka_volterra", run_label)
    log_path = joinpath(project_root, "reports", "logs", "v1_core", "lotka_volterra", string(run_label, ".log"))

    save_lotka_volterra_raw(raw_path, raw_trajectories)
    save_lotka_volterra_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_lotka_volterra_plots(spec, raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_lotka_volterra_manifest(
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
        "release_id" => string("lotka_volterra_fullobs_v1_", run_label),
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

    columns, values = lotka_volterra_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_lotka_volterra_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(lotka_volterra_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "all states positive: ", diagnostics["all_states_positive"])
        println(io, "state range x: [", diagnostics["x_min"], ", ", diagnostics["x_max"], "]")
        println(io, "state range y: [", diagnostics["y_min"], ", ", diagnostics["y_max"], "]")
        println(io, "invariant max abs drift: ", diagnostics["invariant_max_abs_drift"])
        println(io, "invariant max rel drift: ", diagnostics["invariant_max_rel_drift"])
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
