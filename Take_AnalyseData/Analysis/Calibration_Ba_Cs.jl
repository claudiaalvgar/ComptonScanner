using LinearAlgebra
using Plots
using Plots.PlotMeasures

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

leftmargin = 5mm

weights = 1 ./ (energy_err .^ 2)

params = weighted_linear_fit(adc, energy, weights)
model(x) = params[1] * x + params[2]
println("Slope: ", params[1])
println("Intercept: ", params[2])

# Chi-squared calculation
predicted = model.(adc)
residuals = energy .- predicted
χ² = sum((residuals ./ energy_err).^2)
println("Chi-squared (χ²): ", χ²)
ndf = length(energy) - 2
χ²_ndf = χ² / ndf

# Fit line
x_fit = range(minimum(adc), stop=maximum(adc), length=200)
y_fit = model.(x_fit)

# Layout with residuals subplot
layout = @layout [a{0.7h}; b{0.3h}]
plt = plot(layout = layout, size=(800,600))

# Top plot: data with fit
scatter!(plt[1], adc, energy; yerror=energy_err, label="Data", ms=6, marker = (:cross, 8), left_margin=leftmargin)
plot!(plt[1], x_fit, y_fit, lw=2, color=:red,
      label="Fit: E = $(round(params[1], digits=2))×ADC $(round(params[2], digits=2))")
xlabel!(plt[1], " ")
ylabel!(plt[1], "Energy [keV]")
title!(plt[1], "Weighted Linear Fit\nχ²/ndf = $(round(χ²_ndf, digits=2))")

# Bottom plot: residuals
scatter!(plt[2], adc, residuals; yerror=energy_err, ms=5, label="", color=:black, left_margin=leftmargin)
#hline!(plt[2], [0.0], color=:red, lw=1, label="")
xlabel!(plt[2], "ADC Counts")
ylabel!(plt[2], "Residuals (ΔE) [keV]")

# Save or display
savefig("calibration_yerros_with_residuals.png")
display(plt)