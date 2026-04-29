## Benchmark configuration loading

using Dates
using Random

function linear_oscillator_project_path(project_root::AbstractString, relative_path::AbstractString)
    return joinpath(project_root, split(relative_path, '/')...)
end

## Random seed initialization and reproducibility metadata

function linear_oscillator_rng(config::AbstractDict)
    return MersenneTwister(Int(config["seed_policy"]["generation_seed"]))
end

## Initial-condition generation

function validate_linear_oscillator_box_domain(domain::AbstractDict)
    String(domain["type"]) == "box" ||
        throw(ArgumentError("initial_condition_domain type must be box"))
    length(domain["lower"]) == 2 || throw(ArgumentError("lower must have two entries"))
    length(domain["upper"]) == 2 || throw(ArgumentError("upper must have two entries"))
    all(Float64.(domain["lower"]) .< Float64.(domain["upper"])) ||
        throw(ArgumentError("each lower bound must be smaller than upper bound"))
    Float64(domain["min_norm"]) > 0 || throw(ArgumentError("min_norm must be positive"))
    return true
end

function sample_linear_oscillator_initial_condition(rng::AbstractRNG, domain::AbstractDict)
    validate_linear_oscillator_box_domain(domain)
    lower = Float64.(domain["lower"])
    upper = Float64.(domain["upper"])
    min_norm = Float64(domain["min_norm"])

    for _ in 1:10_000
        x0 = lower .+ (upper .- lower) .* rand(rng, 2)
        norm(x0) >= min_norm && return x0
    end

    throw(ArgumentError("failed to sample an initial condition above min_norm"))
end

## Raw state trajectory generation

function build_linear_oscillator_raw_trajectory(
    spec::LinearOscillatorSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_linear_oscillator_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "gamma" => spec.gamma,
        "omega0" => spec.omega0,
    )
    return RawTrajectory(
        make_trajectory_id(spec.system_id, trajectory_index),
        spec.system_id,
        parameter_instance,
        Float64.(x0),
        times,
        X,
    )
end

function generate_linear_oscillator_raw_trajectories(system_config::AbstractDict)
    spec = linear_oscillator_spec_from_config(system_config)
    validate_linear_oscillator_spec(spec)
    rng = linear_oscillator_rng(system_config)
    ic_domain = system_config["initial_condition_domain"]

    raw_trajectories = RawTrajectory[]
    for q in 1:Int(system_config["num_trajectories"])
        x0 = sample_linear_oscillator_initial_condition(rng, ic_domain)
        raw = build_linear_oscillator_raw_trajectory(spec, q, x0)
        validate_raw_trajectory_dimensions(spec, raw)
        push!(raw_trajectories, raw)
    end

    return spec, raw_trajectories
end

## Full-state observed trajectory construction

