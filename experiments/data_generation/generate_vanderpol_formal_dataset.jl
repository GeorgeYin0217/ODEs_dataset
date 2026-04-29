## Formal benchmark purpose and config selection

using Dates
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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "vanderpol_unforced.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "vanderpol_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "vanderpol_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_vanderpol_formal_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "v1_core", "vanderpol_formal_benchmark.json"),
        "system" => load_config("systems", "v1_core", "vanderpol_unforced_formal.json"),
        "observation" => load_config("observations", "full_state_2d_clean.json"),
        "split_i" => load_config("splits", "v1_core", "vanderpol_formal_split_i.json"),
        "split_p" => load_config("splits", "v1_core", "vanderpol_formal_split_p.json"),
        "window" => load_config("windows", "v1_core", "vanderpol_formal_windows.json"),
        "tasks" => load_config("tasks", "v1_core", "vanderpol_formal_tasks.json")["tasks"],
    )
end

## Formal artifact and report saving

function vanderpol_formal_csv_row(
    spec::VanDerPolUnforcedSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns, values = vanderpol_diagnostics_csv_row(spec, observation_id, diagnostics)
    append!(columns, ["formal_passed", "split_i_train", "split_i_val", "split_i_test", "split_p_train", "split_p_val", "split_p_test"])
    append!(
        values,
        [
            diagnostics["formal_passed"],
            diagnostics["split_i_counts"]["train"],
            diagnostics["split_i_counts"]["val"],
            diagnostics["split_i_counts"]["test"],
            diagnostics["split_p_counts"]["train"],
            diagnostics["split_p_counts"]["val"],
            diagnostics["split_p_counts"]["test"],
        ],
    )
    return columns, values
end

function save_vanderpol_formal_outputs(;
    configs::AbstractDict,
    spec::VanDerPolUnforcedSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split_i::AbstractDict,
    split_p::AbstractDict,
    window_summary_i::AbstractDict,
    window_summary_p::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = vanderpol_project_path(PROJECT_ROOT, output_policy["raw_path"])
    processed_path = vanderpol_project_path(PROJECT_ROOT, output_policy["processed_path"])
    split_i_path = vanderpol_project_path(PROJECT_ROOT, output_policy["split_i_path"])
    split_p_path = vanderpol_project_path(PROJECT_ROOT, output_policy["split_p_path"])
    windows_i_summary_path = vanderpol_project_path(PROJECT_ROOT, output_policy["windows_i_summary_path"])
    windows_p_summary_path = vanderpol_project_path(PROJECT_ROOT, output_policy["windows_p_summary_path"])
    manifest_path = vanderpol_project_path(PROJECT_ROOT, output_policy["manifest_path"])
    release_index_path = vanderpol_project_path(PROJECT_ROOT, output_policy["release_index_path"])
    report_root = joinpath(PROJECT_ROOT, "reports", "v1_core", "vanderpol_unforced_fullobs_v1")
    table_path = joinpath(report_root, "tables", "formal", "diagnostics.csv")
    plot_dir = joinpath(report_root, "plots", "formal")
    log_path = joinpath(report_root, "logs", "formal.log")

    save_vanderpol_raw(raw_path, raw_trajectories)
    save_vanderpol_observed(processed_path, observed_trajectories)
    write_json_file(split_i_path, split_i)
    write_json_file(split_p_path, split_p)
    write_json_file(windows_i_summary_path, window_summary_i)
    write_json_file(windows_p_summary_path, window_summary_p)

    plot_files = maybe_save_vanderpol_plots(raw_trajectories, plot_dir)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split_i" => split_i_path,
        "split_p" => split_p_path,
        "windows_split_i_summary" => windows_i_summary_path,
        "windows_split_p_summary" => windows_p_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = Dict(
        "dataset_version" => configs["benchmark"]["release_version"],
        "created_at" => string(now()),
        "benchmark_id" => configs["benchmark"]["benchmark_id"],
        "difficulty_level" => configs["benchmark"]["difficulty_level"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "observation_dim" => observation_spec.output_dim,
        "observation_id" => observation_spec.observation_id,
        "split_ids" => configs["benchmark"]["split_ids"],
        "window_ids" => configs["benchmark"]["window_ids"],
        "task_ids" => configs["benchmark"]["task_ids"],
        "parameter_domain" => configs["system"]["parameter_domain"],
        "parameter_sampling" => configs["system"]["parameter_sampling"],
        "dt" => spec.dt,
        "tspan" => collect(spec.tspan),
        "trajectory_length" => spec.trajectory_length,
        "num_trajectories" => Int(configs["system"]["num_trajectories"]),
        "initial_condition_policy" => configs["system"]["initial_condition_domain"],
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "seed" => configs["system"]["seed_policy"]["generation_seed"],
        "array_layout" => "state_dim_by_time_by_trajectory",
        "system_metadata" => vanderpol_unforced_metadata(spec),
        "split_i_summary" => split_i,
        "split_p_parameter_ranges" => split_p["parameter_ranges"],
        "window_summary_by_split" => Dict("split_i" => window_summary_i, "split_p" => window_summary_p),
        "generated_files" => generated_files,
        "diagnostics" => diagnostics,
    )
    write_json_file(manifest_path, manifest)

    release_index = Dict(
        "release_id" => "vanderpol_unforced_fullobs_v1_formal",
        "release_version" => configs["benchmark"]["release_version"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "manifest_path" => manifest_path,
        "created_at" => string(now()),
    )
    write_json_file(release_index_path, release_index)

    columns, values = vanderpol_formal_csv_row(spec, observation_spec.observation_id, diagnostics)
    write_vanderpol_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "mu range: ", diagnostics["mu_min"], " to ", diagnostics["mu_max"])
        println(io, "state_tensor size: ", size(vanderpol_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "Split-I counts: ", diagnostics["split_i_counts"])
        println(io, "Split-P counts: ", diagnostics["split_p_counts"])
        println(io, "Split-P parameter ranges: ", split_p["parameter_ranges"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "state norm max: ", diagnostics["state_norm_max"])
        println(io, "velocity norm max: ", diagnostics["velocity_norm_max"])
        println(io, "tail sign changes min: ", diagnostics["tail_x1_sign_changes_min"])
        println(io, "formal_passed: ", diagnostics["formal_passed"])
        println(io, "manifest_path: ", manifest_path)
    end

    return Dict(
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "split_i_path" => split_i_path,
        "split_p_path" => split_p_path,
        "windows_i_summary_path" => windows_i_summary_path,
        "windows_p_summary_path" => windows_p_summary_path,
        "manifest_path" => manifest_path,
        "release_index_path" => release_index_path,
        "table_path" => table_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end

## Formal dataset generation entry point

function run_vanderpol_formal_generation()
    configs = load_vanderpol_formal_configs()
    spec, raw_trajectories = generate_vanderpol_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_vanderpol_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )

    split_i = build_vanderpol_split(raw_trajectories, configs["split_i"])
    split_p = build_vanderpol_parameter_split(raw_trajectories, configs["split_p"])
    window_summary_i = build_vanderpol_window_summary(split_i, spec.trajectory_length, configs["window"])
    window_summary_p = build_vanderpol_window_summary(split_p, spec.trajectory_length, configs["window"])

    diagnostics = summarize_vanderpol_dataset(spec, raw_trajectories, observed_trajectories)
    diagnostics["split_i_counts"] = Dict(
        "train" => length(split_i["train_trajectory_ids"]),
        "val" => length(split_i["val_trajectory_ids"]),
        "test" => length(split_i["test_trajectory_ids"]),
    )
    diagnostics["split_p_counts"] = Dict(
        "train" => length(split_p["train_trajectory_ids"]),
        "val" => length(split_p["val_trajectory_ids"]),
        "test" => length(split_p["test_trajectory_ids"]),
    )
    diagnostics["split_p_parameter_ranges"] = split_p["parameter_ranges"]
    diagnostics["one_step_window_counts"] = Dict(
        "split_i" => window_summary_i["one_step"]["counts"],
        "split_p" => window_summary_p["one_step"]["counts"],
    )
    diagnostics["rollout_window_counts"] = Dict(
        "split_i" => window_summary_i["rollout"]["by_horizon"],
        "split_p" => window_summary_p["rollout"]["by_horizon"],
    )
    diagnostics["statistics_window_counts"] = Dict(
        "split_i" => window_summary_i["statistics"]["counts"],
        "split_p" => window_summary_p["statistics"]["counts"],
    )

    output_paths = save_vanderpol_formal_outputs(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        raw_trajectories = raw_trajectories,
        observed_trajectories = observed_trajectories,
        split_i = split_i,
        split_p = split_p,
        window_summary_i = window_summary_i,
        window_summary_p = window_summary_p,
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

function print_vanderpol_formal_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("mu range: [%.6g, %.6g]\n", diagnostics["mu_min"], diagnostics["mu_max"])
    @printf("dt: %.6g\n", spec.dt)
    @printf("trajectory_length: %d\n", spec.trajectory_length)
    @printf("num_trajectories: %d\n", diagnostics["num_trajectories"])
    @printf("times size: %s\n", string(size(first_raw.times)))
    @printf("state_matrix size for first trajectory: %s\n", string(size(first_raw.state_matrix)))
    @printf("observation_matrix size for first trajectory: %s\n", string(size(first_observed.observation_matrix)))
    @printf(
        "Split-I train / val / test trajectory counts: %d / %d / %d\n",
        diagnostics["split_i_counts"]["train"],
        diagnostics["split_i_counts"]["val"],
        diagnostics["split_i_counts"]["test"],
    )
    @printf(
        "Split-P train / val / test trajectory counts: %d / %d / %d\n",
        diagnostics["split_p_counts"]["train"],
        diagnostics["split_p_counts"]["val"],
        diagnostics["split_p_counts"]["test"],
    )
    @printf("Split-P parameter ranges: %s\n", string(diagnostics["split_p_parameter_ranges"]))
    @printf("state range x1: [%.6g, %.6g]\n", diagnostics["x1_min"], diagnostics["x1_max"])
    @printf("state range x2: [%.6g, %.6g]\n", diagnostics["x2_min"], diagnostics["x2_max"])
    @printf("state norm max: %.6e\n", diagnostics["state_norm_max"])
    @printf("velocity norm max: %.6e\n", diagnostics["velocity_norm_max"])
    @printf("rk4 self residual max: %.6e\n", diagnostics["rk4_self_residual_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("tail x1 sign changes min: %d\n", diagnostics["tail_x1_sign_changes_min"])
    @printf("formal_passed: %s\n", string(diagnostics["formal_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_vanderpol_formal_generation()
    print_vanderpol_formal_summary(result)
    result["diagnostics"]["formal_passed"] || error("Van der Pol formal generation failed diagnostics")
end
