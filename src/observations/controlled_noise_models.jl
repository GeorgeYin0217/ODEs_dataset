## Controlled full-state observation spec

using Random
using Statistics

struct ControlledFullStateObservationSpec
    observation_id::String
    mode::String
    input_space_name::String
    noise_level_id::String
    noise_model::String
    state_noise_relative_rms::Float64
    input_noise_relative_rms::Float64
    normalization_policy::String
    quantization_policy::String
    output_dim::Int
    input_dim::Int
    seed_offset::Int
end

function controlled_full_state_observation_spec_from_config(config::AbstractDict)
    return ControlledFullStateObservationSpec(
        String(config["observation_id"]),
        String(config["mode"]),
        String(config["input_space_name"]),
        String(config["noise_level_id"]),
        String(config["noise_model"]),
        Float64(config["state_noise_relative_rms"]),
        Float64(config["input_noise_relative_rms"]),
        String(config["normalization_policy"]),
        String(config["quantization_policy"]),
        Int(config["output_dim"]),
        Int(config["input_dim"]),
        Int(config["seed_offset"]),
    )
end

function validate_controlled_full_state_observation_spec(
    spec::ControlledFullStateObservationSpec,
    state_dim::Integer,
    input_dim::Integer,
)
    spec.mode == "full_state" || throw(ArgumentError("controlled observation requires mode=full_state"))
    spec.input_space_name == "state_and_control" ||
        throw(ArgumentError("input_space_name must be state_and_control"))
    spec.noise_model in ("none", "relative_gaussian_rms") ||
        throw(ArgumentError("unsupported controlled noise_model"))
    spec.state_noise_relative_rms >= 0 ||
        throw(ArgumentError("state_noise_relative_rms must be nonnegative"))
    spec.input_noise_relative_rms >= 0 ||
        throw(ArgumentError("input_noise_relative_rms must be nonnegative"))
    if spec.noise_model == "none"
        spec.state_noise_relative_rms == 0.0 ||
            throw(ArgumentError("clean observation must have zero state noise"))
        spec.input_noise_relative_rms == 0.0 ||
            throw(ArgumentError("clean observation must have zero input noise"))
    end
    spec.normalization_policy == "none" ||
        throw(ArgumentError("controlled smoke only supports normalization_policy=none"))
    spec.quantization_policy == "none" ||
        throw(ArgumentError("controlled smoke only supports quantization_policy=none"))
    spec.output_dim == state_dim || throw(ArgumentError("output_dim must match state_dim"))
    spec.input_dim == input_dim || throw(ArgumentError("input_dim must match input_dim"))
    return true
end

## State and input noise construction

function rms_value(A::AbstractArray{<:Real})
    return sqrt(mean(abs2, Float64.(A)))
end

function exact_relative_gaussian_noise!(
    rng::AbstractRNG,
    noise::AbstractMatrix{Float64},
    reference::AbstractMatrix{<:Real},
    relative_rms::Real,
)
    fill!(noise, 0.0)
    relative_rms == 0 && return noise

    randn!(rng, noise)
    reference_rms = max(rms_value(reference), eps(Float64))
    noise_rms = max(rms_value(noise), eps(Float64))
    noise .*= Float64(relative_rms) * reference_rms / noise_rms
    return noise
end

## Clean and noisy observed controlled trajectories

function apply_controlled_full_state_observation(
    raw::RawControlledTrajectory,
    spec::ControlledFullStateObservationSpec,
)
    validate_controlled_full_state_observation_spec(
        spec,
        size(raw.state_matrix, 1),
        size(raw.input_matrix, 1),
    )

    state_noise = zeros(Float64, size(raw.state_matrix))
    input_noise = zeros(Float64, size(raw.input_matrix))
    if spec.noise_model == "relative_gaussian_rms"
        rng = MersenneTwister(raw.input_seed + spec.seed_offset)
        exact_relative_gaussian_noise!(
            rng,
            state_noise,
            raw.state_matrix,
            spec.state_noise_relative_rms,
        )
        exact_relative_gaussian_noise!(
            rng,
            input_noise,
            raw.input_matrix,
            spec.input_noise_relative_rms,
        )
    end

    observed = ObservedControlledTrajectory(
        raw.trajectory_id,
        raw.system_id,
        spec.observation_id,
        spec.noise_level_id,
        deepcopy(raw.parameter_instance),
        copy(raw.initial_condition_instance),
        raw.input_seed,
        copy(raw.state_matrix),
        copy(raw.input_matrix),
        raw.state_matrix .+ state_noise,
        raw.input_matrix .+ input_noise,
        state_noise,
        input_noise,
    )
    validate_observed_controlled_trajectory(observed)
    return observed
end