function generate_linear_oscillator_observed_trajectories(
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

## Train-val-test split generation

function build_linear_oscillator_split(raw_trajectories::AbstractVector{RawTrajectory}, split_config::AbstractDict)
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

## One-step and rollout window derivation

function build_linear_oscillator_window_summary(
    split::AbstractDict,
    trajectory_length::Integer,
    window_config::AbstractDict,
)
    one_step = window_config["one_step"]
    one_step_windows = build_one_step_windows(
        split,
        trajectory_length;
        window_id = one_step["window_id"],
        lag = Int(one_step["lag"]),
    )
    validate_window_indices(one_step_windows, split, trajectory_length)

    rollout_summaries = Dict{String,Any}()
    for horizon in Int.(window_config["rollout"]["horizons"])
        rollout_windows = build_rollout_windows(
            split,
            trajectory_length;
            window_id = string("linear_oscillator_rollout_h", horizon),
            horizon = horizon,
        )
        validate_window_indices(rollout_windows, split, trajectory_length)
        rollout_summaries[string("h", horizon)] = Dict(
            "window_id" => string("linear_oscillator_rollout_h", horizon),
            "horizon" => horizon,
            "counts" => window_counts(rollout_windows),
            "starts_per_trajectory" => trajectory_length + 1 - horizon,
        )
    end

    return Dict(
        "window_id" => window_config["window_id"],
        "one_step" => Dict(
            "window_id" => one_step["window_id"],
            "lag" => Int(one_step["lag"]),
            "counts" => window_counts(one_step_windows),
            "samples_per_trajectory" => trajectory_length,
        ),
        "rollout" => Dict(
            "window_id" => window_config["rollout"]["window_id"],
            "horizons" => Int.(window_config["rollout"]["horizons"]),
            "by_horizon" => rollout_summaries,
        ),
    )
end

function enrich_linear_oscillator_diagnostics!(
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

## Raw, processed, manifest, report saving

function linear_oscillator_matrix_tensor(matrices::AbstractVector{<:AbstractMatrix})
    first_matrix = first(matrices)
    X = Array{Float64}(undef, size(first_matrix, 1), size(first_matrix, 2), length(matrices))
    for (q, matrix) in enumerate(matrices)
        X[:, :, q] = matrix
    end
    return X
end

function save_linear_oscillator_raw(path::AbstractString, raw_trajectories::AbstractVector{RawTrajectory})
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_ids = [traj.trajectory_id for traj in raw_trajectories],
        system_id = first(raw_trajectories).system_id,
        parameter_instances = [traj.parameter_instance for traj in raw_trajectories],
        initial_conditions = hcat([traj.initial_condition_instance for traj in raw_trajectories]...),
        times = first(raw_trajectories).times,
        state_tensor = linear_oscillator_matrix_tensor([traj.state_matrix for traj in raw_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function save_linear_oscillator_observed(
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
        state_tensor = linear_oscillator_matrix_tensor([traj.state_matrix for traj in observed_trajectories]),
        observation_tensor = linear_oscillator_matrix_tensor([traj.observation_matrix for traj in observed_trajectories]),
        array_layout = "state_dim_by_time_by_trajectory",
    )
    return path
end

function linear_oscillator_csv_value(value)
    if value isa AbstractString
        return string('"', replace(value, "\"" => "\"\""), '"')
    else
        return string(value)
    end
end

function write_linear_oscillator_single_row_csv(
    path::AbstractString,
    columns::AbstractVector,
    values::AbstractVector,
)
    ensure_parent_dir(path)
    open(path, "w") do io
        println(io, join(columns, ","))
        println(io, join(linear_oscillator_csv_value.(values), ","))
    end
    return path
end

function maybe_save_linear_oscillator_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    spec::LinearOscillatorSpec,
    plot_dir::AbstractString,
)
    if !isdefined(Main, :PLOTS_AVAILABLE) || !Main.PLOTS_AVAILABLE
        if isdefined(Main, :PLOTS_LOAD_ERROR)
            @warn "Skipping linear oscillator plots because Plots.jl could not be loaded" exception = Main.PLOTS_LOAD_ERROR[]
        else
            @warn "Skipping linear oscillator plots because Plots.jl was not imported"
        end
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)

        p_time = Main.Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["q(t)" "v(t)"],
            title = "Linear oscillator time series",
        )
        time_path = joinpath(plot_dir, "linear_oscillator_time_series.png")
        Main.Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_phase = Main.Plots.plot(; xlabel = "q", ylabel = "v", title = "Linear oscillator phase portrait")
        for traj in raw_trajectories[1:min(12, length(raw_trajectories))]
            Main.Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, "linear_oscillator_phase_portrait.png")
        Main.Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        energies = linear_oscillator_energy_series(spec, first_raw.state_matrix)
        if spec.gamma == 0.0
            energy_center = first(energies)
            energy_pad = max(1e-12, 1e-6 * abs(energy_center))
            ylims = (energy_center - energy_pad, energy_center + energy_pad)
        else
            ylims = :auto
        end
        p_energy = Main.Plots.plot(
            first_raw.times,
            energies;
            xlabel = "t",
            ylabel = "E(t)",
            ylims = ylims,
            label = "energy",
            title = "Linear oscillator energy",
        )
        energy_path = joinpath(plot_dir, "linear_oscillator_energy.png")
        Main.Plots.savefig(p_energy, energy_path)
        push!(plot_files, energy_path)

        continuous = continuous_eigenvalues(spec)
        axis_radius = 1.2 * spec.omega0
        p_cont = Main.Plots.scatter(
            real.(continuous),
            imag.(continuous);
            xlabel = "real",
            ylabel = "imag",
            xlims = (-axis_radius, axis_radius),
            ylims = (-axis_radius, axis_radius),
            label = "continuous",
            title = "Continuous spectrum",
        )
        cont_path = joinpath(plot_dir, "linear_oscillator_continuous_spectrum.png")
        Main.Plots.savefig(p_cont, cont_path)
        push!(plot_files, cont_path)

        discrete = discrete_eigenvalues(spec)
        theta = range(0, 2pi; length = 200)
        p_disc = Main.Plots.plot(
            cos.(theta),
            sin.(theta);
            label = "unit circle",
            aspect_ratio = :equal,
            xlabel = "real",
            ylabel = "imag",
            title = "Discrete spectrum",
        )
        Main.Plots.scatter!(p_disc, real.(discrete), imag.(discrete); label = "truth")
        disc_path = joinpath(plot_dir, "linear_oscillator_discrete_spectrum.png")
        Main.Plots.savefig(p_disc, disc_path)
        push!(plot_files, disc_path)

        return plot_files
    catch err
        @warn "Skipping linear oscillator plots because plot generation failed" exception = err
        return String[]
    end
end

