## 1. Validate split ratios and trajectory IDs

using Random

function validate_split_ratios(train_ratio::Real, val_ratio::Real, test_ratio::Real; atol::Real = 1e-12)
    all(ratio -> ratio >= 0, (train_ratio, val_ratio, test_ratio)) ||
        throw(ArgumentError("split ratios must be nonnegative"))
    abs(train_ratio + val_ratio + test_ratio - 1.0) <= atol ||
        throw(ArgumentError("split ratios must sum to 1"))
    return true
end

function split_counts(n::Integer, ratios::NTuple{3,Float64})
    raw = collect(Float64(n) .* ratios)
    counts = floor.(Int, raw)
    remainder = n - sum(counts)
    fractions = raw .- counts
    for k in 1:remainder
        index = argmax(fractions)
        counts[index] += 1
        fractions[index] = -Inf
    end
    return counts
end

## 2. Shuffle trajectory IDs with fixed seed

function build_trajectory_split(
    trajectory_ids::AbstractVector{<:AbstractString};
    train_ratio::Real,
    val_ratio::Real,
    test_ratio::Real,
    seed::Integer,
    split_id::AbstractString = "split",
    split_type::AbstractString = "initial_condition",
)
    validate_split_ratios(train_ratio, val_ratio, test_ratio)
    length(unique(trajectory_ids)) == length(trajectory_ids) ||
        throw(ArgumentError("trajectory IDs must be unique"))

    ids = String.(trajectory_ids)
    shuffled = copy(ids)
    shuffle!(MersenneTwister(seed), shuffled)

    n_train, n_val, n_test = split_counts(
        length(shuffled),
        (Float64(train_ratio), Float64(val_ratio), Float64(test_ratio)),
    )

    train_ids = shuffled[1:n_train]
    val_ids = shuffled[(n_train + 1):(n_train + n_val)]
    test_ids = shuffled[(n_train + n_val + 1):(n_train + n_val + n_test)]

    split = Dict(
        "split_id" => String(split_id),
        "split_type" => String(split_type),
        "grouping_unit" => "trajectory",
        "seed" => Int(seed),
        "train_ratio" => Float64(train_ratio),
        "val_ratio" => Float64(val_ratio),
        "test_ratio" => Float64(test_ratio),
        "train_trajectory_ids" => train_ids,
        "val_trajectory_ids" => val_ids,
        "test_trajectory_ids" => test_ids,
    )

    validate_trajectory_split(split, ids)
    return split
end

## 3. Check disjointness and full coverage

function validate_trajectory_split(split::AbstractDict, all_ids::AbstractVector{<:AbstractString})
    train = Set(String.(split["train_trajectory_ids"]))
    val = Set(String.(split["val_trajectory_ids"]))
    test = Set(String.(split["test_trajectory_ids"]))
    allset = Set(String.(all_ids))

    isempty(intersect(train, val)) || throw(ArgumentError("train and val splits overlap"))
    isempty(intersect(train, test)) || throw(ArgumentError("train and test splits overlap"))
    isempty(intersect(val, test)) || throw(ArgumentError("val and test splits overlap"))
    union(train, val, test) == allset || throw(ArgumentError("split does not cover all trajectories"))
    return true
end
