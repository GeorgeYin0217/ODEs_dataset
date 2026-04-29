## Generator scope and entry points

using Dates
using LinearAlgebra
using Random

function vanderpol_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Random seed initialization and initial-condition sampling

function vanderpol_rng(config::AbstractDict)
    return MersenneTwister(Int(config["seed_policy"]["generation_seed"]))
end

function validate_vanderpol_box_domain(domain::AbstractDict)
    String(domain["type"]) == "box" ||
        throw(ArgumentError("initial_condition_domain type must be box"))
    length(domain["lower"]) == 2 || throw(ArgumentError("lower must have two entries"))
    length(domain["upper"]) == 2 || throw(ArgumentError("upper must have two entries"))
    all(Float64.(domain["lower"]) .< Float64.(domain["upper"])) ||
        throw(ArgumentError("each lower bound must be smaller than upper bound"))
    Float64(domain["min_norm"]) >= 0 || throw(ArgumentError("min_norm must be nonnegative"))
    return true
end

function sample_vanderpol_initial_condition(rng::AbstractRNG, domain::AbstractDict)
    validate_vanderpol_box_domain(domain)
    lower = Float64.(domain["lower"])
    upper = Float64.(domain["upper"])
    min_norm = Float64(domain["min_norm"])

    for _ in 1:10_000
        x0 = lower .+ (upper .- lower) .* rand(rng, 2)
        norm(x0) >= min_norm && return x0
    end

    throw(ArgumentError("failed to sample an initial condition above min_norm"))
end

## Parameter-instance sampling

function vanderpol_mu_values(system_config::AbstractDict)
    n = Int(system_config["num_trajectories"])
    if haskey(system_config, "parameter_sampling")
        sampling = system_config["parameter_sampling"]
        sampling_type = String(sampling["type"])
        if sampling_type == "linspace"
            lower = Float64(sampling["lower"])
            upper = Float64(sampling["upper"])
            lower <= upper || throw(ArgumentError("parameter_sampling lower must be <= upper"))
            return collect(range(lower, upper; length = n))
        elseif sampling_type == "fixed"
            return fill(Float64(system_config["default_parameters"]["mu"]), n)
        else
            throw(ArgumentError("unsupported Van der Pol parameter_sampling type: $(sampling_type)"))
        end
    else
        return fill(Float64(system_config["default_parameters"]["mu"]), n)
    end
end

## Raw and observed trajectory generation

function build_vanderpol_raw_trajectory(
    spec::VanDerPolUnforcedSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_vanderpol_unforced_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}("mu" => spec.mu)
    return RawTrajectory(
        make_trajectory_id(spec.system_id, trajectory_index),
        spec.system_id,
        parameter_instance,
        Float64.(x0),
        times,
        X,
    )
end