function make_linear_oscillator_manifest(;
    configs::AbstractDict,
    spec::LinearOscillatorSpec,
    observation_spec::FullStateObservationSpec,
    split::AbstractDict,
    window_summary::AbstractDict,
    generated_files::AbstractDict,
    diagnostics::AbstractDict,
)
    system_config = configs["system"]
    benchmark_config = configs["benchmark"]
    truth = linear_oscillator_metadata(spec)
    return Dict(
        "dataset_version" => benchmark_config["release_version"],
        "created_at" => string(now()),
        "benchmark_id" => benchmark_config["benchmark_id"],
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "state_dim" => spec.state_dim,
        "observation_dim" => observation_spec.output_dim,
        "gamma" => spec.gamma,
        "omega0" => spec.omega0,
        "dt" => spec.dt,
        "trajectory_length" => spec.trajectory_length,
        "num_trajectories" => Int(system_config["num_trajectories"]),
        "initial_condition_policy" => system_config["initial_condition_domain"],
        "observation_id" => observation_spec.observation_id,
        "split_id" => split["split_id"],
        "window_ids" => benchmark_config["window_ids"],
        "task_ids" => benchmark_config["task_ids"],
        "solver_name" => spec.solver_name,
        "solver_abstol" => spec.solver_abstol,
        "solver_reltol" => spec.solver_reltol,
        "seed" => system_config["seed_policy"]["generation_seed"],
        "array_layout" => "state_dim_by_time_by_trajectory",
        "continuous_matrix_A" => truth["continuous_matrix_A"],
        "discrete_matrix_F" => truth["discrete_matrix_F"],
        "continuous_eigenvalues" => truth["continuous_eigenvalues"],
        "discrete_eigenvalues" => truth["discrete_eigenvalues"],
        "generated_files" => generated_files,
        "split_counts" => diagnostics["split_counts"],
        "window_summary" => window_summary,
        "diagnostics" => diagnostics,
    )
end

function save_linear_oscillator_outputs(;
    project_root::AbstractString,
    configs::AbstractDict,
    spec::LinearOscillatorSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
    report_subdir::AbstractVector{<:AbstractString},
    release_id::AbstractString,
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = linear_oscillator_project_path(project_root, output_policy["raw_path"])
    processed_path = linear_oscillator_project_path(project_root, output_policy["processed_path"])
    split_path = linear_oscillator_project_path(project_root, output_policy["split_path"])
    windows_summary_path = linear_oscillator_project_path(project_root, output_policy["windows_summary_path"])
    manifest_path = linear_oscillator_project_path(project_root, output_policy["manifest_path"])
    release_index_path = linear_oscillator_project_path(project_root, output_policy["release_index_path"])

    table_path = joinpath(project_root, "reports", report_subdir[1], report_subdir[2], "tables", report_subdir[3:end]..., "diagnostics.csv")
    plot_dir = joinpath(project_root, "reports", report_subdir[1], report_subdir[2], "plots", report_subdir[3:end]...)
    log_path = joinpath(project_root, "reports", report_subdir[1], report_subdir[2], "logs", report_subdir[3:(end - 1)]..., string(last(report_subdir), ".log"))

    save_linear_oscillator_raw(raw_path, raw_trajectories)
    save_linear_oscillator_observed(processed_path, observed_trajectories)
    write_json_file(split_path, split)
    write_json_file(windows_summary_path, window_summary)

    plot_files = maybe_save_linear_oscillator_plots(raw_trajectories, spec, plot_dir)
    generated_files = Dict(
        "raw_trajectories" => raw_path,
        "processed_trajectories" => processed_path,
        "split" => split_path,
        "windows_summary" => windows_summary_path,
        "diagnostics_table" => table_path,
        "plots" => plot_files,
        "log" => log_path,
    )

    manifest = make_linear_oscillator_manifest(
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
        "release_id" => String(release_id),
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

    columns, values = linear_oscillator_diagnostics_csv_row(
        spec,
        observation_spec.observation_id,
        diagnostics,
    )
    write_linear_oscillator_single_row_csv(table_path, columns, values)

    ensure_parent_dir(log_path)
    open(log_path, "w") do io
        println(io, "benchmark_id: ", configs["benchmark"]["benchmark_id"])
        println(io, "system_id: ", spec.system_id)
        println(io, "variant: ", spec.variant)
        println(io, "observation_id: ", observation_spec.observation_id)
        println(io, "state_tensor size: ", size(linear_oscillator_matrix_tensor([traj.state_matrix for traj in raw_trajectories])))
        println(io, "split counts: ", diagnostics["split_counts"])
        println(io, "one-step window counts: ", diagnostics["one_step_window_counts"])
        println(io, "rollout window counts: ", diagnostics["rollout_window_counts"])
        println(io, "energy relative drift max: ", diagnostics["energy_relative_drift_max"])
        println(io, "energy step increase max: ", diagnostics["energy_step_increase_max"])
        println(io, "energy final ratio max: ", diagnostics["energy_final_ratio_max"])
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "rollout residual max: ", diagnostics["rollout_residual_max"])
        println(io, "discrete spectrum abs error max: ", diagnostics["discrete_spectrum_abs_error_max"])
        println(io, "discrete spectrum modulus max: ", diagnostics["discrete_spectrum_modulus_max"])
        println(io, "smoke_passed: ", diagnostics["smoke_passed"])
        println(io, "formal_passed: ", diagnostics["formal_passed"])
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
