## Generator input configuration parsing

using Dates
using Random

function controlled_duffing_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

function controlled_duffing_manual_initial_conditions(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    String(domain["type"]) == "manual_smoke_set" ||
        throw(ArgumentError("manual initial conditions require type=manual_smoke_set"))
    values = domain["values"]
    return [Float64.(x0) for x0 in values]
end

function controlled_duffing_grid_initial_conditions(system_config::AbstractDict)
    domain = system_config["initial_condition_domain"]
    String(domain["type"]) == "manual_grid_2d" ||
        throw(ArgumentError("grid initial conditions require type=manual_grid_2d"))
    q_values = Float64.(domain["q_values"])
    v_values = Float64.(domain["v_values"])
    return [[q, v] for q in q_values for v in v_values]
end

function controlled_duffing_initial_conditions(system_config::AbstractDict)
    domain_type = String(system_config["initial_condition_domain"]["type"])
    if domain_type == "manual_smoke_set"
        return controlled_duffing_manual_initial_conditions(system_config)
    elseif domain_type == "manual_grid_2d"
        return controlled_duffing_grid_initial_conditions(system_config)
    else
        throw(ArgumentError("unsupported controlled Duffing initial_condition_domain type: $(domain_type)"))
    end
end

function controlled_duffing_beta_values(system_config::AbstractDict)
    if haskey(system_config, "parameter_grid") && haskey(system_config["parameter_grid"], "beta")
        return Float64.(system_config["parameter_grid"]["beta"])
    else
        return [Float64(system_config["default_parameters"]["beta"])]
    end
end

function controlled_duffing_spec_with_beta(system_config::AbstractDict, beta::Real)
    config = deepcopy(system_config)
    config["default_parameters"]["beta"] = Float64(beta)
    return controlled_duffing_spec_from_config(config)
end

## Initial condition and open-loop input sampling

function controlled_duffing_random_zoh_input(
    trajectory_length::Integer;
    amplitude::Real,
    hold_steps::Integer,
    seed::Integer,
)
    trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))
    hold_steps >= 1 || throw(ArgumentError("hold_steps must be at least 1"))
    rng = MersenneTwister(seed)
    U = Matrix{Float64}(undef, 1, trajectory_length)
    m = 1
    while m <= trajectory_length
        u_value = rand(rng) * 2.0 * Float64(amplitude) - Float64(amplitude)
        stop = min(m + hold_steps - 1, trajectory_length)
        U[1, m:stop] .= u_value
        m = stop + 1
    end
    return U
end

function controlled_duffing_input_seed(base_seed::Integer, trajectory_index::Integer)
    return Int(base_seed + 1009 * trajectory_index)
end

## Clean state trajectory integration

