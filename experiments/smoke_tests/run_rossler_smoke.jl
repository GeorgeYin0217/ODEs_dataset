## Smoke test purpose and configuration loading

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "rossler.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "rossler_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "rossler_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_rossler_smoke_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "rossler_smoke_benchmark.json"),
        "system" => load_config("systems", "v1_core", "rossler_smoke.json"),
        "observation" => load_config("observations", "rossler_full_state_clean.json"),
        "split" => load_config("splits", "v1_core", "rossler_smoke_split_i.json"),
        "window" => load_config("windows", "v1_core", "rossler_smoke_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "rossler_smoke_tasks.json")["tasks"],
    )
end

## Run end-to-end generation

function run_rossler_smoke()
    configs = load_rossler_smoke_configs()
    spec, raw_trajectories = generate_rossler_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_rossler_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_rossler_split(raw_trajectories, configs["split"])
    window_summary = build_rossler_window_summary(split, spec.trajectory_length, configs["window"])

    diagnostics = summarize_rossler_dataset(spec, raw_trajectories, observed_trajectories)
    enrich_rossler_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_rossler_outputs(
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

## Check generated files and core dimensions

function assert_rossler_smoke_outputs(result::AbstractDict)
    spec = result["system_spec"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    size(first_raw.state_matrix) == (3, spec.trajectory_length + 1) ||
        error("first raw trajectory has wrong state_matrix size")
    size(first_observed.observation_matrix) == (3, spec.trajectory_length + 1) ||
        error("first observed trajectory has wrong observation_matrix size")
    length(first_raw.times) == spec.trajectory_length + 1 ||
        error("first raw trajectory has wrong time-vector length")

    for key in ("raw_path", "processed_path", "split_path", "windows_summary_path", "manifest_path", "table_path", "log_path")
        path = output_paths[key]
        isfile(path) || error("missing smoke output file: $(path)")
        filesize(path) > 0 || error("empty smoke output file: $(path)")
    end

    if PLOTS_AVAILABLE
        !isempty(output_paths["plot_files"]) || error("plot generation produced no files")
        for path in output_paths["plot_files"]
            isfile(path) || error("missing smoke plot file: $(path)")
            filesize(path) > 0 || error("empty smoke plot file: $(path)")
        end
    end

    manifest = JSON.parsefile(output_paths["manifest_path"])
    required_manifest_keys = [
        "dataset_version",
        "benchmark_id",
        "system_id",
        "observation_id",
        "split_id",
        "window_ids",
        "task_ids",
        "solver_name",
        "burn_in_time",
        "seed",
        "generated_files",
        "diagnostics",
    ]
    for key in required_manifest_keys
        haskey(manifest, key) || error("manifest is missing key: $(key)")
    end

    return true
end

## Print smoke summary

function print_rossler_smoke_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("a / b / c: %.6g / %.6g / %.6g\n", spec.a, spec.b, spec.c)
    @printf("dt: %.6g\n", spec.dt)
    @printf("burn_in_time: %.6g\n", spec.burn_in_time)
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
    @printf("state range z: [%.6g, %.6g]\n", diagnostics["z_min"], diagnostics["z_max"])
    @printf("state norm max: %.6e\n", diagnostics["state_norm_max"])
    @printf("velocity norm max: %.6e\n", diagnostics["velocity_norm_max"])
    @printf("step increment max: %.6e\n", diagnostics["step_increment_max"])
    @printf("rk4 self residual max: %.6e\n", diagnostics["rk4_self_residual_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("divergence mean: %.6g\n", diagnostics["divergence_mean"])
    @printf("active attractor trajectory count: %d\n", diagnostics["active_attractor_trajectory_count"])
    @printf("y positive crossing counts: %s\n", string(diagnostics["y_positive_crossing_counts"]))
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("plot files: %s\n", string(output_paths["plot_files"]))
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_rossler_smoke()
    assert_rossler_smoke_outputs(result)
    print_rossler_smoke_summary(result)
    result["diagnostics"]["smoke_passed"] || error("Rossler smoke generation failed diagnostics")
end
