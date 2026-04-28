## Load smoke benchmark configuration

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

include(joinpath(PROJECT_ROOT, "src", "dynamics", "linear_oscillator.jl"))
include(joinpath(PROJECT_ROOT, "src", "datasets", "trajectory_types.jl"))
include(joinpath(PROJECT_ROOT, "src", "observations", "full_state.jl"))
include(joinpath(PROJECT_ROOT, "src", "splits", "trajectory_split.jl"))
include(joinpath(PROJECT_ROOT, "src", "windows", "window_builders.jl"))
include(joinpath(PROJECT_ROOT, "src", "io", "jld2_io.jl"))
include(joinpath(PROJECT_ROOT, "src", "manifests", "manifest_writer.jl"))
include(joinpath(PROJECT_ROOT, "src", "diagnostics", "linear_oscillator_diagnostics.jl"))
include(joinpath(PROJECT_ROOT, "src", "generators", "linear_oscillator_dataset_generator.jl"))

load_config(parts...) = JSON.parsefile(joinpath(PROJECT_ROOT, "configs", parts...))

function load_linear_oscillator_smoke_configs()
    return Dict(
        "benchmark" => load_config("benchmarks", "smoke_linear_oscillator_undamped_full_state.json"),
        "system" => load_config("systems", "linear_oscillator_smoke_undamped.json"),
        "observation" => load_config("observations", "full_state_2d_clean.json"),
        "split" => load_config("splits", "linear_oscillator_smoke_split_i.json"),
        "window" => load_config("windows", "linear_oscillator_smoke_windows.json"),
        "tasks" => load_config("tasks", "linear_oscillator_forecasting_tasks.json"),
    )
end

## Confirm undamped full-state setup

function validate_linear_oscillator_smoke_configs(configs::AbstractDict)
    spec = linear_oscillator_spec_from_config(configs["system"])
    validate_linear_oscillator_spec(spec)
    spec.gamma == 0.0 || throw(ArgumentError("smoke must use gamma=0"))

    observation_spec = full_state_observation_spec_from_config(configs["observation"])
    validate_full_state_observation_spec(observation_spec, spec.state_dim)

    return spec, observation_spec
end

## Save smoke data and reports

function maybe_save_linear_oscillator_plots(
    raw_trajectories::AbstractVector{RawTrajectory},
    spec::LinearOscillatorSpec,
    plot_dir::AbstractString,
)
    if !PLOTS_AVAILABLE
        @warn "Skipping smoke plots because Plots.jl could not be loaded" exception = PLOTS_LOAD_ERROR[]
        return String[]
    end

    try
        mkpath(plot_dir)
        plot_files = String[]
        first_raw = first(raw_trajectories)

        p_time = Plots.plot(
            first_raw.times,
            first_raw.state_matrix';
            xlabel = "t",
            ylabel = "state",
            label = ["q(t)" "v(t)"],
            title = "Linear oscillator time series",
        )
        time_path = joinpath(plot_dir, "linear_oscillator_time_series.png")
        Plots.savefig(p_time, time_path)
        push!(plot_files, time_path)

        p_phase = Plots.plot(; xlabel = "q", ylabel = "v", title = "Linear oscillator phase portrait")
        for traj in raw_trajectories
            Plots.plot!(p_phase, traj.state_matrix[1, :], traj.state_matrix[2, :]; label = false)
        end
        phase_path = joinpath(plot_dir, "linear_oscillator_phase_portrait.png")
        Plots.savefig(p_phase, phase_path)
        push!(plot_files, phase_path)

        energies = linear_oscillator_energy_series(spec, first_raw.state_matrix)
        energy_center = first(energies)
        energy_pad = max(1e-12, 1e-6 * abs(energy_center))
        p_energy = Plots.plot(
            first_raw.times,
            energies;
            xlabel = "t",
            ylabel = "E(t)",
            ylims = (energy_center - energy_pad, energy_center + energy_pad),
            label = "energy",
            title = "Undamped oscillator energy",
        )
        energy_path = joinpath(plot_dir, "linear_oscillator_energy.png")
        Plots.savefig(p_energy, energy_path)
        push!(plot_files, energy_path)

        continuous = continuous_eigenvalues(spec)
        p_cont = Plots.scatter(
            real.(continuous),
            imag.(continuous);
            xlabel = "real",
            ylabel = "imag",
            xlims = (-1.2 * spec.omega0, 1.2 * spec.omega0),
            ylims = (-1.2 * spec.omega0, 1.2 * spec.omega0),
            label = "continuous",
            title = "Continuous spectrum",
        )
        cont_path = joinpath(plot_dir, "linear_oscillator_continuous_spectrum.png")
        Plots.savefig(p_cont, cont_path)
        push!(plot_files, cont_path)

        discrete = discrete_eigenvalues(spec)
        theta = range(0, 2pi; length = 200)
        p_disc = Plots.plot(
            cos.(theta),
            sin.(theta);
            label = "unit circle",
            aspect_ratio = :equal,
            xlabel = "real",
            ylabel = "imag",
            title = "Discrete spectrum",
        )
        Plots.scatter!(p_disc, real.(discrete), imag.(discrete); label = "truth")
        disc_path = joinpath(plot_dir, "linear_oscillator_discrete_spectrum.png")
        Plots.savefig(p_disc, disc_path)
        push!(plot_files, disc_path)

        return plot_files
    catch err
        @warn "Skipping smoke plots because plot generation failed" exception = err
        return String[]
    end
