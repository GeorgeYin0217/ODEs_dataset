## Diagnostic scope and required inputs

using LinearAlgebra
using Statistics

## Mechanical energy diagnostics

function energy_conservation_diagnostic(
    spec::LinearOscillatorSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
)
    drift_by_trajectory = Float64[]
    relative_drift_by_trajectory = Float64[]
    max_increase_by_trajectory = Float64[]
    final_ratio_by_trajectory = Float64[]

    for traj in raw_trajectories
        energies = linear_oscillator_energy_series(spec, traj.state_matrix)
        drift = maximum(abs.(energies .- first(energies)))
        push!(drift_by_trajectory, drift)
        push!(relative_drift_by_trajectory, drift / max(abs(first(energies)), eps(Float64)))
        push!(max_increase_by_trajectory, maximum(diff(energies)))
        push!(final_ratio_by_trajectory, last(energies) / max(first(energies), eps(Float64)))
    end

    return Dict(
        "energy_drift_max" => maximum(drift_by_trajectory),
        "energy_relative_drift_max" => maximum(relative_drift_by_trajectory),
        "energy_drift_mean" => mean(drift_by_trajectory),
        "energy_step_increase_max" => maximum(max_increase_by_trajectory),
        "energy_final_ratio_mean" => mean(final_ratio_by_trajectory),
        "energy_final_ratio_max" => maximum(final_ratio_by_trajectory),
    )
end

## Full-state observation consistency checks

function full_state_observation_error(observed_trajectories::AbstractVector{ObservedTrajectory})
    errors = [
        maximum(abs.(traj.observation_matrix .- traj.state_matrix))
        for traj in observed_trajectories
    ]
    return maximum(errors)
end

## Exact rollout and spectrum diagnostics

function max_one_step_residual(spec::LinearOscillatorSpec, X::AbstractMatrix)
    size(X) == (spec.state_dim, spec.trajectory_length + 1) ||
        throw(ArgumentError("X must have size (state_dim, trajectory_length + 1)"))

    F = exact_discrete_propagator(spec)
    residual = 0.0
    @inbounds for m in 1:spec.trajectory_length
        residual = max(residual, norm(X[:, m + 1] - F * X[:, m]))
    end
    return residual
end

function rollout_residual_diagnostic(
    spec::LinearOscillatorSpec,
    raw_trajectories::AbstractVector{RawTrajectory};
    horizons::AbstractVector{<:Integer},
    max_starts_per_trajectory::Integer = 8,
)
    F = exact_discrete_propagator(spec)
    by_horizon = Dict{String,Any}()
    global_max = 0.0

    for horizon in horizons
        horizon <= spec.trajectory_length ||
            throw(ArgumentError("rollout horizon cannot exceed trajectory_length"))
        residuals = Float64[]
        Fh = Matrix{Float64}(I, spec.state_dim, spec.state_dim)
        max_start_for_horizon = spec.trajectory_length + 1 - horizon
        start_indices = unique(round.(Int, range(1, max_start_for_horizon; length = min(max_starts_per_trajectory, max_start_for_horizon))))

        for ell in 1:horizon
            Fh = F * Fh
            for traj in raw_trajectories
                for s in start_indices
                    push!(residuals, norm(traj.state_matrix[:, s + ell] - Fh * traj.state_matrix[:, s]))
                end
            end
        end

        residual_max = maximum(residuals)
        global_max = max(global_max, residual_max)
        by_horizon[string("h", horizon)] = Dict(
            "rollout_horizon" => Int(horizon),
            "rollout_residual_mean" => mean(residuals),
            "rollout_residual_max" => residual_max,
            "sampled_starts_per_trajectory" => length(start_indices),
        )
    end

    return Dict(
        "rollout_residual_max" => global_max,
        "by_horizon" => by_horizon,
    )
end

function spectrum_diagnostic(spec::LinearOscillatorSpec)
    observed = eigvals(exact_discrete_propagator(spec))
    truth = discrete_eigenvalues(spec)
    abs_error = maximum([minimum(abs.(z .- truth)) for z in observed])
    moduli = abs.(truth)

    return Dict(
        "continuous_eigenvalues" => Dict(
            "lambda_plus" => linear_oscillator_complex_metadata(continuous_eigenvalues(spec)[1]),
            "lambda_minus" => linear_oscillator_complex_metadata(continuous_eigenvalues(spec)[2]),
        ),
        "discrete_eigenvalues" => Dict(
            "rho_plus" => linear_oscillator_complex_metadata(truth[1]),
            "rho_minus" => linear_oscillator_complex_metadata(truth[2]),
        ),
        "discrete_spectrum_abs_error_max" => abs_error,
        "discrete_spectrum_modulus_min" => minimum(moduli),
        "discrete_spectrum_modulus_max" => maximum(moduli),
        "discrete_spectrum_modulus_error_from_one_max" => maximum(abs.(moduli .- 1.0)),
    )
