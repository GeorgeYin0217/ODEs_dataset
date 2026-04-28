## Load smoke configuration for Lotka-Volterra system

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "lotka_volterra.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "lotka_volterra_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "lotka_volterra_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_lotka_volterra_smoke_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "lotka_volterra_smoke_benchmark.json"),
        "system" => load_config("systems", "v1_core", "lotka_volterra_smoke.json"),
        "observation" => load_config("observations", "lotka_volterra_full_state_clean.json"),
        "split" => load_config("splits", "v1_core", "lotka_volterra_smoke_split_i.json"),
        "window" => load_config("windows", "v1_core", "lotka_volterra_smoke_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "lotka_volterra_smoke_tasks.json")["tasks"],
    )
end

## Generate smoke raw trajectories and derived dataset objects

function run_lotka_volterra_smoke()
    configs = load_lotka_volterra_smoke_configs()
    spec, raw_trajectories = generate_lotka_volterra_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_lotka_volterra_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_lotka_volterra_split(raw_trajectories, configs["split"])
    window_summary = build_lotka_volterra_window_summary(split, spec.trajectory_length, configs["window"])

    diagnostics = summarize_lotka_volterra_dataset(spec, raw_trajectories, observed_trajectories)
    enrich_lotka_volterra_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_lotka_volterra_outputs(
        project_root = PROJECT_ROOT,
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

## Print smoke completion summary

function print_lotka_volterra_smoke_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]
    equilibrium = diagnostics["positive_equilibrium"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf(
        "alpha / beta / gamma / delta: %.6g / %.6g / %.6g / %.6g\n",
        spec.alpha,
        spec.beta,
        spec.gamma,
        spec.delta,
    )
    @printf("positive equilibrium: [%.6g, %.6g]\n", equilibrium[1], equilibrium[2])
    @printf("local frequency scale: %.6g\n", diagnostics["local_frequency"])
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
    @printf("statistics window counts: %s\n", string(diagnostics["statistics_window_counts"]))
    @printf("state range x: [%.6g, %.6g]\n", diagnostics["x_min"], diagnostics["x_max"])
    @printf("state range y: [%.6g, %.6g]\n", diagnostics["y_min"], diagnostics["y_max"])
    @printf("state norm max: %.6e\n", diagnostics["state_norm_max"])
    @printf("velocity norm max: %.6e\n", diagnostics["velocity_norm_max"])
    @printf("rk4 self residual max: %.6e\n", diagnostics["rk4_self_residual_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("all states positive: %s\n", string(diagnostics["all_states_positive"]))
    @printf("invariant initial range: [%.6g, %.6g]\n", diagnostics["invariant_initial_min"], diagnostics["invariant_initial_max"])
    @printf("invariant max abs drift: %.6e\n", diagnostics["invariant_max_abs_drift"])
    @printf("invariant max rel drift: %.6e\n", diagnostics["invariant_max_rel_drift"])
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_lotka_volterra_smoke()
    print_lotka_volterra_smoke_summary(result)
    result["diagnostics"]["smoke_passed"] || error("Lotka-Volterra smoke generation failed diagnostics")
end
