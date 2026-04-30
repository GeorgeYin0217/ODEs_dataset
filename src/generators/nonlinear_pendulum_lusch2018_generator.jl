## Input configuration parsing

using Dates
using Random
using Statistics

function pendulum_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Candidate initial-condition sampling

function sample_nonlinear_pendulum_initial_conditions(system_config::AbstractDict)
    spec = nonlinear_pendulum_lusch2018_spec_from_config(system_config)
    validate_nonlinear_pendulum_lusch2018_spec(spec)
    domain = system_config["initial_condition_domain"]
    String(domain["type"]) == "uniform_rejection_energy" ||
        throw(ArgumentError("pendulum generator expects initial_condition_domain type uniform_rejection_energy"))

    num_trajectories = Int(system_config["num_trajectories"])
    max_candidates = Int(get(domain, "max_candidates", 100 * num_trajectories))
    rng = MersenneTwister(Int(system_config["seed_policy"]["generation_seed"]))
    accepted = Vector{Float64}[]
    candidate_count = 0

    while length(accepted) < num_trajectories && candidate_count < max_candidates
        candidate_count += 1
        x1 = spec.x1_min + rand(rng) * (spec.x1_max - spec.x1_min)
        x2 = spec.x2_min + rand(rng) * (spec.x2_max - spec.x2_min)
        x0 = [x1, x2]
        if nonlinear_pendulum_initial_condition_is_admissible(spec, x0)
            push!(accepted, x0)
        end
    end

    length(accepted) == num_trajectories ||
        throw(ArgumentError("rejection sampler did not reach the requested trajectory count"))

    return accepted, Dict(
        "candidate_count" => candidate_count,
        "accepted_count" => length(accepted),
        "rejected_count" => candidate_count - length(accepted),
        "acceptance_rate" => length(accepted) / candidate_count,
        "seed" => Int(system_config["seed_policy"]["generation_seed"]),
        "policy" => "uniform_box_rejection_by_H_lt_threshold",
        "energy_threshold" => spec.energy_threshold,
    )
end

## Energy-based rejection filtering

