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

# Fit
a, b = odr_linear_fit(adc, energy, adc_err, energy_err)
println("Slope: $a")
println("Intercept: $b")

# Plot results
model(x) = a*x + b
x_fit = range(minimum(adc), stop=maximum(adc), length=200)
y_fit = model.(x_fit)

scatter(adc, energy; xerror=adc_err, yerror=energy_err, label="Data", ms=6)
plot!(x_fit, y_fit, lw=2, color=:red, label="ODR Fit")
xlabel!("ADC")
ylabel!("Energy [keV]")
title!("Orthogonal Distance Regression Fit")