function build_controlled_duffing_raw_trajectory(
    spec::ControlledDuffingSpec,
    system_config::AbstractDict,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    input_config = system_config["input_policy"]
    seed = controlled_duffing_input_seed(
        Int(system_config["seed_policy"]["input_seed"]),
        trajectory_index,
    )
    U = controlled_duffing_random_zoh_input(
        spec.trajectory_length;
        amplitude = Float64(input_config["amplitude"]),
        hold_steps = Int(input_config["hold_steps"]),
        seed = seed,
    )
    times, X = generate_controlled_duffing_trajectory(spec, x0, U)
    parameter_instance = Dict{String,Any}(
        "delta" => spec.delta,
        "alpha" => spec.alpha,
        "beta" => spec.beta,
        "input_gain" => spec.input_gain,
        "parameter_instance_id" => string("beta_", replace(string(spec.beta), "." => "p")),
    )
    raw = RawControlledTrajectory(
        make_trajectory_id(spec.system_id, trajectory_index),
        spec.system_id,
        parameter_instance,
        Float64.(x0),
        seed,
        times,
        X,
        U,
    )
    validate_raw_controlled_trajectory(raw)
    return raw
end

function generate_controlled_duffing_raw_trajectories(system_config::AbstractDict)
    base_spec = controlled_duffing_spec_from_config(system_config)
    validate_controlled_duffing_spec(base_spec)
    beta_values = controlled_duffing_beta_values(system_config)
    x0_values = controlled_duffing_initial_conditions(system_config)
    expected_count = length(beta_values) * length(x0_values)
    expected_count == Int(system_config["num_trajectories"]) ||
        throw(ArgumentError("num_trajectories must equal beta count times initial-condition count"))

    raw_trajectories = RawControlledTrajectory[]
    trajectory_index = 1
    for beta in beta_values
        spec = controlled_duffing_spec_with_beta(system_config, beta)
        validate_controlled_duffing_spec(spec)
        for x0 in x0_values
            push!(
                raw_trajectories,
                build_controlled_duffing_raw_trajectory(spec, system_config, trajectory_index, x0),
            )
            trajectory_index += 1
        end
    end

    return base_spec, raw_trajectories
end

## Clean and noisy observed trajectory generation

function generate_controlled_duffing_observed_by_id(
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    observation_configs::AbstractVector{<:AbstractDict},
    state_dim::Integer,
    input_dim::Integer,
)
    observed_by_id = Dict{String,Vector{ObservedControlledTrajectory}}()
    specs = ControlledFullStateObservationSpec[]
    for config in observation_configs
        spec = controlled_full_state_observation_spec_from_config(config)
        validate_controlled_full_state_observation_spec(spec, state_dim, input_dim)
        observed = [
            apply_controlled_full_state_observation(raw, spec)
            for raw in raw_trajectories
        ]
        foreach(validate_observed_controlled_trajectory, observed)
        observed_by_id[spec.observation_id] = observed
        push!(specs, spec)
    end
    return specs, observed_by_id
end

## Split and window summary construction

function build_controlled_duffing_split(
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    split_config::AbstractDict,
)
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

function build_controlled_duffing_beta_split(
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    split_config::AbstractDict,
)
    beta_ids(beta_values) = [
        traj.trajectory_id for traj in raw_trajectories
        if Float64(traj.parameter_instance["beta"]) in Float64.(beta_values)
    ]

    split = Dict(
        "split_id" => String(split_config["split_id"]),
        "split_type" => String(split_config["split_type"]),
        "grouping_unit" => "trajectory",
        "parameter_name" => "beta",
        "train_beta_values" => Float64.(split_config["train_beta_values"]),
        "val_beta_values" => Float64.(split_config["val_beta_values"]),
        "test_beta_values" => Float64.(split_config["test_beta_values"]),
        "train_trajectory_ids" => beta_ids(split_config["train_beta_values"]),
        "val_trajectory_ids" => beta_ids(split_config["val_beta_values"]),
        "test_trajectory_ids" => beta_ids(split_config["test_beta_values"]),
    )

    all_ids = [traj.trajectory_id for traj in raw_trajectories]
    validate_trajectory_split(split, all_ids)
    isempty(intersect(Set(split["train_beta_values"]), Set(split["test_beta_values"]))) ||
        throw(ArgumentError("Split-P beta train and test beta sets must be disjoint"))
    return split
end

function build_controlled_duffing_window_summary(
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
            window_id = string("duffing_controlled_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("duffing_controlled_rollout_h", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => trajectory_length + 1 - horizon,
        )
    end

    return Dict(
        "window_id" => window_config["window_id"],
        "alignment_convention" => "(z_m, u_m, z_{m+1}) with u_m held on [t_m, t_{m+1})",
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
    )
end

## Raw and processed data saving

function save_controlled_duffing_raw(
    path::AbstractString,
    raw_trajectories::AbstractVector{RawControlledTrajectory},
)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        input_seeds = [traj.input_seed for traj in raw_trajectories],
        times = first(raw_trajectories).times,
        state_tensor = controlled_duffing_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        input_tensor = controlled_duffing_matrix_tensor([traj.input_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory and input_dim_by_step_by_trajectory",
        input_convention = "input_tensor[:, m, r] acts from times[m] to times[m+1]",
    )
    return path
end

function save_controlled_duffing_observed(
    path::AbstractString,
    observed_trajectories::AbstractVector{ObservedControlledTrajectory},
)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in observed_trajectories],
        system_id = first(observed_trajectories).system_id,
        observation_id = first(observed_trajectories).observation_id,
        noise_level_id = first(observed_trajectories).noise_level_id,
        parameter_instances = [traj.parameter_instance for traj in observed_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in observed_trajectories]...),
        input_seeds = [traj.input_seed for traj in observed_trajectories],
        state_tensor = controlled_duffing_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        input_tensor = controlled_duffing_matrix_tensor([traj.input_matrix for traj in observed_trajectories]),
        observation_tensor = controlled_duffing_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        observed_input_tensor = controlled_duffing_matrix_tensor([traj.observed_input_matrix for traj in observed_trajectories]),
        state_noise_tensor = controlled_duffing_matrix_tensor([traj.state_noise_matrix for traj in observed_trajectories]),
        input_noise_tensor = controlled_duffing_matrix_tensor([traj.input_noise_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory and input_dim_by_step_by_trajectory",
        one_step_contract = "(observation_tensor[:, m, r], observed_input_tensor[:, m, r], observation_tensor[:, m+1, r])",
    )
    return path
end

function controlled_duffing_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_controlled_duffing_single_row_csv(
    path::AbstractString,
    columns::AbstractVector,
    values::AbstractVector,
)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(controlled_duffing_csv_value.(values), ","))
    end
    return path
end

## Optional smoke diagnostic plots

function maybe_save_controlled_duffing_plots(
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    observed_by_id::AbstractDict{String,<:AbstractVector{ObservedControlledTrajectory}},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)
        noisy = first(observed_by_id["duffing_controlled_fullstate_noise_s1"])

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["q(t)" "v(t)"],
            title = string("Controlled Duffing ", run_label, " state trajectory"),
        )
        time_path = joinpath(plot_dir, string(run_label, "_time_series.png"))
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_input = Main.Plots.plot(
            first_raw.times[1:(end - 1)],
            vec(first_raw.input_matrix);
            xlabel = "t",
            ylabel = "u",
            label = false,
            title = string("Controlled Duffing ", run_label, " ZOH input"),
        )
        input_path = joinpath(plot_dir, string(run_label, "_input.png"))
        Main.Plots.savefig(p_input, input_path)
        push!(plot_files, input_path)

        p_phase = Main.Plots.plot(
            ;
            xlabel = "q",
            ylabel = "v",
            title = string("Controlled Duffing ", run_label, " phase portrait"),
        )
        for traj in raw_trajectories
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, string(run_label, "_phase_portrait.png"))
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        p_noise = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix[1, :];
            xlabel = "t",
            ylabel = "q",
            label = "clean q",
            title = string("Controlled Duffing ", run_label, " clean/noisy observation check"),
        )
        Main.Plots.plot!(p_noise, first_raw.times, noisy.observation_matrix[1, :]; label = "noisy q")
        noise_path = joinpath(plot_dir, string(run_label, "_noise_check.png"))
        Main.Plots.savefig(p_noise, noise_path)
        push!(plot_files, noise_path)

        return plot_files
    catch err
        @warn "Skipping controlled Duffing plots because plot generation failed" exception = err
        return String[]
    end
