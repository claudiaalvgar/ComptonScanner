using LinearAlgebra
using Plots

function weighted_linear_fit(x, y, w)
    # w = weights (usually 1/σ_y²)
    W = Diagonal(w)
    X = [x ones(length(x))]
    β = (X' * W * X) \ (X' * W * y)  # weighted least squares solution
    return β  # β[1] = slope, β[2] = intercept
end

adc = [78.85, 258.25, 282.60, 330.95, 606.8372]
energy = [80.9979, 276.3992, 302.8512, 356.0134, 661.659]
energy_err = [0.0011, 0.0021, 0.0016, 0.0017, 0.0021]

weights = 1 ./ (energy_err .^ 2)

params = weighted_linear_fit(adc, energy, weights)
println("Slope: ", params[1])
println("Intercept: ", params[2])

# Plot result
using Plots
model(x) = params[1] * x + params[2]
x_fit = range(minimum(adc), stop=maximum(adc), length=200)
y_fit = model.(x_fit)

scatter(adc, energy; yerror=energy_err, label="Data", ms=6)
plot!(x_fit, y_fit, lw=2, color=:red, label="Weighted Fit")
xlabel!("ADC")
ylabel!("Energy [keV]")
title!("Weighted Linear Fit")
savefig("calibration_preliminary.png")