function validate_vanderpol_raw_trajectory_dimensions(spec::VanDerPolUnforcedSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    return true
end

function generate_vanderpol_raw_trajectories(system_config::AbstractDict)
    base_spec = vanderpol_unforced_spec_from_config(system_config)
    validate_vanderpol_unforced_spec(base_spec)
    rng = vanderpol_rng(system_config)
    ic_domain = system_config["initial_condition_domain"]
    mu_values = vanderpol_mu_values(system_config)

    raw_trajectories = RawTrajectory[]
    for q in 1:length(mu_values)
        spec = vanderpol_unforced_spec_with_mu(base_spec, mu_values[q])
        validate_vanderpol_unforced_spec(spec)
        x0 = sample_vanderpol_initial_condition(rng, ic_domain)
        raw = build_vanderpol_raw_trajectory(spec, q, x0)
        validate_vanderpol_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return base_spec, raw_trajectories
end

function generate_vanderpol_observed_trajectories(
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

function build_vanderpol_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_vanderpol_parameter_split(
    raw_trajectories::AbstractVector{RawTrajectory},
    split_config::AbstractDict,
)
    parameter_name = String(get(split_config, "parameter_name", "mu"))
    split_type = String(split_config["split_type"])
    split_type == "parameter" || throw(ArgumentError("parameter split requires split_type=parameter"))

    sorted = sort(
        collect(raw_trajectories);
        by = traj -> Float64(traj.parameter_instance[parameter_name]),
    )
    trajectory_ids = [traj.trajectory_id for traj in sorted]
    validate_split_ratios(
        Float64(split_config["train_ratio"]),
        Float64(split_config["val_ratio"]),
        Float64(split_config["test_ratio"]),
    )
    n_train, n_val, n_test = split_counts(
        length(trajectory_ids),
        (
            Float64(split_config["train_ratio"]),
            Float64(split_config["val_ratio"]),
            Float64(split_config["test_ratio"]),
        ),
    )

    split = Dict(
        "split_id" => String(split_config["split_id"]),
        "split_type" => split_type,
        "grouping_unit" => "trajectory",
        "seed" => Int(split_config["seed"]),
        "train_ratio" => Float64(split_config["train_ratio"]),
        "val_ratio" => Float64(split_config["val_ratio"]),
        "test_ratio" => Float64(split_config["test_ratio"]),
        "train_trajectory_ids" => trajectory_ids[1:n_train],
        "val_trajectory_ids" => trajectory_ids[(n_train + 1):(n_train + n_val)],
        "test_trajectory_ids" => trajectory_ids[(n_train + n_val + 1):(n_train + n_val + n_test)],
    )
    validate_trajectory_split(split, trajectory_ids)

    parameter_by_id = Dict(
        traj.trajectory_id => Float64(traj.parameter_instance[parameter_name])
        for traj in sorted
    )
    split["parameter_name"] = parameter_name
    split["parameter_ranges"] = Dict(
        split_name => Dict(
            "min" => minimum(parameter_by_id[id] for id in split[string(split_name, "_trajectory_ids")]),
            "max" => maximum(parameter_by_id[id] for id in split[string(split_name, "_trajectory_ids")]),
            "values" => [parameter_by_id[id] for id in split[string(split_name, "_trajectory_ids")]],
        )
        for split_name in ("train", "val", "test")
    )

    train_max = split["parameter_ranges"]["train"]["max"]
    val_min = split["parameter_ranges"]["val"]["min"]
    val_max = split["parameter_ranges"]["val"]["max"]
    test_min = split["parameter_ranges"]["test"]["min"]
    train_max < val_min || throw(ArgumentError("Split-P train and val parameter ranges overlap"))
    val_max < test_min || throw(ArgumentError("Split-P val and test parameter ranges overlap"))
    return split
end

function build_vanderpol_window_summary(
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
            window_id = string("vanderpol_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("vanderpol_rollout_h", horizon),
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

function vanderpol_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_vanderpol_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = vanderpol_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_vanderpol_observed(
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
        state_tensor = vanderpol_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = vanderpol_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function vanderpol_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_vanderpol_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(vanderpol_csv_value.(values), ","))
    end
    return path
end

function maybe_save_vanderpol_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping Van der Pol plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping Van der Pol plots because Plots.jl was not imported"
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
            label = ["x1(t)" "x2(t)"],
            title = "Van der Pol time series",
        )
        time_path = joinpath(plot_dir, "vanderpol_time_series.png")
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_phase = Main.Plots.plot(; xlabel = "x1", ylabel = "x2", title = "Van der Pol phase portrait")
        for traj in raw_trajectories[1:min(8, length(raw_trajectories))]
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, "vanderpol_phase_portrait.png")
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        return plot_files
    catch err
        @warn "Skipping Van der Pol plots because plot generation failed" exception = err
        return String[]
    end
end

function make_vanderpol_manifest(;
    configs::AbstractDict,
    spec::VanDerPolUnforcedSpec,
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
        "mu_default" => spec.mu,
        "parameter_domain" => system_config["parameter_domain"],
        "parameter_sampling" => get(system_config, "parameter_sampling", Dict("type" => "fixed")),
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
        "system_metadata" => vanderpol_unforced_metadata(spec),
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_vanderpol_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::VanDerPolUnforcedSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = vanderpol_project_path(project_root, output_policy["raw_path"])
    processed_path = vanderpol_project_path(project_root, output_policy["processed_path"])
    split_path = vanderpol_project_path(project_root, output_policy["split_path"])
    windows_summary_path = vanderpol_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = vanderpol_project_path(project_root, output_policy["manifest_path"])
    release_index_path = vanderpol_project_path(project_root, output_policy["release_index_path"])

    report_root = joinpath(project_root, "reports", "v1_core", "vanderpol_unforced_fullobs_v1")
    table_path = joinpath(report_root, "tables", "smoke", "diagnostics.csv")
    plot_dir = joinpath(report_root, "plots", "smoke")
    log_path = joinpath(report_root, "logs", "smoke.log")

    save_vanderpol_raw(raw_path, raw_trajectories)
    save_vanderpol_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_vanderpol_plots(raw_trajectories, plot_dir)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_vanderpol_manifest(
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
        "release_id" => "vanderpol_unforced_fullobs_v1_smoke",
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

    columns, values = vanderpol_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_vanderpol_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(vanderpol_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "statistics window counts: ", diagnostics["statistics_window_counts"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "state norm max: ", diagnostics["state_norm_max"])
        println(io, "rk4 self residual max: ", diagnostics["rk4_self_residual_max"])
        println(io, "tail sign changes min: ", diagnostics["tail_x1_sign_changes_min"])
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
