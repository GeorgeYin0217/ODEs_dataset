## Release configuration selection

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "nonlinear_pendulum_lusch2018.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "pendulum_family_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "nonlinear_pendulum_lusch2018_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_pendulum_medium_release_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_plus", "nonlinear_pendulum_lusch2018_medium_benchmark.json"),
        "system" => load_config("systems", "v1_plus", "nonlinear_pendulum_lusch2018_medium.json"),
        "observation" => load_config("observations", "pendulum_fullstate_identity_clean.json"),
        "split" => load_config("splits", "v1_plus", "pendulum_split_i_default.json"),
        "window" => load_config("windows", "v1_plus", "pendulum_lusch2018_default_windows.json"),
        "tasks" => load_config("tasks", "v1_plus", "pendulum_lusch2018_default_tasks.json")["tasks"],
    )
end

## Reproducibility and seed control

function run_nonlinear_pendulum_lusch2018_medium_release()
    configs = load_pendulum_medium_release_configs()

    ## Full trajectory generation

    spec, raw_trajectories, sampling_statistics = generate_pendulum_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_pendulum_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )

    ## Processed dataset materialization

    split = build_pendulum_split(raw_trajectories, configs["split"])
    window_summary = build_pendulum_window_summary(
        split,
        pendulum_transition_count(spec),
        spec.trajectory_length,
        configs["window"],
    )

    ## Manifest and release summary writing

    diagnostics = summarize_pendulum_dataset(
        spec,
        raw_trajectories,
        observed_trajectories,
        sampling_statistics,
    )
    enrich_pendulum_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_pendulum_outputs(
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

## Release completion summary

function print_pendulum_medium_release_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("benchmark_id: %s\n", result["configs"]["benchmark"]["benchmark_id"])
    @printf("difficulty_level: %s\n", result["configs"]["benchmark"]["difficulty_level"])
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("dt: %.6g\n", spec.dt)
    @printf("snapshot count T: %d\n", spec.trajectory_length)
    @printf("transition count: %d\n", diagnostics["transition_count"])
    @printf("num_trajectories: %d\n", diagnostics["num_trajectories"])
    @printf("candidate count: %d\n", diagnostics["sampling_statistics"]["candidate_count"])
    @printf("acceptance rate: %.6f\n", diagnostics["acceptance_rate"])
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
    @printf("state range x1: [%.6g, %.6g]\n", diagnostics["x1_min"], diagnostics["x1_max"])
    @printf("state range x2: [%.6g, %.6g]\n", diagnostics["x2_min"], diagnostics["x2_max"])
    @printf("initial energy range: [%.6g, %.6g]\n", diagnostics["initial_energy_min"], diagnostics["initial_energy_max"])
    @printf("energy drift max: %.6e\n", diagnostics["energy_drift_max"])
    @printf("energy drift p95: %.6e\n", diagnostics["energy_drift_p95"])
    @printf("near-separatrix initial count: %d\n", diagnostics["near_separatrix_count"])
    @printf("separatrix violation count: %d\n", diagnostics["separatrix_violation_count"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("medium_passed: %s\n", string(diagnostics["medium_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("animation path: %s\n", output_paths["animation_path"])
    @printf("report path: %s\n", output_paths["report_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_nonlinear_pendulum_lusch2018_medium_release()
    print_pendulum_medium_release_summary(result)
    result["diagnostics"]["medium_passed"] || error("Nonlinear pendulum medium release failed diagnostics")
    isempty(result["output_paths"]["animation_path"]) && error("Nonlinear pendulum animation was not generated")
end