end

## Manifest and output writing

function make_controlled_duffing_manifest(;
    configs::AbstractDict,
    spec::ControlledDuffingSpec,
    observation_specs::AbstractVector{ControlledFullStateObservationSpec},
    split::AbstractDict,
    window_summary::AbstractDict,
    generated_files::AbstractDict,
    diagnostics::AbstractDict,
)
    benchmark_config = configs["benchmark"]
    system_config = configs["system"]
    return Dict(
        "dataset_version" => benchmark_config["release_version"],
        "created_at" => string(now()),
        "benchmark_id" => benchmark_config["benchmark_id"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "input_dim" => spec.input_dim,
        "observation_ids" => [spec.observation_id for spec in observation_specs],
        "noise_level_ids" => [spec.noise_level_id for spec in observation_specs],
        "delta_default" => spec.delta,
        "alpha_default" => spec.alpha,
        "beta_default" => spec.beta,
        "input_gain_default" => spec.input_gain,
        "parameter_domain" => system_config["parameter_domain"],
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "num_raw_trajectories" => Int(system_config["num_trajectories"]),
        "input_policy" => system_config["input_policy"],
        "initial_condition_policy" => system_config["initial_condition_domain"],
        "split_id" => split["split_id"],
        "window_ids" => benchmark_config["window_ids"],
        "task_ids" => benchmark_config["task_ids"],
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "seed_policy" => system_config["seed_policy"],
        "array_layout" => "state_dim_by_time_by_trajectory and input_dim_by_step_by_trajectory",
        "input_convention" => "U[:, m] is held on [t_m, t_{m+1})",
        "one_step_contract" => "(z_m, u_m, z_{m+1})",
        "system_metadata" => controlled_duffing_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_controlled_duffing_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::ControlledDuffingSpec,
    observation_specs::AbstractVector{ControlledFullStateObservationSpec},
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    observed_by_id::AbstractDict{String,<:AbstractVector{ObservedControlledTrajectory}},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = controlled_duffing_project_path(project_root, output_policy["raw_path"])
    split_path = controlled_duffing_project_path(project_root, output_policy["split_path"])
    windows_summary_path = controlled_duffing_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = controlled_duffing_project_path(project_root, output_policy["manifest_path"])
    release_index_path = controlled_duffing_project_path(project_root, output_policy["release_index_path"])

    task_dir = run_label == "formal" ? "duffing_controlled_edmdc_formal" : "duffing_controlled_edmdc_smoke"
    report_root = joinpath(project_root, "reports", "v1_core", task_dir)
    table_path = joinpath(report_root, "tables", "diagnostics.csv")
    plot_dir = joinpath(report_root, "plots")
    log_path = joinpath(report_root, "logs", string(run_label, ".log"))

    save_controlled_duffing_raw(raw_path, raw_trajectories)

    processed_files = Dict{String,Any}()
    for spec in observation_specs
        relative_path = replace(output_policy["processed_path_template"], "{observation_id}" => spec.observation_id)
        path = controlled_duffing_project_path(project_root, relative_path)
        save_controlled_duffing_observed(path, observed_by_id[spec.observation_id])
        processed_files[spec.observation_id] = path
    end

    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)
    plot_files = maybe_save_controlled_duffing_plots(raw_trajectories, observed_by_id, plot_dir, run_label)

    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories_by_observation" => processed_files,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_controlled_duffing_manifest(
        configs = configs,
        spec = spec,
        observation_specs = observation_specs,
        split = split,
        window_summary = window_summary,
        generated_files = generated_files,
        diagnostics = diagnostics,
    )
    write_json_file(manifest_path, manifest)

    release_index = Dict(
        "release_id" => string("duffing_controlled_edmdc_v1_", run_label),
        "release_version" => configs["benchmark"]["release_version"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "raw_path" => raw_path,
        "processed_paths" => processed_files,
        "manifest_path" => manifest_path,
        "created_at" => string(now()),
    )
    write_json_file(release_index_path, release_index)

    columns, values = controlled_duffing_diagnostics_csv_row(spec, diagnostics)
    write_controlled_duffing_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_ids: ", [spec.observation_id for spec in observation_specs])
        println(io, "raw state size: ", diagnostics["raw_state_size"])
        println(io, "raw input size: ", diagnostics["raw_input_size"])
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "input mean/std/absmax: ", (diagnostics["input_mean"], diagnostics["input_std"], diagnostics["input_abs_max"]))
        println(io, "noise diagnostics: ", diagnostics["observations"])
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "manifest_path: ", manifest_path)
    end

    return Dict(
        "raw_path" => raw_path,
        "processed_files" => processed_files,
        "split_path" => split_path,
        "windows_summary_path" => windows_summary_path,
        "manifest_path" => manifest_path,
        "release_index_path" => release_index_path,
        "table_path" => table_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end