end

## Diagnostic threshold policy

function linear_oscillator_smoke_passed(diagnostics::AbstractDict; atol::Real = 1e-10)
    return diagnostics["energy_relative_drift_max"] <= atol &&
        diagnostics["full_state_observation_error_max"] <= atol &&
        diagnostics["rollout_residual_max"] <= atol &&
        diagnostics["discrete_spectrum_abs_error_max"] <= atol &&
        diagnostics["discrete_spectrum_modulus_error_from_one_max"] <= atol
end

function linear_oscillator_formal_passed(diagnostics::AbstractDict; atol::Real = 1e-10)
    return diagnostics["gamma"] > 0.0 &&
        diagnostics["gamma"] < diagnostics["omega0"] &&
        diagnostics["energy_step_increase_max"] <= atol &&
        diagnostics["energy_final_ratio_max"] < 1.0 &&
        diagnostics["full_state_observation_error_max"] <= atol &&
        diagnostics["rollout_residual_max"] <= atol &&
        diagnostics["discrete_spectrum_abs_error_max"] <= atol &&
        diagnostics["discrete_spectrum_modulus_max"] < 1.0
end

## Diagnostic table assembly

function summarize_linear_oscillator_dataset(
    spec::LinearOscillatorSpec,
    raw_trajectories::AbstractVector{RawTrajectory},
    observed_trajectories::AbstractVector{ObservedTrajectory};
    horizons::AbstractVector{<:Integer},
)
    energy = energy_conservation_diagnostic(spec, raw_trajectories)
    rollout = rollout_residual_diagnostic(spec, raw_trajectories; horizons = horizons)
    spectrum = spectrum_diagnostic(spec)
    one_step = maximum(max_one_step_residual(spec, traj.state_matrix) for traj in raw_trajectories)

    diagnostics = Dict{String,Any}(
        "system_id" => spec.system_id,
        "family" => spec.family,
        "variant" => spec.variant,
        "gamma" => spec.gamma,
        "omega0" => spec.omega0,
        "dt" => spec.dt,
        "num_trajectories" => length(raw_trajectories),
        "trajectory_length" => spec.trajectory_length,
        "state_matrix_size" => collect(size(first(raw_trajectories).state_matrix)),
        "array_layout" => "state_dim_by_time",
        "max_one_step_residual" => one_step,
        "full_state_observation_error_max" => full_state_observation_error(observed_trajectories),
    )

    merge!(diagnostics, energy)
    merge!(diagnostics, rollout)
    merge!(diagnostics, spectrum)
    diagnostics["smoke_passed"] = linear_oscillator_smoke_passed(diagnostics)
    diagnostics["formal_passed"] = linear_oscillator_formal_passed(diagnostics)
    return diagnostics
end

function linear_oscillator_diagnostics_csv_row(
    spec::LinearOscillatorSpec,
    observation_id::AbstractString,
    diagnostics::AbstractDict,
)
    columns = [
        "system_id",
        "observation_id",
        "variant",
        "gamma",
        "omega0",
        "dt",
        "energy_relative_drift_max",
        "full_state_observation_error_max",
        "rollout_residual_max",
        "discrete_spectrum_abs_error_max",
        "discrete_spectrum_modulus_error_from_one_max",
        "num_trajectories",
        "trajectory_length",
        "smoke_passed",
    ]
    values = [
        spec.system_id,
        String(observation_id),
        spec.variant,
        spec.gamma,
        spec.omega0,
        spec.dt,
        diagnostics["energy_relative_drift_max"],
        diagnostics["full_state_observation_error_max"],
        diagnostics["rollout_residual_max"],
        diagnostics["discrete_spectrum_abs_error_max"],
        diagnostics["discrete_spectrum_modulus_error_from_one_max"],
        diagnostics["num_trajectories"],
        diagnostics["trajectory_length"],
        diagnostics["smoke_passed"],
    ]
    return columns, values
end
