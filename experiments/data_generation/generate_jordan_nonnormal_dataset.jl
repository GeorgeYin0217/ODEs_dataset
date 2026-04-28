## Formal generation purpose

using Printf

project_root = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(project_root, "experiments", "smoke_tests", "run_jordan_nonnormal_smoke.jl"))

## Load formal benchmark configuration

function load_jordan_formal_configs()
    benchmark_config = load_config(
        "benchmarks",
        "unit_internal",
        "jordan_nonnormal_formal_benchmark.json",
    )

    return Dict(
        "benchmark" => benchmark_config,
        "system" => load_config("systems", "unit_internal", "jordan_nonnormal_linear_formal.json"),
        "observation" => load_config("observations", "unit_internal", "full_state_identity_clean.json"),
        "split" => load_config("splits", "unit_internal", "jordan_split_i_formal.json"),
        "one_step_window" => load_config("windows", "unit_internal", "one_step_lag1.json"),
        "rollout_window" => load_config("windows", "unit_internal", "jordan_rollout_formal.json"),
        "tasks" => [
            load_config("tasks", "unit_internal", "jordan_one_step_forecast.json"),
            load_config("tasks", "unit_internal", "jordan_rollout_forecast_formal.json"),
        ],
    )
end

## Generate formal dataset

function generate_jordan_nonnormal_dataset()
    configs = load_jordan_formal_configs()
    spec, raw_trajectories = generate_raw_jordan_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_clean_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_jordan_split(raw_trajectories, configs["split"])
    window_summary = build_jordan_window_summary(
        split,
        spec.trajectory_length,
        configs["one_step_window"],
        configs["rollout_window"],
    )
    horizons = Int.(configs["rollout_window"]["horizons"])
    diagnostics = summarize_jordan_nonnormal_dataset(spec, raw_trajectories; horizons = horizons)
    enrich_jordan_diagnostics!(diagnostics, split, window_summary)
    output_paths = save_jordan_outputs(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        raw_trajectories = raw_trajectories,
        observed_trajectories = observed_trajectories,
        split = split,
        window_summary = window_summary,
        diagnostics = diagnostics,
        run_label = "formal",
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

function print_jordan_generation_summary(result::AbstractDict)
    print_jordan_summary(result)
    @printf("formal generation entry: %s\n", @__FILE__)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = generate_jordan_nonnormal_dataset()
    print_jordan_generation_summary(result)
end
