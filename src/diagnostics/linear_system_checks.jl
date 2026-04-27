## 1. Analytic and protocol diagnostics for linear diagonal datasets

function dataset_max_analytic_error(spec::LinearDiagonalSpec, raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(
        max_analytic_error(spec, traj.initial_condition_instance, traj.state_matrix, traj.times)
        for traj in raw_trajectories
    )
end

function dataset_max_one_step_residual(spec::LinearDiagonalSpec, raw_trajectories::AbstractVector{RawTrajectory})
    return maximum(max_one_step_residual(spec, traj.state_matrix) for traj in raw_trajectories)
end

function validate_raw_trajectory_dimensions(spec::LinearDiagonalSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    return true
end

function summarize_linear_dataset(spec::LinearDiagonalSpec, raw_trajectories::AbstractVector{RawTrajectory})
    max_abs_state = maximum(maximum(abs.(traj.state_matrix)) for traj in raw_trajectories)
    return Dict(
        "max_abs_state" => max_abs_state,
        "max_analytic_error" => dataset_max_analytic_error(spec, raw_trajectories),
        "max_one_step_residual" => dataset_max_one_step_residual(spec, raw_trajectories),
        "num_trajectories" => length(raw_trajectories),
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
    )
end

function validate_generated_file_list(paths::AbstractVector{<:AbstractString})
    for path in paths
        assert_file_exists(path)
    end
    return true
end
