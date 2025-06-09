include("CalibPlot.jl")
using .CalibPlot  # or CalibPlot if you did `import` or `using` the package

adc = [100, 200, 300, 400]
energy = [150, 250, 350, 450]
adc_err = [5, 5, 5, 5]
energy_err = [12, 2, 2, 2]





CalibPlot.calibplot(adc, energy; xerr=adc_err, yerr=energy_err)