function combine_measurements(means::Vector{Float64}, errors::Vector{Float64})
    weights = 1.0 ./ (errors .^ 2)
    weighted_mean = sum(weights .* means) / sum(weights)
    combined_error = sqrt(1.0 / sum(weights))
    return (value = weighted_mean, error = combined_error)
end


means_80keV  = [78.84, 78.86, 78.84]     
errors_80keV = [0.03, 0.03, 0.03]

means_276keV  = [258.29, 258.21, 258.25]
errors_276keV = [0.04, 0.04, 0.04]

means_302keV  = [282.61, 282.607, 282.59]
errors_302keV = [0.03, 0.024, 0.03]

means_356keV  = [330.972, 330.929, 330.938]
errors_356keV = [0.013, 0.014, 0.015]

means_662keV  = [606.939, 606.925, 606.810, 606.774, 606.785, 606.814, 606.848, 606.838]
errors_662keV = [0.006, 0.007, 0.005, 0.006, 0.006, 0.006, 0.006, 0.006]


means = means_662keV
errors = errors_662keV

result = combine_measurements(means, errors)

println("Combined mean = $(round(result.value, digits=5)) ± $(round(result.error, digits=5))")