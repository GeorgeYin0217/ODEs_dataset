## 1. Define one-step window index format

function build_one_step_windows(
    split::AbstractDict,
    trajectory_length::Integer;
    window_id::AbstractString = "one_step_lag1",
    lag::Integer = 1,
)
    lag == 1 || throw(ArgumentError("only lag=1 is supported in the first baseline"))
    trajectory_length >= 1 || throw(ArgumentError("trajectory_length must be at least 1"))

    windows = Dict{String,Any}(
        "window_id" => String(window_id),
        "window_type" => "one_step",
        "lag" => Int(lag),
        "splits" => Dict{String,Any}(),
    )

    for split_name in ("train", "val", "test")
        ids = split[string(split_name, "_trajectory_ids")]
        windows["splits"][split_name] = [
            Dict("trajectory_id" => id, "index_m" => m, "lag" => Int(lag))
            for id in ids for m in 1:trajectory_length
        ]
    end

    return windows
end

## 2. Define rollout window index format

function build_rollout_windows(
    split::AbstractDict,
    trajectory_length::Integer;
    window_id::AbstractString = "rollout_horizon20",
    horizon::Integer,
)
    horizon >= 1 || throw(ArgumentError("horizon must be at least 1"))
    horizon <= trajectory_length || throw(ArgumentError("horizon cannot exceed trajectory_length"))

    max_start = trajectory_length + 1 - horizon
    windows = Dict{String,Any}(
        "window_id" => String(window_id),
        "window_type" => "rollout",
        "horizon" => Int(horizon),
        "splits" => Dict{String,Any}(),
    )

    for split_name in ("train", "val", "test")
        ids = split[string(split_name, "_trajectory_ids")]
        windows["splits"][split_name] = [
            Dict("trajectory_id" => id, "start_index" => s, "horizon" => Int(horizon))
            for id in ids for s in 1:max_start
        ]
    end

    return windows
end

## 3. Define statistics window index format

function build_statistics_windows(
    split::AbstractDict,
    trajectory_length::Integer;
    window_id::AbstractString = "statistics_horizon100",
    horizon::Integer,
)
    horizon >= 1 || throw(ArgumentError("horizon must be at least 1"))
    horizon <= trajectory_length + 1 || throw(ArgumentError("horizon cannot exceed trajectory_length + 1"))

    max_start = trajectory_length + 2 - horizon
    windows = Dict{String,Any}(
        "window_id" => String(window_id),
        "window_type" => "statistics",
        "horizon" => Int(horizon),
        "splits" => Dict{String,Any}(),
    )

    for split_name in ("train", "val", "test")
        ids = split[string(split_name, "_trajectory_ids")]
        windows["splits"][split_name] = [
            Dict("trajectory_id" => id, "start_index" => s, "horizon" => Int(horizon))
            for id in ids for s in 1:max_start
        ]
    end

    return windows
end

## 4. Check horizon bounds and split isolation

function validate_window_indices(windows::AbstractDict, split::AbstractDict, trajectory_length::Integer)
    window_type = windows["window_type"]

    for split_name in ("train", "val", "test")
        allowed = Set(String.(split[string(split_name, "_trajectory_ids")]))
        for window in windows["splits"][split_name]
            String(window["trajectory_id"]) in allowed ||
                throw(ArgumentError("window trajectory_id is outside its split"))

            if window_type == "one_step"
                1 <= Int(window["index_m"]) <= trajectory_length ||
                    throw(ArgumentError("one-step index_m is out of bounds"))
            elseif window_type == "rollout"
                horizon = Int(window["horizon"])
                1 <= Int(window["start_index"]) <= trajectory_length + 1 - horizon ||
                    throw(ArgumentError("rollout start_index is out of bounds"))
            elseif window_type == "statistics"
                horizon = Int(window["horizon"])
                1 <= Int(window["start_index"]) <= trajectory_length + 2 - horizon ||
                    throw(ArgumentError("statistics start_index is out of bounds"))
            else
                throw(ArgumentError("unsupported window_type: $(window_type)"))
            end
        end
    end

    return true
end

function window_counts(windows::AbstractDict)
    return Dict(
        split_name => length(windows["splits"][split_name])
        for split_name in ("train", "val", "test")
    )
end
