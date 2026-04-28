## Load v1_core benchmark configuration

using JSON
using Printf

const PLOTS_LOAD_ERROR = Ref{Any}(nothing)
const PLOTS_AVAILABLE = try
    @eval import Plots
    true
catch err
    PLOTS_LOAD_ERROR[] = err
    false
end

const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(PROJECT_ROOT, "src", "dynamics", "linear_oscillator.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "linear_oscillator_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "linear_oscillator_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_linear_oscillator_formal_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core_linear_oscillator_damped_full_state.json"),
        "system" => load_config("systems", "linear_oscillator_v1_core_damped.json"),
        "observation" => load_config("observations", "full_state_2d_clean.json"),
        "split" => load_config("splits", "linear_oscillator_v1_core_split_i.json"),
        "window" => load_config("windows", "linear_oscillator_v1_core_windows.json"),
        "forecasting_tasks" => load_config("tasks", "linear_oscillator_forecasting_tasks.json"),
        "reconstruction_tasks" => load_config("tasks", "linear_oscillator_reconstruction_tasks.json"),
    )
end

## Confirm underdamped full-state setup

function validate_linear_oscillator_formal_configs(configs::AbstractDict)
    spec = linear_oscillator_spec_from_config(configs["system"])
    validate_linear_oscillator_spec(spec)
    spec.gamma > 0.0 || throw(ArgumentError("formal damped config requires gamma > 0"))
    spec.gamma < spec.omega0 || throw(ArgumentError("formal damped config requires gamma < omega0"))

    observation_spec = full_state_observation_spec_from_config(configs["observation"])
    validate_full_state_observation_spec(observation_spec, spec.state_dim)

    return spec, observation_spec
end

## Run formal trajectory generation

function run_linear_oscillator_formal_generation()
    configs = load_linear_oscillator_formal_configs()
    validate_linear_oscillator_formal_configs(configs)

    spec, raw_trajectories = generate_linear_oscillator_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_linear_oscillator_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )

    split = build_linear_oscillator_split(raw_trajectories, configs["split"])
    window_summary = build_linear_oscillator_window_summary(
        split,
        spec.trajectory_length,
        configs["window"],
    )

    horizons = Int.(configs["window"]["rollout"]["horizons"])
    diagnostics = summarize_linear_oscillator_dataset(
        spec,
        raw_trajectories,
        observed_trajectories;
        horizons = horizons,
    )
    enrich_linear_oscillator_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_linear_oscillator_outputs(
        project_root = PROJECT_ROOT,
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        raw_trajectories = raw_trajectories,
        observed_trajectories = observed_trajectories,
        split = split,
        window_summary = window_summary,
        diagnostics = diagnostics,
        report_subdir = ["v1_core", "linear_oscillator", "damped_full_state"],
        release_id = "linear_oscillator_v1_core_release_preview",
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

## Print formal generation summary

function print_linear_oscillator_formal_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("gamma: %.6g\n", spec.gamma)
    @printf("omega0: %.12g\n", spec.omega0)
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
    @printf("one-step window counts: %s\n", string(diagnostics["one_step_window_counts"]))
    @printf("rollout window counts: %s\n", string(diagnostics["rollout_window_counts"]))
    @printf("energy step increase max: %.6e\n", diagnostics["energy_step_increase_max"])
    @printf("energy final ratio max: %.6e\n", diagnostics["energy_final_ratio_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("rollout residual max: %.6e\n", diagnostics["rollout_residual_max"])
    @printf("discrete spectrum abs error max: %.6e\n", diagnostics["discrete_spectrum_abs_error_max"])
    @printf("discrete spectrum modulus max: %.6e\n", diagnostics["discrete_spectrum_modulus_max"])
    @printf("formal_passed: %s\n", string(diagnostics["formal_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_linear_oscillator_formal_generation()
    print_linear_oscillator_formal_summary(result)
end
