## Smoke-test purpose and run identifier

using Dates
using JSON
using Printf
using Random

const PLOTS_LOAD_ERROR = Ref{Any}(nothing)
const PLOTS_AVAILABLE = try
    @eval import Plots
    true
catch err
    PLOTS_LOAD_ERROR[] = err
    false
end

const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(PROJECT_ROOT, "src", "dynamics", "linear_rotation_contraction_2d.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "exact_linear_trajectory_generator.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "rotation_contraction_diagnostics.jl"))

## Load benchmark configuration

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function project_path(relative_path::AbstractString)
    return joinpath(PROJECT_ROOT, split(relative_path, '/')...)
end

## Resolve system observation split window and task specs

function load_rotation_contraction_smoke_configs()
    benchmark_config = load_config(
        "benchmarks",
        "unit_internal",
        "benchmark_rotation_contraction_smoke.json",
    )

    return Dict(
        "benchmark" => benchmark_config,
        "system" => load_config("systems", "unit_internal", "linear_rotation_contraction_2d.json"),
        "observation" => load_config("observations", "unit_internal", "full_state_identity_clean.json"),
        "split" => load_config("splits", "unit_internal", "split_i_70_15_15_seed202604.json"),
        "one_step_window" => load_config("windows", "unit_internal", "one_step_lag1.json"),
        "rollout_window" => load_config("windows", "unit_internal", "rollout_h10_h50_h100.json"),
        "tasks" => [
            load_config("tasks", "unit_internal", "task_rotation_contraction_one_step.json"),
            load_config("tasks", "unit_internal", "task_rotation_contraction_rollout.json"),
            load_config("tasks", "unit_internal", "task_rotation_contraction_spectrum.json"),
        ],
    )
end

## Generate raw trajectories

function generate_raw_rotation_contraction_trajectories(system_config::AbstractDict)
    spec = linear_rotation_contraction_2d_spec_from_config(system_config)
    validate_linear_rotation_contraction_2d_spec(spec)
    rng = rotation_contraction_rng(system_config)
    ic_domain = system_config["initial_condition_domain"]

    raw_trajectories = RawTrajectory[]
    for q in 1:Int(system_config["num_trajectories"])
        x0 = sample_polar_annulus_initial_condition(rng, ic_domain)
        raw = build_rotation_contraction_raw_trajectory(spec, q, x0)
        validate_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

## Generate observed trajectories

function generate_clean_observed_trajectories(
    raw_trajectories::AbstractVector{RawTrajectory},
    observation_config::AbstractDict,
    state_dim::Integer,
)
    observation_spec = full_state_observation_spec_from_config(observation_config)
    validate_full_state_observation_spec(observation_spec, state_dim)
    observed = [apply_full_state_observation(raw, observation_spec) for raw in raw_trajectories]
    foreach(validate_observed_trajectory, observed)
    return observation_spec, observed
end

## Generate trajectory-level splits

function build_rotation_contraction_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
    trajectory_ids = [traj.trajectory_id for traj in raw_trajectories]
    return build_trajectory_split(
        trajectory_ids;
        train_ratio = Float64(split_config["train_ratio"]),
        val_ratio = Float64(split_config["val_ratio"]),
        test_ratio = Float64(split_config["test_ratio"]),
        seed = Int(split_config["seed"]),
        split_id = split_config["split_id"],
        split_type = split_config["split_type"],
    )
end

## Build window summaries

