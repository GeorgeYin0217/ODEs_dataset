## Formal configuration loading

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

function load_controlled_duffing_formal_configs()
    observation_paths = [
        ("observations", "duffing_controlled_fullstate_clean.json"),
        ("observations", "duffing_controlled_fullstate_noise_s1.json"),
        ("observations", "duffing_controlled_fullstate_noise_s2.json"),
        ("observations", "duffing_controlled_fullstate_noise_s3.json"),
        ("observations", "duffing_controlled_fullstate_noise_s4.json"),
    ]
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "duffing_controlled_edmdc_formal.json"),
        "system" => load_config("systems", "v1_core", "duffing_controlled_edmdc_formal.json"),
        "observations" => [load_config(path...) for path in observation_paths],
        "split" => load_config("splits", "v1_core", "duffing_controlled_formal_split_i.json"),
        "split_beta" => load_config("splits", "v1_core", "duffing_controlled_formal_split_p_beta.json"),
        "window" => load_config("windows", "v1_core", "duffing_controlled_formal_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "duffing_controlled_edmdc_formal_tasks.json")["tasks"],
    )
end

## Formal controlled data generation

function write_controlled_duffing_beta_split_outputs!(
    configs::AbstractDict,
    raw_trajectories::AbstractVector{RawControlledTrajectory},
    manifest_path::AbstractString,
)
    output_policy = configs["benchmark"]["output_policy"]
    split_beta = build_controlled_duffing_beta_split(raw_trajectories, configs["split_beta"])
    trajectory_length = Int(configs["system"]["trajectory_length"])
    window_summary_beta = build_controlled_duffing_window_summary(
        split_beta,
        trajectory_length,
        configs["window"],
    )

    split_beta_path = controlled_duffing_project_path(PROJECT_ROOT, output_policy["split_beta_path"])
    windows_beta_summary_path = controlled_duffing_project_path(
        PROJECT_ROOT,
        output_policy["windows_beta_summary_path"],
    )
    write_json_file(split_beta_path, split_beta)
    write_json_file(windows_beta_summary_path, window_summary_beta)

    manifest = read_json_file(manifest_path)
    manifest["generated_files"]["split_p_beta"] = split_beta_path
    manifest["generated_files"]["windows_summary_p_beta"] = windows_beta_summary_path
    manifest["split_p_beta_counts"] = Dict(
        "train" => length(split_beta["train_trajectory_ids"]),
        "val" => length(split_beta["val_trajectory_ids"]),
        "test" => length(split_beta["test_trajectory_ids"]),
    )
    manifest["window_summary_p_beta"] = window_summary_beta
    write_json_file(manifest_path, manifest)

    return split_beta, window_summary_beta, split_beta_path, windows_beta_summary_path
end

function run_duffing_controlled_edmdc_formal()
    configs = load_controlled_duffing_formal_configs()
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

    split_beta, window_summary_beta, split_beta_path, windows_beta_summary_path =
        write_controlled_duffing_beta_split_outputs!(
            configs,
            raw_trajectories,
            output_paths["manifest_path"],
        )
    output_paths["split_beta_path"] = split_beta_path
    output_paths["windows_beta_summary_path"] = windows_beta_summary_path

    return Dict(
        "configs" => configs,
        "system_spec" => spec,
        "observation_specs" => observation_specs,
        "diagnostics" => diagnostics,
        "output_paths" => output_paths,
        "split_i" => split,
        "split_p_beta" => split_beta,
        "window_summary_i" => window_summary,
        "window_summary_p_beta" => window_summary_beta,
        "first_raw_trajectory" => first(raw_trajectories),
        "first_clean_trajectory" => first(observed_by_id["duffing_controlled_fullstate_clean"]),
        "first_noisy_trajectory" => first(observed_by_id["duffing_controlled_fullstate_noise_s3"]),
    )
end

## Formal completion summary

function print_controlled_duffing_formal_summary(result::AbstractDict)
    spec = result["system_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    output_paths = result["output_paths"]
    clean = diagnostics["observations"]["duffing_controlled_fullstate_clean"]
    s1 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s1"]
    s2 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s2"]
    s3 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s3"]
    s4 = diagnostics["observations"]["duffing_controlled_fullstate_noise_s4"]
    split_p = result["split_p_beta"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("delta / alpha / input_gain: %.6g / %.6g / %.6g\n",
        spec.delta, spec.alpha, spec.input_gain)
    @printf("beta_values: %s\n", string(diagnostics["beta_values"]))
    @printf("dt: %.6g\n", spec.dt)
    @printf("trajectory_length: %d\n", spec.trajectory_length)
    @printf("num_raw_trajectories: %d\n", diagnostics["num_raw_trajectories"])
    @printf("times size: %s\n", string(size(first_raw.times)))
    @printf("state_matrix size for first trajectory: %s\n", string(size(first_raw.state_matrix)))
    @printf("input_matrix size for first trajectory: %s\n", string(size(first_raw.input_matrix)))
    @printf(
        "Split-I train / val / test trajectory counts: %d / %d / %d\n",
        diagnostics["split_counts"]["train"],
        diagnostics["split_counts"]["val"],
        diagnostics["split_counts"]["test"],
    )
    @printf(
        "Split-P beta train / val / test trajectory counts: %d / %d / %d\n",
        length(split_p["train_trajectory_ids"]),
        length(split_p["val_trajectory_ids"]),
        length(split_p["test_trajectory_ids"]),
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
    @printf("s1 state/input relative rms mean: %.6e / %.6e\n",
        s1["state_noise_relative_rms_mean"], s1["input_noise_relative_rms_mean"])
    @printf("s2 state/input relative rms mean: %.6e / %.6e\n",
        s2["state_noise_relative_rms_mean"], s2["input_noise_relative_rms_mean"])
    @printf("s3 state/input relative rms mean: %.6e / %.6e\n",
        s3["state_noise_relative_rms_mean"], s3["input_noise_relative_rms_mean"])
    @printf("s4 state/input relative rms mean: %.6e / %.6e\n",
        s4["state_noise_relative_rms_mean"], s4["input_noise_relative_rms_mean"])
    @printf("formal_passed: %s\n", string(diagnostics["formal_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed outputs: %s\n", string(output_paths["processed_files"]))
    @printf("Split-P beta path: %s\n", output_paths["split_beta_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_duffing_controlled_edmdc_formal()
    print_controlled_duffing_formal_summary(result)
    result["diagnostics"]["formal_passed"] ||
        error("Controlled Duffing EDMDc formal generation failed diagnostics")
end
