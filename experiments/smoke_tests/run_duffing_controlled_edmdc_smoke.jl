## Smoke configuration loading

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "duffing_controlled.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "controlled_trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "controlled_noise_models.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "controlled_duffing_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "generate_controlled_duffing.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_controlled_duffing_smoke_configs()
    observation_paths = [
        ("observations", "duffing_controlled_fullstate_clean.json"),
        ("observations", "duffing_controlled_fullstate_noise_s1.json"),
    ]
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "duffing_controlled_edmdc_smoke.json"),
        "system" => load_config("systems", "v1_core", "duffing_controlled_edmdc_smoke.json"),
        "observations" => [load_config(path...) for path in observation_paths],
        "split" => load_config("splits", "v1_core", "duffing_controlled_smoke_split_i.json"),
        "window" => load_config("windows", "v1_core", "duffing_controlled_smoke_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "duffing_controlled_edmdc_smoke_tasks.json")["tasks"],
    )
end

## Small-scale controlled data generation

function run_duffing_controlled_edmdc_smoke()
    configs = load_controlled_duffing_smoke_configs()
    spec, raw_trajectories = generate_controlled_duffing_raw_trajectories(configs["system"])
    observation_specs, observed_by_id = generate_controlled_duffing_observed_by_id(
        raw_trajectories,
        configs["observations"],
        spec.state_dim,
        spec.input_dim,
    )
    split = build_controlled_duffing_split(raw_trajectories, configs["split"])
    window_summary = build_controlled_duffing_window_summary(
        split,
        spec.trajectory_length,
        configs["window"],
    )

    diagnostics = summarize_controlled_duffing_dataset(spec, raw_trajectories, observed_by_id)
    enrich_controlled_duffing_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_controlled_duffing_outputs(
        project_root = PROJECT_ROOT,
        configs = configs,
        spec = spec,
        observation_specs = observation_specs,
        raw_trajectories = raw_trajectories,
        observed_by_id = observed_by_id,
        split = split,
        window_summary = window_summary,
        diagnostics = diagnostics,
    )

    return Dict(
        "configs" => configs,
        "system_spec" => spec,
        "observation_specs" => observation_specs,
        "diagnostics" => diagnostics,
        "output_paths" => output_paths,
        "first_raw_trajectory" => first(raw_trajectories),
        "first_clean_trajectory" => first(observed_by_id["duffing_controlled_fullstate_clean"]),
        "first_noisy_trajectory" => first(observed_by_id["duffing_controlled_fullstate_noise_s1"]),
    )
end

## Smoke manifest and log summary

function print_controlled_duffing_smoke_summary(result::AbstractDict)
    spec = result["system_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    output_paths = result["output_paths"]
    clean = diagnostics["observations"]["duffing_controlled_fullstate_clean"]
    noisy = diagnostics["observations"]["duffing_controlled_fullstate_noise_s1"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("delta / alpha / beta / input_gain: %.6g / %.6g / %.6g / %.6g\n",
        spec.delta, spec.alpha, spec.beta, spec.input_gain)
    @printf("dt: %.6g\n", spec.dt)
    @printf("trajectory_length: %d\n", spec.trajectory_length)
    @printf("num_raw_trajectories: %d\n", diagnostics["num_raw_trajectories"])
    @printf("times size: %s\n", string(size(first_raw.times)))
    @printf("state_matrix size for first trajectory: %s\n", string(size(first_raw.state_matrix)))
    @printf("input_matrix size for first trajectory: %s\n", string(size(first_raw.input_matrix)))
    @printf(
        "train / val / test trajectory counts: %d / %d / %d\n",
        diagnostics["split_counts"]["train"],
        diagnostics["split_counts"]["val"],
        diagnostics["split_counts"]["test"],
    )
    @printf("one-step window counts: %s\n", string(diagnostics["one_step_window_counts"]))
    @printf("rollout window counts: %s\n", string(diagnostics["rollout_window_counts"]))
    @printf("state range q: [%.6g, %.6g]\n", diagnostics["q_min"], diagnostics["q_max"])
    @printf("state range v: [%.6g, %.6g]\n", diagnostics["v_min"], diagnostics["v_max"])
    @printf("input mean / std / absmax: %.6g / %.6g / %.6g\n",
        diagnostics["input_mean"], diagnostics["input_std"], diagnostics["input_abs_max"])
    @printf("rk4 self residual max: %.6e\n", diagnostics["rk4_self_residual_max"])
    @printf("clean state/input relative rms: %.6e / %.6e\n",
        clean["state_noise_relative_rms_max"], clean["input_noise_relative_rms_max"])
    @printf("noisy state/input relative rms mean: %.6e / %.6e\n",
        noisy["state_noise_relative_rms_mean"], noisy["input_noise_relative_rms_mean"])
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed outputs: %s\n", string(output_paths["processed_files"]))
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_duffing_controlled_edmdc_smoke()
    print_controlled_duffing_smoke_summary(result)
    result["diagnostics"]["smoke_passed"] || error("Controlled Duffing EDMDc smoke generation failed diagnostics")
end
