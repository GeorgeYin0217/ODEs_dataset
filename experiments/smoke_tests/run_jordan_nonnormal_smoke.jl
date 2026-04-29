## Smoke run purpose

using Dates
using JSON
using Printf
using Random

const PLOTS_LOAD_ERROR = Ref{Any}(nothing)
const PLOTS_AVAILABLE = try
    @eval import Plots
    true
catch err
    PLOTS_LOAD_ERROR[] = err
    false
end

const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(PROJECT_ROOT, "src", "dynamics", "jordan_nonnormal_linear.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "jordan_nonnormal_diagnostics.jl"))

## Load smoke benchmark configuration

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function project_path(relative_path::AbstractString)
    return joinpath(PROJECT_ROOT, split(relative_path, '/')...)
end

function load_jordan_smoke_configs()
    benchmark_config = load_config(
        "benchmarks",
        "unit_internal",
        "jordan_nonnormal_smoke_benchmark.json",
    )

    return Dict(
        "benchmark" => benchmark_config,
        "system" => load_config("systems", "unit_internal", "jordan_nonnormal_linear_smoke.json"),
        "observation" => load_config("observations", "unit_internal", "full_state_identity_clean.json"),
        "split" => load_config("splits", "unit_internal", "jordan_split_i_smoke.json"),
        "one_step_window" => load_config("windows", "unit_internal", "one_step_lag1.json"),
        "rollout_window" => load_config("windows", "unit_internal", "jordan_rollout_smoke.json"),
        "tasks" => [
            load_config("tasks", "unit_internal", "jordan_one_step_forecast.json"),
            load_config("tasks", "unit_internal", "jordan_rollout_forecast.json"),
        ],
    )
end

## Resolve all dependent configuration paths

function validate_jordan_initial_condition_domain(domain::AbstractDict)
    String(domain["type"]) == "box_with_x2_activation" ||
        throw(ArgumentError("initial_condition_domain type must be box_with_x2_activation"))
    Float64(domain["x1_lower"]) < Float64(domain["x1_upper"]) ||
        throw(ArgumentError("x1_lower must be smaller than x1_upper"))
    Float64(domain["x2_abs_lower"]) > 0 ||
        throw(ArgumentError("x2_abs_lower must be positive"))
    Float64(domain["x2_abs_lower"]) < Float64(domain["x2_abs_upper"]) ||
        throw(ArgumentError("x2_abs_lower must be smaller than x2_abs_upper"))
    return true
end

function jordan_rng(config::AbstractDict)
    return MersenneTwister(Int(config["seed_policy"]["generation_seed"]))
end

function sample_jordan_initial_condition(rng::AbstractRNG, domain::AbstractDict)
    validate_jordan_initial_condition_domain(domain)
    x1 = Float64(domain["x1_lower"]) +
        (Float64(domain["x1_upper"]) - Float64(domain["x1_lower"])) * rand(rng)
    x2_abs = Float64(domain["x2_abs_lower"]) +
        (Float64(domain["x2_abs_upper"]) - Float64(domain["x2_abs_lower"])) * rand(rng)
    x2 = (rand(rng, Bool) ? 1.0 : -1.0) * x2_abs
    return [x1, x2]
end

## Generate smoke dataset

function build_jordan_raw_trajectory(
    spec::JordanNonnormalLinearSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_jordan_nonnormal_linear_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "alpha" => spec.alpha,
        "gamma" => spec.gamma,
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

function validate_raw_trajectory_dimensions(spec::JordanNonnormalLinearSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    return true
end

function generate_raw_jordan_trajectories(system_config::AbstractDict)
    spec = jordan_nonnormal_linear_spec_from_config(system_config)
    validate_jordan_nonnormal_linear_spec(spec)
    rng = jordan_rng(system_config)
    ic_domain = system_config["initial_condition_domain"]

    raw_trajectories = RawTrajectory[]
    for q in 1:Int(system_config["num_trajectories"])
        x0 = sample_jordan_initial_condition(rng, ic_domain)
        raw = build_jordan_raw_trajectory(spec, q, x0)
        validate_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

function generate_clean_observed_trajectories(
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

function build_jordan_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

function build_jordan_window_summary(
    split::AbstractDict,
    trajectory_length::Integer,
    one_step_config::AbstractDict,
    rollout_config::AbstractDict,
)
    one_step_windows = build_one_step_windows(
        split,
        trajectory_length;
        window_id = one_step_config["window_id"],
        lag = Int(one_step_config["lag"]),
    )
    validate_window_indices(one_step_windows, split, trajectory_length)

    rollout_summaries = Dict{String,Any}()
    for horizon in Int.(rollout_config["horizons"])
        rollout_windows = build_rollout_windows(
            split,
            trajectory_length;
            window_id = string("jordan_rollout_horizon", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("jordan_rollout_horizon", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => trajectory_length + 1 - horizon,
        )
    end

    return Dict(
        "one_step" => Dict(
            "window_id" => one_step_config["window_id"],
            "lag" => Int(one_step_config["lag"]),
            "counts" => window_counts(one_step_windows),
            "samples_per_trajectory" => trajectory_length,
        ),
        "rollout" => Dict(
            "window_id" => rollout_config["window_id"],
            "horizons" => Int.(rollout_config["horizons"]),
            "by_horizon" => rollout_summaries,
        ),
    )
end

## Run smoke diagnostics

function enrich_jordan_diagnostics!(
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

## Save smoke outputs

function matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function trajectory_tensor(raw_trajectories::AbstractVector{RawTrajectory})
    return matrix_tensor([traj.state_matrix for traj in raw_trajectories])
end

function observation_tensor(observed_trajectories::AbstractVector{ObservedTrajectory})
    return matrix_tensor([traj.observation_matrix for traj in observed_trajectories])
end

function save_jordan_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = trajectory_tensor(raw_trajectories),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_jordan_observed(path::AbstractString, observed_trajectories::AbstractVector{ObservedTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in observed_trajectories],
        system_id = first(observed_trajectories).system_id,
        observation_id = first(observed_trajectories).observation_id,
        parameter_instances = [traj.parameter_instance for traj in observed_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in observed_trajectories]...),
        state_tensor = matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = observation_tensor(observed_trajectories),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(csv_value.(values), ","))
    end
    return path
end

function maybe_save_jordan_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    plot_dir::AbstractString,
    run_label::AbstractString = "smoke",
)
    if !PLOTS_AVAILABLE
        @warn "Skipping smoke plots because Plots.jl could not be loaded" exception = PLOTS_LOAD_ERROR[]
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]

        first_raw = first(raw_trajectories)
        p_time = Plots.plot(; xlabel = "t", ylabel = "state", title = "Jordan smoke time series")
        Plots.plot!(p_time, first_raw.times, first_raw.state_matrix[1, :]; label = "x1")
        Plots.plot!(p_time, first_raw.times, first_raw.state_matrix[2, :]; label = "x2")
        time_path = joinpath(plot_dir, string(run_label, "_time_series.png"))
        Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_phase = Plots.plot(; xlabel = "x1", ylabel = "x2", title = "Jordan smoke phase portrait")
        for traj in raw_trajectories
            Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, string(run_label, "_phase_portrait.png"))
        Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        p_amp = Plots.plot(; xlabel = "t", ylabel = "norm amplification", title = "Jordan nonnormal amplification")
        for traj in raw_trajectories
            norms = [norm(view(traj.state_matrix, :, m)) for m in axes(traj.state_matrix, 2)]
            Plots.plot!(p_amp, traj.times, norms ./ norms[1]; label = false)
        end
        amp_path = joinpath(plot_dir, string(run_label, "_norm_amplification.png"))
        Plots.savefig(p_amp, amp_path)
        push!(plot_files, amp_path)

        return plot_files
    catch err
        @warn "Skipping smoke plots because plot generation failed" exception = err
        return String[]
    end
end

function make_jordan_manifest(;
    configs::AbstractDict,
    spec::JordanNonnormalLinearSpec,
    observation_spec::FullStateObservationSpec,
    split::AbstractDict,
    window_summary::AbstractDict,
    generated_files::AbstractDict,
    diagnostics::AbstractDict,
)
    system_config = configs["system"]
    benchmark_config = configs["benchmark"]
    truth = jordan_nonnormal_linear_metadata(spec)
    return Dict(
        "dataset_version" => "0.1.0-dev",
        "created_at" => string(now()),
        "benchmark_id" => benchmark_config["benchmark_id"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "state_dim" => spec.state_dim,
        "alpha" => spec.alpha,
        "gamma" => spec.gamma,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "num_trajectories" => Int(system_config["num_trajectories"]),
        "initial_condition_policy" => system_config["initial_condition_domain"],
        "observation_id" => observation_spec.observation_id,
        "split_id" => split["split_id"],
        "window_ids" => benchmark_config["window_ids"],
        "task_ids" => [task["task_id"] for task in configs["tasks"]],
        "solver_name" => spec.solver_name,
        "seed" => system_config["seed_policy"]["generation_seed"],
        "array_layout" => "state_dim_by_time_by_trajectory",
        "truth_metadata" => truth,
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_jordan_outputs(;
    configs::AbstractDict,
    spec::JordanNonnormalLinearSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
    run_label::AbstractString = "smoke",
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = project_path(output_policy["raw_path"])
    processed_path = project_path(output_policy["processed_path"])
    split_path = project_path(output_policy["split_path"])
    windows_summary_path = project_path(output_policy["windows_summary_path"])
    manifest_path = project_path(output_policy["manifest_path"])
    table_path = joinpath(
        PROJECT_ROOT,
        "reports",
        "unit_internal",
        "jordan_nonnormal_linear",
        "tables",
        string(run_label, "_diagnostics.csv"),
    )
    plot_dir = joinpath(PROJECT_ROOT, "reports", "unit_internal", "jordan_nonnormal_linear", "plots")
    log_path = joinpath(
        PROJECT_ROOT,
        "reports",
        "unit_internal",
        "jordan_nonnormal_linear",
        "logs",
        string(run_label, "_generation.log"),
    )

    save_jordan_raw(raw_path, raw_trajectories)
    save_jordan_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_jordan_plots(raw_trajectories, plot_dir, run_label)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_jordan_manifest(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        split = split,
        window_summary = window_summary,
        generated_files = generated_files,
        diagnostics = diagnostics,
    )
    write_json_file(manifest_path, manifest)

    columns, values = jordan_diagnostics_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(trajectory_tensor(raw_trajectories)))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "rank_A_minus_alphaI: ", diagnostics["rank_A_minus_alphaI"])
        println(io, "geom_mult: ", diagnostics["geom_mult"])
        println(io, "max_one_step_residual: ", diagnostics["max_one_step_residual"])
        println(io, "max_rollout_residual: ", diagnostics["max_rollout_residual"])
        println(io, "max_norm_amplification: ", diagnostics["max_norm_amplification"])
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "manifest_path: ", manifest_path)
    end

    return Dict(
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "split_path" => split_path,
        "windows_summary_path" => windows_summary_path,
        "manifest_path" => manifest_path,
        "table_path" => table_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end

## Print smoke summary

function run_jordan_nonnormal_smoke()
    configs = load_jordan_smoke_configs()
    spec, raw_trajectories = generate_raw_jordan_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_clean_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_jordan_split(raw_trajectories, configs["split"])
    window_summary = build_jordan_window_summary(
        split,
        spec.trajectory_length,
        configs["one_step_window"],
        configs["rollout_window"],
    )
    horizons = Int.(configs["rollout_window"]["horizons"])
    diagnostics = summarize_jordan_nonnormal_dataset(spec, raw_trajectories; horizons = horizons)
    enrich_jordan_diagnostics!(diagnostics, split, window_summary)
    output_paths = save_jordan_outputs(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        raw_trajectories = raw_trajectories,
        observed_trajectories = observed_trajectories,
        split = split,
        window_summary = window_summary,
        diagnostics = diagnostics,
    )

    return Dict(
        "configs" => configs,
        "system_spec" => spec,
        "observation_spec" => observation_spec,
        "diagnostics" => diagnostics,
        "output_paths" => output_paths,
        "first_raw_trajectory" => first(raw_trajectories),
        "first_observed_trajectory" => first(observed_trajectories),
    )
end

function print_jordan_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("alpha: %.6g\n", spec.alpha)
    @printf("gamma: %.6g\n", spec.gamma)
    @printf("dt: %.6g\n", spec.dt)
    @printf("trajectory_length: %d\n", spec.trajectory_length)
    @printf("num_trajectories: %d\n", diagnostics["num_trajectories"])
    @printf("times size: %s\n", string(size(first_raw.times)))
    @printf("state_matrix size for first trajectory: %s\n", string(size(first_raw.state_matrix)))
    @printf("observation_matrix size for first trajectory: %s\n", string(size(first_observed.observation_matrix)))
    @printf(
        "train / val / test trajectory counts: %d / %d / %d\n",
        diagnostics["split_counts"]["train"],
        diagnostics["split_counts"]["val"],
        diagnostics["split_counts"]["test"],
    )
    @printf("rank_A_minus_alphaI: %d\n", diagnostics["rank_A_minus_alphaI"])
    @printf("geom_mult: %d\n", diagnostics["geom_mult"])
    @printf("max closed-form error: %.6e\n", diagnostics["max_closed_form_error"])
    @printf("max one-step residual: %.6e\n", diagnostics["max_one_step_residual"])
    @printf("max rollout residual: %.6e\n", diagnostics["max_rollout_residual"])
    @printf("max norm amplification: %.6f\n", diagnostics["max_norm_amplification"])
    @printf("x2 activation min abs: %.6f\n", diagnostics["x2_activation_min_abs"])
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_jordan_nonnormal_smoke()
    print_jordan_summary(result)
end