function build_rotation_contraction_window_summary(
    split::AbstractDict,
    trajectory_length::Integer,
    one_step_config::AbstractDict,
    rollout_config::AbstractDict,
)
    one_step_windows = build_one_step_windows(
        split,
        trajectory_length;
        window_id = one_step_config["window_id"],
        lag = Int(one_step_config["lag"]),
    )
    validate_window_indices(one_step_windows, split, trajectory_length)

    rollout_summaries = Dict{String,Any}()
    for horizon in Int.(rollout_config["horizons"])
        rollout_windows = build_rollout_windows(
            split,
            trajectory_length;
            window_id = string("rollout_horizon", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("rollout_horizon", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => trajectory_length + 1 - horizon,
        )
    end

    return Dict(
        "one_step" => Dict(
            "window_id" => one_step_config["window_id"],
            "lag" => Int(one_step_config["lag"]),
            "counts" => window_counts(one_step_windows),
            "samples_per_trajectory" => trajectory_length,
        ),
        "rollout" => Dict(
            "window_id" => rollout_config["window_id"],
            "horizons" => Int.(rollout_config["horizons"]),
            "by_horizon" => rollout_summaries,
        ),
    )
end

## Run rotation-contraction diagnostics

function enrich_rotation_contraction_diagnostics!(
    diagnostics::AbstractDict,
    split::AbstractDict,
    window_summary::AbstractDict,
)
    diagnostics["split_counts"] = Dict(
        "train" => length(split["train_trajectory_ids"]),
        "val" => length(split["val_trajectory_ids"]),
        "test" => length(split["test_trajectory_ids"]),
    )
    diagnostics["one_step_window_counts"] = window_summary["one_step"]["counts"]
    diagnostics["rollout_window_counts"] = Dict(
        horizon_key => summary["counts"]
        for (horizon_key, summary) in window_summary["rollout"]["by_horizon"]
    )
    return diagnostics
end

## Save data manifest tables plots and logs

function trajectory_tensor(raw_trajectories::AbstractVector{RawTrajectory})
    return matrix_tensor([traj.state_matrix for traj in raw_trajectories])
end

function matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function observation_tensor(observed_trajectories::AbstractVector{ObservedTrajectory})
    first_matrix = first(observed_trajectories).observation_matrix
    Z = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(observed_trajectories))
    for (q, traj) in enumerate(observed_trajectories)
        Z[:, :, q] = traj.observation_matrix
    end
    return Z
end

function save_rotation_contraction_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = trajectory_tensor(raw_trajectories),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_rotation_contraction_observed(
    path::AbstractString,
    observed_trajectories::AbstractVector{ObservedTrajectory},
)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in observed_trajectories],
        system_id = first(observed_trajectories).system_id,
        observation_id = first(observed_trajectories).observation_id,
        parameter_instances = [traj.parameter_instance for traj in observed_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in observed_trajectories]...),
        state_tensor = matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = observation_tensor(observed_trajectories),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_single_row_csv(path::AbstractString, columns::AbstractVector, values::AbstractVector)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(csv_value.(values), ","))
    end
    return path
end

function maybe_save_rotation_contraction_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    spec::LinearRotationContraction2DSpec,
    plot_dir::AbstractString,
)
    if !PLOTS_AVAILABLE
        @warn "Skipping smoke plots because Plots.jl could not be loaded" exception = PLOTS_LOAD_ERROR[]
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]

        p_phase = Plots.plot(; xlabel = "x1", ylabel = "x2", title = "Rotation-contraction phase portrait")
        for traj in raw_trajectories[1:min(8, length(raw_trajectories))]
            Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, "rotation_contraction_phase_portrait.png")
        Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        first_raw = first(raw_trajectories)
        radii = radii_from_state_matrix(first_raw.state_matrix)
        theory = radii[1] .* exp.(-spec.gamma .* first_raw.times)
        p_radius = Plots.plot(first_raw.times, radii; label = "empirical", xlabel = "t", ylabel = "radius")
        Plots.plot!(p_radius, first_raw.times, theory; label = "theory", title = "Radius decay")
        radius_path = joinpath(plot_dir, "rotation_contraction_radius_decay.png")
        Plots.savefig(p_radius, radius_path)
        push!(plot_files, radius_path)

        angle_increments = diff(unwrapped_angles_from_state_matrix(first_raw.state_matrix))
        p_angle = Plots.plot(
            first_raw.times[1:end - 1],
            angle_increments;
            label = "empirical",
            xlabel = "t",
            ylabel = "angle increment",
            title = "Angle increment",
        )
        Plots.hline!(p_angle, [rotation_angle_per_step(spec)]; label = "truth")
        angle_path = joinpath(plot_dir, "rotation_contraction_angle_increment.png")
        Plots.savefig(p_angle, angle_path)
        push!(plot_files, angle_path)

        lambdas = discrete_eigenvalues(spec)
        circle_theta = range(0, 2pi; length = 200)
        p_spectrum = Plots.plot(
            cos.(circle_theta),
            sin.(circle_theta);
            label = "unit circle",
            aspect_ratio = :equal,
            xlabel = "real",
            ylabel = "imag",
            title = "Discrete spectrum",
        )
        Plots.scatter!(p_spectrum, real.(lambdas), imag.(lambdas); label = "truth")
        spectrum_path = joinpath(plot_dir, "rotation_contraction_discrete_spectrum.png")
        Plots.savefig(p_spectrum, spectrum_path)
        push!(plot_files, spectrum_path)

        return plot_files
    catch err
        @warn "Skipping smoke plots because plot generation failed" exception = err
        return String[]
    end
end

