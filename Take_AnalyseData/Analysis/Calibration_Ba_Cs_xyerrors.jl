using LinearAlgebra
using Plots

function odr_linear_fit(x, y, σx, σy; maxiter=10, tol=1e-6)
    # Initial guess: ordinary weighted least squares ignoring σx
    w = 1 ./ (σy.^2)
    β = ( [x ones(length(x))]' * Diagonal(w) * [x ones(length(x))] ) \ ([x ones(length(x))]' * Diagonal(w) * y)

    a, b = β[1], β[2]

    for iter in 1:maxiter
        # Calculate weights considering both σx and σy
        weights = 1 ./ (σy.^2 + (a^2) .* σx.^2)

        # Weighted least squares with updated weights
        W = Diagonal(weights)
        X = [x ones(length(x))]
        β_new = (X' * W * X) \ (X' * W * y)

        # Check convergence
        if norm(β_new - β) < tol
            break
        end
        β = β_new
        a, b = β[1], β[2]
    end

    return a, b
end

# Your data
adc = [78.85, 258.25, 282.60, 330.95, 606.8372]
energy = [80.9979, 276.3992, 302.8512, 356.0134, 661.659]
adc_err = [0.017, 0.023, 1.19, 7.13, 0.003]
energy_err = [0.0011, 0.0021, 0.0016, 0.0017, 0.0021]

leftmargin = 5mm

# Fit
a, b = odr_linear_fit(adc, energy, adc_err, energy_err)
println("Slope: $a")
println("Intercept: $b")
model(x) = a * x + b

# Chi-squared calculation (weighted by total uncertainty)
weights = 1 ./ (energy_err.^2 + (a^2) .* adc_err.^2)
predicted = model.(adc)
residuals = energy .- predicted
χ² = sum(weights .* residuals.^2)
ndf = length(adc) - 2
χ²_ndf = χ² / ndf
println("Chi-squared (χ²): $χ²")
println("χ²/ndf: $χ²_ndf")

# Fit line for plotting
x_fit = range(minimum(adc), stop=maximum(adc), length=200)
y_fit = model.(x_fit)

# Layout: main plot + residuals
layout = @layout [a{0.7h}; b{0.3h}]
plt = plot(layout=layout, size=(800, 600))

# Top plot: data and fit
scatter!(plt[1], adc, energy; xerror=adc_err, yerror=energy_err,
         label="Data", ms=6, left_margin=leftmargin, marker = (:circle, 5))
plot!(plt[1], x_fit, y_fit, lw=2, color=:red,
      label="Fit: E = $(round(a, digits=2))×ADC $(round(b, digits=2))")
ylabel!(plt[1], "Energy [keV]")
title!(plt[1], "Orthogonal Distance Regression Fit\nχ²/ndf = $(round(χ²_ndf, digits=2))")
xlabel!(plt[1], "")

# Bottom plot: residuals
scatter!(plt[2], adc, residuals; yerror=energy_err, xerror=adc_err,
         ms=5, color=:black, label="", left_margin=leftmargin)
#hline!(plt[2], [0.0], color=:red, lw=1, label="")
xlabel!(plt[2], "ADC Counts")
ylabel!(plt[2], "Residuals [keV]")

# Save and display
savefig("calibration_with_odr_residuals.png")
display(plt)