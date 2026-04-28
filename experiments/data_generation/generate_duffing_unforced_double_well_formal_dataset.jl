## Formal benchmark purpose and smoke-parameter config selection

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

function duffing_formal_benchmark_from_smoke(smoke_benchmark::AbstractDict)
    benchmark = deepcopy(smoke_benchmark)
    benchmark["benchmark_id"] = "duffing_unforced_double_well_fullobs_v1_formal_smoke_params"
    benchmark["difficulty_level"] = "formal"
    benchmark["notes"] = "Formal entry point intentionally reuses the smoke system, split, window, and task parameters."
    benchmark["output_policy"] = Dict(
        "raw_path" => "data/raw/v1_core/duffing_unforced_double_well/formal/raw_trajectories.jld2",
        "processed_path" => "data/processed/v1_core/duffing_unforced_double_well/formal/full_state_clean/observed_trajectories.jld2",
        "split_path" => "data/processed/v1_core/duffing_unforced_double_well/formal/full_state_clean/splits.json",
        "windows_summary_path" => "data/processed/v1_core/duffing_unforced_double_well/formal/full_state_clean/windows_summary.json",
        "manifest_path" => "data/manifests/v1_core/duffing_unforced_double_well/formal/manifest.json",
        "release_index_path" => "data/releases/v1_core/duffing_unforced_double_well/formal/release_index.json",
    )
    return benchmark
end

function load_duffing_formal_smoke_parameter_configs()
    smoke_benchmark = load_config("benchmarks", "v1_core", "duffing_smoke_benchmark.json")
    return Dict(
        "benchmark" => duffing_formal_benchmark_from_smoke(smoke_benchmark),
        "system" => load_config("systems", "v1_core", "duffing_unforced_double_well_smoke.json"),
        "observation" => load_config("observations", "duffing_full_state_clean.json"),
        "split" => load_config("splits", "v1_core", "duffing_smoke_split_i.json"),
        "window" => load_config("windows", "v1_core", "duffing_smoke_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "duffing_smoke_tasks.json")["tasks"],
    )
end

## Formal dataset generation entry point

function run_duffing_formal_generation_with_smoke_parameters()
    configs = load_duffing_formal_smoke_parameter_configs()
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

## Formal completion summary

function print_duffing_formal_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]
    final_counts = diagnostics["final_well_counts"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("benchmark_id: %s\n", result["configs"]["benchmark"]["benchmark_id"])
    @printf("difficulty_level: %s\n", result["configs"]["benchmark"]["difficulty_level"])
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
    @printf("max positive energy jump: %.6e\n", diagnostics["max_positive_energy_jump"])
    @printf("positive energy jump count total: %d\n", diagnostics["positive_energy_jump_count_total"])
    @printf(
        "final well counts left / right / near_barrier: %d / %d / %d\n",
        final_counts["left"],
        final_counts["right"],
        final_counts["near_barrier"],
    )
    @printf("formal_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_duffing_formal_generation_with_smoke_parameters()
    print_duffing_formal_summary(result)
    result["diagnostics"]["smoke_passed"] || error("Duffing formal generation failed diagnostics")
end
