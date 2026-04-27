## 1. Save and load trajectory objects as simple JLD2 fields

using JLD2

function ensure_parent_dir(path::AbstractString)
    dir = dirname(path)
    if !isempty(dir)
        mkpath(dir)
    end
    return path
end

function save_raw_trajectory(path::AbstractString, traj::RawTrajectory)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_id = traj.trajectory_id,
        system_id = traj.system_id,
        parameter_instance = traj.parameter_instance,
        initial_condition_instance = traj.initial_condition_instance,
        times = traj.times,
        state_matrix = traj.state_matrix,
    )
    return path
end

function save_observed_trajectory(path::AbstractString, traj::ObservedTrajectory)
    ensure_parent_dir(path)
    JLD2.jldsave(
        path;
        trajectory_id = traj.trajectory_id,
        system_id = traj.system_id,
        observation_id = traj.observation_id,
        parameter_instance = traj.parameter_instance,
        initial_condition_instance = traj.initial_condition_instance,
        state_matrix = traj.state_matrix,
        observation_matrix = traj.observation_matrix,
    )
    return path
end

load_jld2_dict(path::AbstractString) = JLD2.load(path)

function assert_file_exists(path::AbstractString)
    isfile(path) || throw(ArgumentError("file does not exist: $(path)"))
    return true
end