function validate_pendulum_raw_trajectory_dimensions(
    spec::NonlinearPendulumLusch2018Spec,
    traj::RawTrajectory,
)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length ||
        throw(ArgumentError("times length must match trajectory_length snapshot count"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    return true
end

## Trajectory integration and snapshot extraction

function build_pendulum_raw_trajectory(
    spec::NonlinearPendulumLusch2018Spec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_nonlinear_pendulum_lusch2018_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "hamiltonian_initial" => nonlinear_pendulum_hamiltonian(spec, x0),
        "energy_threshold" => spec.energy_threshold,
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

## RawTrajectory assembly

function generate_pendulum_raw_trajectories(system_config::AbstractDict)
    spec = nonlinear_pendulum_lusch2018_spec_from_config(system_config)
    validate_nonlinear_pendulum_lusch2018_spec(spec)
    x0_values, sampling_statistics = sample_nonlinear_pendulum_initial_conditions(system_config)

    raw_trajectories = RawTrajectory[]
    for (q, x0) in enumerate(x0_values)
        raw = build_pendulum_raw_trajectory(spec, q, x0)
        validate_pendulum_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories, sampling_statistics
end

## ObservedTrajectory assembly

function generate_pendulum_observed_trajectories(
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

## Split and window generation

function build_pendulum_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_pendulum_window_summary(
    split::AbstractDict,
    transition_count::Integer,
    snapshot_count::Integer,
    window_config::AbstractDict,
)
    one_step = window_config["one_step"]
    one_step_windows = build_one_step_windows(
        split,
        transition_count;
        window_id = one_step["window_id"],
        lag = Int(one_step["lag"]),
    )
    validate_window_indices(one_step_windows, split, transition_count)

    rollout_summaries = Dict{String,Any}()
    for horizon in Int.(window_config["rollout"]["horizons"])
        rollout_windows = build_rollout_windows(
            split,
            transition_count;
            window_id = string("pendulum_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, transition_count)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("pendulum_rollout_h", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => transition_count + 1 - horizon,
        )
    end

    statistics_config = window_config["statistics"]
    statistics_windows = build_statistics_windows(
        split,
        transition_count;
        window_id = statistics_config["window_id"],
        horizon = Int(statistics_config["horizon"]),
    )
    validate_window_indices(statistics_windows, split, transition_count)

    return Dict(
        "window_id" => window_config["window_id"],
        "snapshot_count" => snapshot_count,
        "transition_count" => transition_count,
        "one_step" => Dict(
            "window_id" => one_step["window_id"],
            "lag" => Int(one_step["lag"]),
            "counts" => window_counts(one_step_windows),
            "samples_per_trajectory" => transition_count,
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
            "starts_per_trajectory" => transition_count + 2 - Int(statistics_config["horizon"]),
        ),
    )
end

## Sampling statistics and acceptance-rate summary

function pendulum_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_pendulum_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = pendulum_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_pendulum_observed(
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
        state_tensor = pendulum_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = pendulum_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function pendulum_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_pendulum_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(pendulum_csv_value.(values), ","))
    end
    return path
end

function write_pendulum_split_window_counts_csv(
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

function write_pendulum_energy_summary_csv(path::AbstractString, diagnostics::AbstractDict)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, "quantity,value")
        for key in (
            "initial_energy_min",
            "initial_energy_max",
            "initial_energy_mean",
            "initial_energy_std",
            "energy_drift_max",
            "energy_drift_mean",
            "energy_drift_p95",
            "max_energy_seen",
            "separatrix_violation_count",
        )
            println(io, key, ",", diagnostics[key])
        end
    end
    return path
end

## Optional plots for smoke inspection

function maybe_save_pendulum_plots(
    spec::NonlinearPendulumLusch2018Spec,
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping pendulum plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping pendulum plots because Plots.jl was not imported"
        end
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        selected = raw_trajectories[1:min(12, length(raw_trajectories))]
        first_raw = first(raw_trajectories)

        p_phase = Main.Plots.plot(;
            xlabel = "x1",
            ylabel = "x2",
            title = string("Pendulum ", run_label, " phase portrait"),
            legend = false,
        )
        for traj in selected
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :])
        end
        phase_path = joinpath(plot_dir, "pendulum_phase_portrait.png")
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["x1(t)" "x2(t)"],
            title = string("Pendulum ", run_label, " time series"),
        )
        time_path = joinpath(plot_dir, "pendulum_time_series.png")
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        energies = [
            nonlinear_pendulum_hamiltonian(traj.initial_condition_instance[1], traj.initial_condition_instance[2])
            for traj in raw_trajectories
        ]
        p_hist = Main.Plots.histogram(
            energies;
            bins = 12,
            xlabel = "H(x0)",
            ylabel = "count",
            label = false,
            title = string("Pendulum ", run_label, " initial energy"),
        )
        hist_path = joinpath(plot_dir, "pendulum_initial_energy_histogram.png")
        Main.Plots.savefig(p_hist, hist_path)
        push!(plot_files, hist_path)

        p_energy = Main.Plots.plot(;
            xlabel = "t",
            ylabel = "H(x)-H(x0)",
            title = string("Pendulum ", run_label, " energy drift"),
            legend = false,
        )
        for traj in selected
            sequence = pendulum_energy_sequence(spec, traj)
            Main.Plots.plot!(p_energy, traj.times, sequence .- first(sequence))
        end
        drift_path = joinpath(plot_dir, "pendulum_energy_drift.png")
        Main.Plots.savefig(p_energy, drift_path)
        push!(plot_files, drift_path)

        return plot_files
    catch err
        @warn "Skipping pendulum plots because plot generation failed" exception = err
        return String[]
    end
end

function maybe_save_pendulum_animation(
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "medium",
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping pendulum animation because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping pendulum animation because Plots.jl was not imported"
        end
        return ""
    end

    try
        mkpath(plot_dir)
        energies = [
            nonlinear_pendulum_hamiltonian(traj.initial_condition_instance[1], traj.initial_condition_instance[2])
            for traj in raw_trajectories
        ]
        representative_index = argmin(abs.(energies .- median(energies)))
        traj = raw_trajectories[representative_index]
        frame_count = size(traj.state_matrix, 2)
        anim = Main.Plots.Animation()

        for m in 1:frame_count
            theta = traj.state_matrix[1, m]
            bob_x = sin(theta)
            bob_y = -cos(theta)
            p = Main.Plots.plot(;
                xlabel = "horizontal position",
                ylabel = "vertical position",
                xlim = (-1.15, 1.15),
                ylim = (-1.15, 0.25),
                aspect_ratio = :equal,
                title = string("Pendulum ", run_label, " frame ", m, "/", frame_count),
                legend = false,
            )
            Main.Plots.plot!(p, [0.0, bob_x], [0.0, bob_y]; linewidth = 3)
            Main.Plots.scatter!(p, [0.0], [0.0]; markersize = 4)
            Main.Plots.scatter!(p, [bob_x], [bob_y]; markersize = 10)
            Main.Plots.frame(anim, p)
        end

        animation_path = joinpath(plot_dir, string("pendulum_physical_animation_", run_label, ".gif"))
        Main.Plots.gif(anim, animation_path; fps = 15)
        return animation_path
    catch err
        @warn "Skipping pendulum animation because GIF generation failed" exception = err
        return ""
    end
end

function write_pendulum_markdown_report(
    path::AbstractString,
    diagnostics::AbstractDict,
    output_paths::AbstractDict,
    animation_path::AbstractString,
)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, "# Nonlinear Pendulum Lusch2018 Medium Dataset Report")
        println(io)
        println(io, "## Task Summary")
        println(io)
        println(io, "Generated the Lusch-aligned undamped nonlinear pendulum dataset with full-state clean observations. The system is x1_dot = x2 and x2_dot = -sin(x1), with tau = 0.02, t in [0, 1], and 51 snapshots per trajectory.")
        println(io)
        println(io, "## Configuration")
        println(io)
        println(io, "- System ID: `", diagnostics["system_id"], "`")
        println(io, "- Scope: `", diagnostics["family"], "`")
        println(io, "- Variant: `", diagnostics["variant"], "`")
        println(io, "- Number of trajectories: ", diagnostics["num_trajectories"])
        println(io, "- Snapshot count: ", diagnostics["trajectory_length"])
        println(io, "- Transition count: ", diagnostics["transition_count"])
        println(io, "- Acceptance rate: ", diagnostics["acceptance_rate"])
        println(io)
        println(io, "## Validation Results")
        println(io)
        println(io, "- State matrix size: `", diagnostics["state_matrix_size"], "`")
        println(io, "- Full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "- Initial energy range: [", diagnostics["initial_energy_min"], ", ", diagnostics["initial_energy_max"], "]")
        println(io, "- Energy drift max: ", diagnostics["energy_drift_max"])
        println(io, "- Energy drift p95: ", diagnostics["energy_drift_p95"])
        println(io, "- Separatrix violation count: ", diagnostics["separatrix_violation_count"])
        println(io, "- Energy band counts: low=", diagnostics["low_energy_count"], ", mid=", diagnostics["mid_energy_count"], ", high=", diagnostics["high_energy_count"])
        println(io, "- Near-separatrix initial count: ", diagnostics["near_separatrix_count"])
        println(io, "- Medium validation passed: ", diagnostics["medium_passed"])
        println(io)
        println(io, "## Split And Window Counts")
        println(io)
        println(io, "- Split counts: `", diagnostics["split_counts"], "`")
        println(io, "- One-step counts: `", diagnostics["one_step_window_counts"], "`")
        println(io, "- Rollout counts: `", diagnostics["rollout_window_counts"], "`")
        println(io, "- Statistics counts: `", diagnostics["statistics_window_counts"], "`")
        println(io)
        println(io, "## Animation")
        println(io)
        if isempty(animation_path)
            println(io, "Animation generation was skipped or failed. See the run log for details.")
        else
            println(io, "![Nonlinear pendulum physical animation](../plots/", basename(animation_path), ")")
        end
        println(io)
        println(io, "## Generated Files")
        println(io)
        for key in sort(collect(keys(output_paths)))
            println(io, "- `", key, "`: `", output_paths[key], "`")
        end
    end
    return path
end

function make_pendulum_manifest(;
    configs::AbstractDict,
    spec::NonlinearPendulumLusch2018Spec,
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
        "parameter_domain" => system_config["parameter_domain"],
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "transition_count" => pendulum_transition_count(spec),
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
        "system_metadata" => nonlinear_pendulum_lusch2018_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

## Raw, processed, manifest, and report saving

function save_pendulum_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::NonlinearPendulumLusch2018Spec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    run_label = String(configs["benchmark"]["difficulty_level"])
    raw_path = pendulum_project_path(project_root, output_policy["raw_path"])
    processed_path = pendulum_project_path(project_root, output_policy["processed_path"])
    split_path = pendulum_project_path(project_root, output_policy["split_path"])
    windows_summary_path = pendulum_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = pendulum_project_path(project_root, output_policy["manifest_path"])
    release_index_path = pendulum_project_path(project_root, output_policy["release_index_path"])

    report_root = joinpath(project_root, "reports", "v1_plus", string("nonlinear_pendulum_lusch2018_", run_label))
    table_dir = joinpath(report_root, "tables")
    table_path = joinpath(table_dir, "diagnostics.csv")
    energy_summary_path = joinpath(table_dir, "energy_summary.csv")
    split_window_counts_path = joinpath(table_dir, "split_window_counts.csv")
    plot_dir = joinpath(report_root, "plots")
    report_path = joinpath(report_root, "notebooks", string("nonlinear_pendulum_lusch2018_", run_label, "_report.md"))
    log_path = joinpath(report_root, "logs", string(run_label, ".log"))

    save_pendulum_raw(raw_path, raw_trajectories)
    save_pendulum_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_pendulum_plots(spec, raw_trajectories, plot_dir, run_label)
    animation_path = maybe_save_pendulum_animation(raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "energy_summary_table" => energy_summary_path,
        "split_window_counts_table" => split_window_counts_path,
        "report" => report_path,
        "animation" => animation_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_pendulum_manifest(
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
        "release_id" => string("nonlinear_pendulum_lusch2018_fullobs_v1_plus_", run_label),
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

    columns, values = pendulum_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_pendulum_single_row_csv(table_path, columns, values)
    write_pendulum_energy_summary_csv(energy_summary_path, diagnostics)
    write_pendulum_split_window_counts_csv(split_window_counts_path, split, window_summary)
    output_paths_for_report = Dict(
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "split_path" => split_path,
        "windows_summary_path" => windows_summary_path,
        "manifest_path" => manifest_path,
        "release_index_path" => release_index_path,
        "table_path" => table_path,
        "energy_summary_path" => energy_summary_path,
        "split_window_counts_path" => split_window_counts_path,
        "animation_path" => animation_path,
        "log_path" => log_path,
    )
    write_pendulum_markdown_report(report_path, diagnostics, output_paths_for_report, animation_path)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(pendulum_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "sampling statistics: ", diagnostics["sampling_statistics"])
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "initial energy range: [", diagnostics["initial_energy_min"], ", ", diagnostics["initial_energy_max"], "]")
        println(io, "energy drift max: ", diagnostics["energy_drift_max"])
        println(io, "energy band counts: low=", diagnostics["low_energy_count"], ", mid=", diagnostics["mid_energy_count"], ", high=", diagnostics["high_energy_count"])
        println(io, "near separatrix count: ", diagnostics["near_separatrix_count"])
        println(io, "separatrix violation count: ", diagnostics["separatrix_violation_count"])
        println(io, "plot files: ", plot_files)
        println(io, "animation path: ", animation_path)
        println(io, "report path: ", report_path)
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "medium_passed: ", diagnostics["medium_passed"])
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
        "energy_summary_path" => energy_summary_path,
        "split_window_counts_path" => split_window_counts_path,
        "animation_path" => animation_path,
        "report_path" => report_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end
