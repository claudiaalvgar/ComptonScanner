include("CalibPlot.jl")
using .CalibPlot

adc = [78.85, 258.25, 282.60, 330.95, 606.8372]
energy = [80.9979, 276.3992, 302.8512, 356.0134, 661.659]
adc_err = [0.017, 0.023, 1.19, 7.13, 0.003]
energy_err = [0.0011, 0.0021, 0.0016, 0.0017, 0.0021]





CalibPlot.calibplot(adc, energy; xerr=adc_err, yerr=energy_err)