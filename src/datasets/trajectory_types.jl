## 1. Define lightweight trajectory data objects

struct RawTrajectory
    trajectory_id::String
    system_id::String
    parameter_instance::Dict{String,Any}
    initial_condition_instance::Vector{Float64}
    times::Vector{Float64}
    state_matrix::Matrix{Float64}
end

struct ObservedTrajectory
    trajectory_id::String
    system_id::String
    observation_id::String
    parameter_instance::Dict{String,Any}
    initial_condition_instance::Vector{Float64}
    state_matrix::Matrix{Float64}
    observation_matrix::Matrix{Float64}
end

## 2. Convert typed objects to simple dictionaries for storage

function raw_trajectory_dict(traj::RawTrajectory)
    return Dict(
        "trajectory_id" => traj.trajectory_id,
        "system_id" => traj.system_id,
        "parameter_instance" => traj.parameter_instance,
        "initial_condition_instance" => traj.initial_condition_instance,
        "times" => traj.times,
        "state_matrix" => traj.state_matrix,
    )
end

function observed_trajectory_dict(traj::ObservedTrajectory)
    return Dict(
        "trajectory_id" => traj.trajectory_id,
        "system_id" => traj.system_id,
        "observation_id" => traj.observation_id,
        "parameter_instance" => traj.parameter_instance,
        "initial_condition_instance" => traj.initial_condition_instance,
        "state_matrix" => traj.state_matrix,
        "observation_matrix" => traj.observation_matrix,
    )
end

function make_trajectory_id(system_id::AbstractString, index::Integer)
    return string(system_id, "_traj_", lpad(string(index), 4, "0"))
end
