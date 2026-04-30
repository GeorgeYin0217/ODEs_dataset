## Raw controlled trajectory object definition

struct RawControlledTrajectory
    trajectory_id::String
    system_id::String
    parameter_instance::Dict{String,Any}
    initial_condition_instance::Vector{Float64}
    input_seed::Int
    times::Vector{Float64}
    state_matrix::Matrix{Float64}
    input_matrix::Matrix{Float64}
end

## Observed controlled trajectory object definition

struct ObservedControlledTrajectory
    trajectory_id::String
    system_id::String
    observation_id::String
    noise_level_id::String
    parameter_instance::Dict{String,Any}
    initial_condition_instance::Vector{Float64}
    input_seed::Int
    state_matrix::Matrix{Float64}
    input_matrix::Matrix{Float64}
    observation_matrix::Matrix{Float64}
    observed_input_matrix::Matrix{Float64}
    state_noise_matrix::Matrix{Float64}
    input_noise_matrix::Matrix{Float64}
end

## Controlled sample object definitions

struct OneStepControlledSample
    trajectory_id::String
    index_m::Int
    z_m::Vector{Float64}
    u_m::Vector{Float64}
    z_next::Vector{Float64}
end

struct RolloutControlledSample
    trajectory_id::String
    start_index::Int
    horizon::Int
    z_start::Vector{Float64}
    input_block::Matrix{Float64}
    target_block::Matrix{Float64}
end

## Dimension consistency checks

function validate_raw_controlled_trajectory(traj::RawControlledTrajectory)
    size(traj.state_matrix, 2) == size(traj.input_matrix, 2) + 1 ||
        throw(ArgumentError("state columns must equal input columns plus one"))
    length(traj.times) == size(traj.state_matrix, 2) ||
        throw(ArgumentError("times length must match state columns"))
    all(isfinite, traj.state_matrix) || throw(ArgumentError("state_matrix contains NaN or Inf"))
    all(isfinite, traj.input_matrix) || throw(ArgumentError("input_matrix contains NaN or Inf"))
    return true
end

function validate_observed_controlled_trajectory(traj::ObservedControlledTrajectory)
    size(traj.state_matrix) == size(traj.observation_matrix) ||
        throw(ArgumentError("observation_matrix must match state_matrix size"))
    size(traj.input_matrix) == size(traj.observed_input_matrix) ||
        throw(ArgumentError("observed_input_matrix must match input_matrix size"))
    size(traj.state_noise_matrix) == size(traj.state_matrix) ||
        throw(ArgumentError("state_noise_matrix must match state_matrix size"))
    size(traj.input_noise_matrix) == size(traj.input_matrix) ||
        throw(ArgumentError("input_noise_matrix must match input_matrix size"))
    size(traj.state_matrix, 2) == size(traj.input_matrix, 2) + 1 ||
        throw(ArgumentError("state/input time alignment is inconsistent"))
    all(isfinite, traj.observation_matrix) ||
        throw(ArgumentError("observation_matrix contains NaN or Inf"))
    all(isfinite, traj.observed_input_matrix) ||
        throw(ArgumentError("observed_input_matrix contains NaN or Inf"))
    return true
end
