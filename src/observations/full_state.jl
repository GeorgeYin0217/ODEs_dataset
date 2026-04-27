## 1. Define full-state observation spec assumptions

struct FullStateObservationSpec
    observation_id::String
    mode::String
    input_space_name::String
    noise_model::String
    noise_level::Float64
    normalization_policy::String
    quantization_policy::String
    output_dim::Int
end

function full_state_observation_spec_from_config(config::AbstractDict)
    return FullStateObservationSpec(
        String(config["observation_id"]),
        String(config["mode"]),
        String(config["input_space_name"]),
        String(config["noise_model"]),
        Float64(config["noise_level"]),
        String(config["normalization_policy"]),
        String(config["quantization_policy"]),
        Int(config["output_dim"]),
    )
end

function validate_full_state_observation_spec(spec::FullStateObservationSpec, state_dim::Integer)
    spec.mode == "full_state" || throw(ArgumentError("full-state observation requires mode=full_state"))
    spec.noise_model == "none" || throw(ArgumentError("first full-state baseline only supports noise_model=none"))
    spec.noise_level == 0.0 || throw(ArgumentError("first full-state baseline only supports noise_level=0"))
    spec.normalization_policy == "none" ||
        throw(ArgumentError("first full-state baseline only supports normalization_policy=none"))
    spec.quantization_policy == "none" ||
        throw(ArgumentError("first full-state baseline only supports quantization_policy=none"))
    spec.output_dim == state_dim || throw(ArgumentError("output_dim must match state_dim"))
    return true
end

## 2. Apply identity observation chain U = S = Z = I

function apply_full_state_observation(raw::RawTrajectory, spec::FullStateObservationSpec)
    validate_full_state_observation_spec(spec, size(raw.state_matrix, 1))
    observation_matrix = copy(raw.state_matrix)
    return ObservedTrajectory(
        raw.trajectory_id,
        raw.system_id,
        spec.observation_id,
        deepcopy(raw.parameter_instance),
        copy(raw.initial_condition_instance),
        copy(raw.state_matrix),
        observation_matrix,
    )
end

## 3. Validate observation dimension and matrix orientation

function validate_observed_trajectory(traj::ObservedTrajectory)
    size(traj.state_matrix) == size(traj.observation_matrix) ||
        throw(ArgumentError("full-state observation_matrix must match state_matrix size"))
    return true
end
