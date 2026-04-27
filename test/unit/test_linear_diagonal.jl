using Test
using Random

project_root = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(project_root, "src", "dynamics", "linear_diagonal.jl"))
include(joinpath(project_root, "src", "datasets", "trajectory_types.jl"))
include(joinpath(project_root, "src", "observations", "full_state.jl"))
include(joinpath(project_root, "src", "splits", "trajectory_split.jl"))
include(joinpath(project_root, "src", "windows", "window_builders.jl"))
include(joinpath(project_root, "src", "io", "jld2_io.jl"))
include(joinpath(project_root, "src", "manifests", "manifest_writer.jl"))
include(joinpath(project_root, "src", "diagnostics", "linear_system_checks.jl"))

@testset "linear diagonal exact generator" begin
    spec = LinearDiagonalSpec(
        "linear_diagonal",
        "unit_internal",
        2,
        [-1.0, 0.5],
        0.1,
        5,
        "exact_diagonal",
        1e-12,
        1e-12,
    )
    x0 = [0.5, -0.25]
    times, X = generate_linear_diagonal_trajectory(spec, x0)

    @test size(X) == (2, 6)
    @test length(times) == 6
    @test max_analytic_error(spec, x0, X, times) <= 1e-14
    @test max_one_step_residual(spec, X) <= 1e-14
end

@testset "full-state observation and protocol objects" begin
    spec = LinearDiagonalSpec(
        "linear_diagonal",
        "unit_internal",
        2,
        [-1.0, 0.5],
        0.1,
        5,
        "exact_diagonal",
        1e-12,
        1e-12,
    )
    times, X = generate_linear_diagonal_trajectory(spec, [0.5, -0.25])
    raw = RawTrajectory(
        "linear_diagonal_traj_0001",
        spec.system_id,
        Dict{String,Any}("eigenvalues" => spec.eigenvalues),
        [0.5, -0.25],
        times,
        X,
    )
    obs_spec = FullStateObservationSpec("full_state_identity", "full_state", "state", "none", 0.0, "none", "none", 2)
    observed = apply_full_state_observation(raw, obs_spec)

    @test observed.observation_matrix == raw.state_matrix
    @test observed.observation_matrix !== raw.state_matrix
    @test validate_raw_trajectory_dimensions(spec, raw)
    @test validate_observed_trajectory(observed)
end

@testset "trajectory split and windows" begin
    ids = [make_trajectory_id("linear_diagonal", i) for i in 1:10]
    split = build_trajectory_split(
        ids;
        train_ratio = 0.7,
        val_ratio = 0.15,
        test_ratio = 0.15,
        seed = 1,
        split_id = "split_I_70_15_15_seed1",
        split_type = "initial_condition",
    )

    @test length(split["train_trajectory_ids"]) == 7
    @test length(split["val_trajectory_ids"]) == 2
    @test length(split["test_trajectory_ids"]) == 1
    @test validate_trajectory_split(split, ids)

    one_step = build_one_step_windows(split, 5; window_id = "one_step_lag1", lag = 1)
    rollout = build_rollout_windows(split, 5; window_id = "rollout_horizon2", horizon = 2)

    @test validate_window_indices(one_step, split, 5)
    @test validate_window_indices(rollout, split, 5)
    @test window_counts(one_step)["train"] == 35
    @test window_counts(rollout)["train"] == 28
end

@testset "JLD2 and manifest smoke IO" begin
    spec = LinearDiagonalSpec(
        "linear_diagonal",
        "unit_internal",
        2,
        [-1.0, 0.5],
        0.1,
        5,
        "exact_diagonal",
        1e-12,
        1e-12,
    )
    times, X = generate_linear_diagonal_trajectory(spec, [0.5, -0.25])
    raw = RawTrajectory(
        "linear_diagonal_traj_0001",
        spec.system_id,
        Dict{String,Any}("eigenvalues" => spec.eigenvalues),
        [0.5, -0.25],
        times,
        X,
    )

    mktempdir() do dir
        raw_path = joinpath(dir, "raw.jld2")
        save_raw_trajectory(raw_path, raw)
        loaded = load_jld2_dict(raw_path)

        @test loaded["trajectory_id"] == raw.trajectory_id
        @test loaded["state_matrix"] == raw.state_matrix

        manifest = Dict(
            "dataset_version" => "0.1.0-dev",
            "release_date" => "2026-04-27",
            "benchmark_id" => "linear_diagonal_smoke",
            "system_id" => "linear_diagonal",
            "observation_id" => "full_state_identity",
            "split_id" => "split_I_70_15_15_seed1",
            "window_ids" => ["one_step_lag1"],
            "task_ids" => ["one_step_forecast"],
            "difficulty_level" => "small",
            "solver_name" => "exact_diagonal",
            "seed" => 1,
            "state_dim" => 2,
            "eigenvalues" => [-1.0, 0.5],
            "dt" => 0.1,
            "trajectory_length" => 5,
            "num_trajectories" => 1,
            "generated_files" => Dict("raw_trajectories" => [raw_path]),
            "diagnostics" => Dict("max_analytic_error" => 0.0),
        )
        @test validate_manifest(manifest)
    end
end
