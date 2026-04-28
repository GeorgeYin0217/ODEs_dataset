## Formal data-generation entry point

using Printf

project_root = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(project_root, "experiments", "smoke_tests", "run_rotation_contraction_smoke.jl"))

## Run the validated rotation-contraction data factory

function generate_rotation_contraction_dataset()
    configs = load_rotation_contraction_smoke_configs()
    spec, raw_trajectories = generate_raw_rotation_contraction_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_clean_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_rotation_contraction_split(raw_trajectories, configs["split"])
    window_summary = build_rotation_contraction_window_summary(
        split,
        spec.trajectory_length,
        configs["one_step_window"],
        configs["rollout_window"],
    )
    horizons = Int.(configs["rollout_window"]["horizons"])
    diagnostics = summarize_rotation_contraction_dataset(spec, raw_trajectories; horizons = horizons)
    enrich_rotation_contraction_diagnostics!(diagnostics, split, window_summary)
    output_paths = save_rotation_contraction_outputs(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        raw_trajectories = raw_trajectories,
        observed_trajectories = observed_trajectories,
        split = split,
        window_summary = window_summary,
        diagnostics = diagnostics,
        report_stem = "rotation_contraction_generation",
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

## Print final generation summary

function print_rotation_contraction_generation_summary(result::AbstractDict)
    print_rotation_contraction_summary(result)
    @printf("formal generation entry: %s\n", @__FILE__)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = generate_rotation_contraction_dataset()
    print_rotation_contraction_generation_summary(result)
end