function make_rotation_contraction_manifest(;
    configs::AbstractDict,
    spec::LinearRotationContraction2DSpec,
    observation_spec::FullStateObservationSpec,
    split::AbstractDict,
    window_summary::AbstractDict,
    generated_files::AbstractDict,
    diagnostics::AbstractDict,
)
    system_config = configs["system"]
    benchmark_config = configs["benchmark"]
    truth = linear_rotation_contraction_2d_metadata(spec)
    return Dict(
        "dataset_version" => "0.1.0-dev",
        "created_at" => string(now()),
        "benchmark_id" => benchmark_config["benchmark_id"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "state_dim" => spec.state_dim,
        "gamma" => spec.gamma,
        "omega" => spec.omega,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "num_trajectories" => Int(system_config["num_trajectories"]),
        "initial_condition_policy" => system_config["initial_condition_domain"],
        "observation_id" => observation_spec.observation_id,
        "split_id" => split["split_id"],
        "window_ids" => benchmark_config["window_ids"],
        "task_ids" => [task["task_id"] for task in configs["tasks"]],
        "solver_name" => spec.solver_name,
        "seed" => system_config["seed_policy"]["generation_seed"],
        "array_layout" => "state_dim_by_time_by_trajectory",
        "continuous_matrix_A" => truth["continuous_matrix_A"],
        "discrete_matrix_F" => truth["discrete_matrix_F"],
        "continuous_eigenvalues" => truth["continuous_eigenvalues"],
        "discrete_eigenvalues" => truth["discrete_eigenvalues"],
        "contraction_factor" => truth["contraction_factor"],
        "rotation_angle_per_step" => truth["rotation_angle_per_step"],
        "generator_commit_hash_or_local_placeholder" => "local_uncommitted_or_unknown",
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_rotation_contraction_outputs(;
    configs::AbstractDict,
    spec::LinearRotationContraction2DSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
    report_stem::AbstractString = "rotation_contraction_smoke",
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = project_path(output_policy["raw_path"])
    processed_path = project_path(output_policy["processed_path"])
    split_path = project_path(output_policy["split_path"])
    windows_summary_path = project_path(output_policy["windows_summary_path"])
    manifest_path = project_path(output_policy["manifest_path"])
    release_index_path = project_path(output_policy["release_index_path"])
    report_root = joinpath(PROJECT_ROOT, "reports", "unit_internal", "linear_rotation_contraction_2d")
    table_path = joinpath(report_root, "tables", string(report_stem, "_diagnostics.csv"))
    plot_dir = joinpath(report_root, "plots")
    log_path = joinpath(report_root, "logs", string(report_stem, ".log"))

    save_rotation_contraction_raw(raw_path, raw_trajectories)
    save_rotation_contraction_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_rotation_contraction_plots(raw_trajectories, spec, plot_dir)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_rotation_contraction_manifest(
        configs = configs,
        spec = spec,
        observation_spec = observation_spec,
        split = split,
        window_summary = window_summary,
        generated_files = generated_files,
        diagnostics = diagnostics,
    )
    write_json_file(manifest_path, manifest)

    release_index = Dict(
        "release_id" => "unit_internal_dev_rotation_contraction",
        "release_version" => configs["benchmark"]["release_version"],
        "system_id" => spec.system_id,
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "manifest_path" => manifest_path,
        "created_at" => string(now()),
    )
    write_json_file(release_index_path, release_index)

    columns, values = rotation_contraction_diagnostics_csv_row(
        spec,
        observation_spec.observation_id,
        diagnostics,
    )
    write_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(trajectory_tensor(raw_trajectories)))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "rho max abs error: ", diagnostics["rho_empirical_max_abs_error"])
        println(io, "theta max abs error: ", diagnostics["theta_step_max_abs_error"])
        println(io, "rollout residual max: ", diagnostics["rollout_residual_max"])
        println(io, "spectrum abs error max: ", diagnostics["spectrum_abs_error_max"])
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "manifest_path: ", manifest_path)
    end

    return Dict(
        "raw_path" => raw_path,
        "processed_path" => processed_path,
        "split_path" => split_path,
        "windows_summary_path" => windows_summary_path,
        "manifest_path" => manifest_path,
        "release_index_path" => release_index_path,
        "table_path" => table_path,
        "plot_files" => plot_files,
        "log_path" => log_path,
    )
end

## Print final smoke-test summary

function run_rotation_contraction_smoke()
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

function print_rotation_contraction_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("gamma: %.6g\n", spec.gamma)
    @printf("omega: %.12g\n", spec.omega)
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
    @printf("rho max abs error: %.6e\n", diagnostics["rho_empirical_max_abs_error"])
    @printf("theta max abs error: %.6e\n", diagnostics["theta_step_max_abs_error"])
    @printf("rollout residual max: %.6e\n", diagnostics["rollout_residual_max"])
    @printf("spectrum abs error max: %.6e\n", diagnostics["spectrum_abs_error_max"])
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_rotation_contraction_smoke()
    print_rotation_contraction_summary(result)
end
