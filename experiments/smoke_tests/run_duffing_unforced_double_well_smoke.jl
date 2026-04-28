## Load smoke configuration for Duffing double-well system

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "duffing.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "duffing_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "duffing_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_duffing_smoke_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "duffing_smoke_benchmark.json"),
        "system" => load_config("systems", "v1_core", "duffing_unforced_double_well_smoke.json"),
        "observation" => load_config("observations", "duffing_full_state_clean.json"),
        "split" => load_config("splits", "v1_core", "duffing_smoke_split_i.json"),
        "window" => load_config("windows", "v1_core", "duffing_smoke_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "duffing_smoke_tasks.json")["tasks"],
    )
end

## Generate raw Duffing state trajectories

function run_duffing_unforced_double_well_smoke()
    configs = load_duffing_smoke_configs()
    spec, raw_trajectories = generate_duffing_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_duffing_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_duffing_split(raw_trajectories, configs["split"])
    window_summary = build_duffing_window_summary(split, spec.trajectory_length, configs["window"])

    diagnostics = summarize_duffing_dataset(spec, raw_trajectories, observed_trajectories)
    enrich_duffing_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_duffing_outputs(
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

function print_duffing_smoke_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]
    final_counts = diagnostics["final_well_counts"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("delta / alpha / beta: %.6g / %.6g / %.6g\n", spec.delta, spec.alpha, spec.beta)
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
    @printf("state range q: [%.6g, %.6g]\n", diagnostics["q_min"], diagnostics["q_max"])
    @printf("state range v: [%.6g, %.6g]\n", diagnostics["v_min"], diagnostics["v_max"])
    @printf("state norm max: %.6e\n", diagnostics["state_norm_max"])
    @printf("velocity norm max: %.6e\n", diagnostics["velocity_norm_max"])
    @printf("rk4 self residual max: %.6e\n", diagnostics["rk4_self_residual_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("max positive energy jump: %.6e\n", diagnostics["max_positive_energy_jump"])
    @printf("positive energy jump count total: %d\n", diagnostics["positive_energy_jump_count_total"])
    @printf("energy drop min: %.6e\n", diagnostics["energy_drop_min"])
    @printf(
        "final well counts left / right / near_barrier: %d / %d / %d\n",
        final_counts["left"],
        final_counts["right"],
        final_counts["near_barrier"],
    )
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_duffing_unforced_double_well_smoke()
    print_duffing_smoke_summary(result)
    result["diagnostics"]["smoke_passed"] || error("Duffing smoke generation failed diagnostics")
end
