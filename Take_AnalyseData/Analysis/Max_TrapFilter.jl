module Max_TrapFilter

export @call_max_height, max_trapezoid_height

function max_trapezoid_height(data::Vector{<:Real}, threshold::Real)
    max_heights = Float64[]
    i = 1
    while i <= length(data)
        if data[i] > threshold
            start = i
            while i <= length(data) && data[i] > threshold
                i += 1
            end
            push!(max_heights, maximum(data[start:i-1]))
        else
            i += 1
        end
    end
    return isempty(max_heights) ? nothing : max_heights
end



function max_trapezoid_height(data::Vector{<:AbstractVector{<:Real}}, threshold::Real)
    return [max_trapezoid_height(wf, threshold) for wf in data]
end



macro call_max_height(data_expr, threshold_expr)
    return :(Max_TrapFilter.max_trapezoid_height($(esc(data_expr)), $(esc(threshold_expr))))
end

end # module