end

function save_linear_oscillator_smoke_outputs(;
    configs::AbstractDict,
    spec::LinearOscillatorSpec,
    observation_spec::FullStateObservationSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory},
    split::AbstractDict,
    window_summary::AbstractDict,
    diagnostics::AbstractDict,
)
    output_policy = configs["benchmark"]["output_policy"]
    raw_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["raw_path"])
    processed_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["processed_path"])
    split_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["split_path"])
    windows_summary_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["windows_summary_path"])
    manifest_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["manifest_path"])
    release_index_path = linear_oscillator_project_path(PROJECT_ROOT, output_policy["release_index_path"])
    table_path = joinpath(
        PROJECT_ROOT,
        "reports",
        "tables",
        "v1_core",
        "linear_oscillator",
        "smoke_undamped_full_state",
        "diagnostics.csv",
    )
    plot_dir = joinpath(
        PROJECT_ROOT,
        "reports",
        "plots",
        "v1_core",
        "linear_oscillator",
        "smoke_undamped_full_state",
    )
    log_path = joinpath(
        PROJECT_ROOT,
        "reports",
        "logs",
        "v1_core",
        "linear_oscillator",
        "smoke_undamped_full_state.log",
    )

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
        "release_id" => "linear_oscillator_smoke_undamped_full_state",
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
        println(io, "full-state observation error max: ", diagnostics["full_state_observation_error_max"])
        println(io, "rollout residual max: ", diagnostics["rollout_residual_max"])
        println(io, "discrete spectrum abs error max: ", diagnostics["discrete_spectrum_abs_error_max"])
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

## Run minimal linear oscillator generation

function run_linear_oscillator_smoke()
    configs = load_linear_oscillator_smoke_configs()
    spec, observation_spec = validate_linear_oscillator_smoke_configs(configs)

    spec, raw_trajectories = generate_linear_oscillator_raw_trajectories(configs["system"])
    observation_spec, observed_trajectories = generate_linear_oscillator_observed_trajectories(
        raw_trajectories,
        configs["observation"],
        spec.state_dim,
    )
    split = build_linear_oscillator_split(raw_trajectories, configs["split"])
    window_summary = build_linear_oscillator_window_summary(
        split,
        spec.trajectory_length,
        configs["window"],
    )

    horizons = Int.(configs["window"]["rollout"]["horizons"])
    diagnostics = summarize_linear_oscillator_dataset(
        spec,
        raw_trajectories,
        observed_trajectories;
        horizons = horizons,
    )
    enrich_linear_oscillator_diagnostics!(diagnostics, split, window_summary)

    output_paths = save_linear_oscillator_smoke_outputs(
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

## Print smoke summary

function print_linear_oscillator_smoke_summary(result::AbstractDict)
    spec = result["system_spec"]
    observation_spec = result["observation_spec"]
    diagnostics = result["diagnostics"]
    first_raw = result["first_raw_trajectory"]
    first_observed = result["first_observed_trajectory"]
    output_paths = result["output_paths"]

    @printf("system_id: %s\n", spec.system_id)
    @printf("variant: %s\n", spec.variant)
    @printf("observation_id: %s\n", observation_spec.observation_id)
    @printf("gamma: %.6g\n", spec.gamma)
    @printf("omega0: %.12g\n", spec.omega0)
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
    @printf("energy relative drift max: %.6e\n", diagnostics["energy_relative_drift_max"])
    @printf("full-state observation error max: %.6e\n", diagnostics["full_state_observation_error_max"])
    @printf("rollout residual max: %.6e\n", diagnostics["rollout_residual_max"])
    @printf("discrete spectrum abs error max: %.6e\n", diagnostics["discrete_spectrum_abs_error_max"])
    @printf("discrete spectrum modulus error from one max: %.6e\n", diagnostics["discrete_spectrum_modulus_error_from_one_max"])
    @printf("smoke_passed: %s\n", string(diagnostics["smoke_passed"]))
    @printf("raw output: %s\n", output_paths["raw_path"])
    @printf("processed output: %s\n", output_paths["processed_path"])
    @printf("manifest path: %s\n", output_paths["manifest_path"])
    @printf("diagnostics table: %s\n", output_paths["table_path"])
    @printf("log path: %s\n", output_paths["log_path"])
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    result = run_linear_oscillator_smoke()
    print_linear_oscillator_smoke_summary(result)
end
