## 1. Load packages and project source files

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

project_root = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(project_root, "src", "dynamics", "linear_diagonal.jl"))
include(joinpath(project_root, "src", "datasets", "trajectory_types.jl"))
include(joinpath(project_root, "src", "observations", "full_state.jl"))
include(joinpath(project_root, "src", "splits", "trajectory_split.jl"))
include(joinpath(project_root, "src", "windows", "window_builders.jl"))
include(joinpath(project_root, "src", "io", "jld2_io.jl"))
include(joinpath(project_root, "src", "manifests", "manifest_writer.jl"))
include(joinpath(project_root, "src", "diagnostics", "linear_system_checks.jl"))

## 2. Define helpers

function load_config(parts...)
    return JSON.parsefile(joinpath(project_root, "configs", parts...))
end

function maybe_save_smoke_plots(times, X, plot_dir)
    if !PLOTS_AVAILABLE
        @warn "Skipping smoke plots because Plots.jl could not be loaded" exception = PLOTS_LOAD_ERROR[]
        return String[]
    end

    try
        mkpath(plot_dir)

        p1 = Plots.plot(times, X'; xlabel = "t", ylabel = "x_i(t)", title = "Linear diagonal coordinates")
        Plots.savefig(p1, joinpath(plot_dir, "coordinate_timeseries.png"))

        p2 = Plots.plot(times, log.(abs.(X') .+ eps()); xlabel = "t", ylabel = "log(|x_i(t)|)", title = "Log amplitudes")
        Plots.savefig(p2, joinpath(plot_dir, "log_amplitudes.png"))

        return [
            joinpath(plot_dir, "coordinate_timeseries.png"),
            joinpath(plot_dir, "log_amplitudes.png"),
        ]
    catch err
        @warn "Skipping smoke plots because Plots.jl could not be used" exception = err
        return String[]
    end
end

## 3. Load smoke-test configuration

system_config = load_config("systems", "unit_internal", "linear_diagonal_small.json")
observation_config = load_config("observations", "unit_internal", "full_state_identity.json")
split_config = load_config("splits", "unit_internal", "split_I_70_15_15_seed1.json")
one_step_config = load_config("windows", "unit_internal", "one_step_lag1.json")
rollout_config = load_config("windows", "unit_internal", "rollout_horizon20.json")
one_step_task_config = load_config("tasks", "unit_internal", "one_step_forecast.json")
rollout_task_config = load_config("tasks", "unit_internal", "multi_step_rollout.json")
benchmark_config = load_config("benchmarks", "unit_internal", "linear_diagonal_smoke.json")

system_spec = linear_diagonal_spec_from_config(system_config)
observation_spec = full_state_observation_spec_from_config(observation_config)
validate_linear_diagonal_spec(system_spec)
validate_full_state_observation_spec(observation_spec, system_spec.state_dim)

## 4. Generate raw and processed trajectories

rng = MersenneTwister(Int(system_config["seed_policy"]["generation_seed"]))
ic_domain = system_config["initial_condition_domain"]
parameter_instance = Dict{String,Any}("eigenvalues" => copy(system_spec.eigenvalues))

difficulty = String(system_config["difficulty_level"])
raw_dir = joinpath(project_root, "data", "raw", system_spec.family, system_spec.system_id, difficulty)
processed_dir = joinpath(
    project_root,
    "data",
    "processed",
    system_spec.family,
    system_spec.system_id,
    observation_spec.observation_id,
    difficulty,
)
manifest_dir = joinpath(project_root, "data", "manifests", system_spec.family, system_spec.system_id, difficulty)
plot_dir = joinpath(project_root, "reports", "plots", system_spec.family, system_spec.system_id, "smoke")

raw_trajectories = RawTrajectory[]
observed_trajectories = ObservedTrajectory[]
raw_files = String[]
processed_files = String[]

for q in 1:Int(system_config["num_trajectories"])
    trajectory_id = make_trajectory_id(system_spec.system_id, q)
    x0 = sample_initial_condition(
        rng,
        system_spec.state_dim;
        lower = Float64(ic_domain["lower"]),
        upper = Float64(ic_domain["upper"]),
        min_abs = Float64(ic_domain["min_abs"]),
    )
    times, X = generate_linear_diagonal_trajectory(system_spec, x0)

    raw = RawTrajectory(trajectory_id, system_spec.system_id, deepcopy(parameter_instance), x0, times, X)
    observed = apply_full_state_observation(raw, observation_spec)

    validate_raw_trajectory_dimensions(system_spec, raw)
    validate_observed_trajectory(observed)

    raw_path = joinpath(raw_dir, string(trajectory_id, ".jld2"))
    processed_path = joinpath(processed_dir, string(trajectory_id, ".jld2"))
    save_raw_trajectory(raw_path, raw)
    save_observed_trajectory(processed_path, observed)

    push!(raw_trajectories, raw)
    push!(observed_trajectories, observed)
    push!(raw_files, raw_path)
    push!(processed_files, processed_path)
end

## 5. Generate trajectory-level split and windows

trajectory_ids = [traj.trajectory_id for traj in raw_trajectories]
split = build_trajectory_split(
    trajectory_ids;
    train_ratio = Float64(split_config["train_ratio"]),
    val_ratio = Float64(split_config["val_ratio"]),
    test_ratio = Float64(split_config["test_ratio"]),
    seed = Int(split_config["seed"]),
    split_id = split_config["split_id"],
    split_type = split_config["split_type"],
)

one_step_windows = build_one_step_windows(
    split,
    system_spec.trajectory_length;
    window_id = one_step_config["window_id"],
    lag = Int(one_step_config["lag"]),
)
rollout_windows = build_rollout_windows(
    split,
    system_spec.trajectory_length;
    window_id = rollout_config["window_id"],
    horizon = Int(rollout_config["horizon"]),
)
validate_window_indices(one_step_windows, split, system_spec.trajectory_length)
validate_window_indices(rollout_windows, split, system_spec.trajectory_length)

mkpath(manifest_dir)
split_path = write_json_file(joinpath(manifest_dir, string(split_config["split_id"], ".json")), split)
one_step_windows_path = write_json_file(joinpath(manifest_dir, string(one_step_config["window_id"], ".json")), one_step_windows)
rollout_windows_path = write_json_file(joinpath(manifest_dir, string(rollout_config["window_id"], ".json")), rollout_windows)

## 6. Run diagnostics and write manifest

diagnostics = summarize_linear_dataset(system_spec, raw_trajectories)
diagnostics["split_counts"] = Dict(
    "train" => length(split["train_trajectory_ids"]),
    "val" => length(split["val_trajectory_ids"]),
    "test" => length(split["test_trajectory_ids"]),
)
diagnostics["one_step_window_counts"] = window_counts(one_step_windows)
diagnostics["rollout_window_counts"] = window_counts(rollout_windows)

plot_files = maybe_save_smoke_plots(first(raw_trajectories).times, first(raw_trajectories).state_matrix, plot_dir)

generated_files = Dict(
    "raw_trajectories" => raw_files,
    "processed_trajectories" => processed_files,
    "split" => split_path,
    "windows" => [one_step_windows_path, rollout_windows_path],
    "plots" => plot_files,
)

manifest = make_release_manifest(
    dataset_version = "0.1.0-dev",
    benchmark_id = benchmark_config["benchmark_id"],
    system_config = system_config,
    observation_config = observation_config,
    split_config = split_config,
    window_configs = [one_step_config, rollout_config],
    task_configs = [one_step_task_config, rollout_task_config],
    benchmark_config = benchmark_config,
    generated_files = generated_files,
    diagnostics = diagnostics,
)
validate_manifest(manifest)
manifest_path = write_json_file(joinpath(manifest_dir, "linear_diagonal_smoke_manifest.json"), manifest)

## 7. Print final summary

@printf("system_id: %s\n", system_spec.system_id)
@printf("state_dim: %d\n", system_spec.state_dim)
@printf("eigenvalues: %s\n", string(system_spec.eigenvalues))
@printf("dt: %.6g\n", system_spec.dt)
@printf("trajectory_length: %d\n", system_spec.trajectory_length)
@printf("num_trajectories: %d\n", length(raw_trajectories))
@printf("times size: %s\n", string(size(first(raw_trajectories).times)))
@printf("state_matrix size for first trajectory: %s\n", string(size(first(raw_trajectories).state_matrix)))
@printf("observation_matrix size for first trajectory: %s\n", string(size(first(observed_trajectories).observation_matrix)))
@printf("train / val / test trajectory counts: %d / %d / %d\n",
    diagnostics["split_counts"]["train"],
    diagnostics["split_counts"]["val"],
    diagnostics["split_counts"]["test"],
)
@printf("one-step window counts: %s\n", string(diagnostics["one_step_window_counts"]))
@printf("rollout window counts: %s\n", string(diagnostics["rollout_window_counts"]))
@printf("max analytic error: %.6e\n", diagnostics["max_analytic_error"])
@printf("max one-step residual: %.6e\n", diagnostics["max_one_step_residual"])
@printf("raw output directory: %s\n", raw_dir)
@printf("processed output directory: %s\n", processed_dir)
@printf("manifest path: %s\n", manifest_path)
