## Generator scope and supported linear systems

using Random

## Configuration validation before generation

function validate_polar_annulus_domain(domain::AbstractDict)
    String(domain["type"]) == "polar_annulus" ||
        throw(ArgumentError("initial_condition_domain type must be polar_annulus"))
    Float64(domain["radius_lower"]) > 0 ||
        throw(ArgumentError("radius_lower must be positive"))
    Float64(domain["radius_lower"]) < Float64(domain["radius_upper"]) ||
        throw(ArgumentError("radius_lower must be smaller than radius_upper"))
    Float64(domain["angle_lower"]) < Float64(domain["angle_upper"]) ||
        throw(ArgumentError("angle_lower must be smaller than angle_upper"))
    return true
end

## Random seed and trajectory-id policy

function rotation_contraction_rng(config::AbstractDict)
    return MersenneTwister(Int(config["seed_policy"]["generation_seed"]))
end

## Initial-condition sampling dispatch

function sample_polar_annulus_initial_condition(rng::AbstractRNG, domain::AbstractDict)
    validate_polar_annulus_domain(domain)
    r = Float64(domain["radius_lower"]) +
        (Float64(domain["radius_upper"]) - Float64(domain["radius_lower"])) * rand(rng)
    theta = Float64(domain["angle_lower"]) +
        (Float64(domain["angle_upper"]) - Float64(domain["angle_lower"])) * rand(rng)
    return [r * cos(theta), r * sin(theta)]
end

## Exact discrete propagation loop

function generate_exact_linear_trajectory(spec::LinearRotationContraction2DSpec, x0::AbstractVector{<:Real})
    return generate_linear_rotation_contraction_2d_trajectory(spec, x0)
end

## RawTrajectory assembly

function build_rotation_contraction_raw_trajectory(
    spec::LinearRotationContraction2DSpec,
    trajectory_index::Integer,
    x0::AbstractVector{<:Real},
)
    times, X = generate_exact_linear_trajectory(spec, x0)
    parameter_instance = Dict{String,Any}(
        "gamma" => spec.gamma,
        "omega" => spec.omega,
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

function validate_raw_trajectory_dimensions(spec::LinearRotationContraction2DSpec, traj::RawTrajectory)
    size(traj.state_matrix) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("state_matrix has wrong orientation or size"))
    length(traj.times) == spec.trajectory_length + 1 ||
        throw(ArgumentError("times length must be trajectory_length + 1"))
    return true
end
