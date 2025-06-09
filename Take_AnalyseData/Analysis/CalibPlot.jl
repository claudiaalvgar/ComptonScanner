module CalibPlot

using Plots, LsqFit, Statistics

function calibplot(adc, energy; xerr=nothing, yerr=nothing,
                   xlabel="ADC", ylabel="Energy [keV]",
                   title="ADC → Energy calibration")

    adc_vec     = adc
    energy_vec  = energy
    Nx = length(adc_vec)
    @assert length(energy_vec) == Nx "adc and energy must be same length"

    xerr_vec = xerr === nothing ? zeros(Nx) : xerr
    yerr_vec = yerr === nothing ? zeros(Nx) : yerr
    @assert length(xerr_vec)==Nx && length(yerr_vec)==Nx "error vectors wrong length"

   model(x, p) = @. p[1]*x + p[2]

# Replace zeros in yerr_vec with 1.0 to avoid divide-by-zero
σy = map(e -> e == 0 ? 1.0 : e, yerr_vec)

# 3. Manually scale x and y by the weights
adc_scaled    = adc_vec    ./ σy
energy_scaled = energy_vec ./ σy

# 4. Fit using the scaled model (no weights argument!)
fit = curve_fit(model, adc_scaled, energy_scaled, [1.0, 0.0])
p = fit.param

# To plot, use original model on unscaled x
x_plot = range(minimum(adc_vec), maximum(adc_vec), length=200)
y_plot = model(x_plot, p)  # This is OK because the model was linear

    layout = @layout([a{0.72h}; b{0.28h}])
    plt = plot(layout = layout, legend = :topleft, title = title)

    scatter!(plt[1], adc_vec, energy_vec;
             xerror = xerr_vec, yerror = yerr_vec,
             label = "data", ms = 6)
    plot!(plt[1], x_plot, y_plot; color = :red, lw = 2,
          label = "fit: E = $(round(p[1],digits=4))*ADC + $(round(p[2],digits=2))")
    xlabel!(plt[1], xlabel)
    ylabel!(plt[1], ylabel)

    resid = energy_vec .- model(adc_vec, p)
    scatter!(plt[2], adc_vec, resid;
             xerror = xerr_vec, yerror = yerr_vec,
             label = "", color = :black, ms = 5)
    hline!(plt[2], [0]; color = :red, lw = 1, label = "")
    xlabel!(plt[2], xlabel)
    ylabel!(plt[2], "Residuals")

    display(plt)
    return plt
end

end # module