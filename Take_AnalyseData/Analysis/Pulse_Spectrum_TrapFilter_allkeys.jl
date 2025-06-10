using Pkg
Pkg.activate(".")

using LegendHDF5IO
using Statistics
using ProgressMeter
using Plots
using StatsBase
using LsqFit
using Revise
using RadiationDetectorDSP
using LegendDSP
using LinearAlgebra
using LaTeXStrings

include("Max_TrapFilter.jl")
using .Max_TrapFilter

n = parse(Int, ARGS[1])

#Comment to run Cs data
file0 = "/remote/ceph/user/a/alvarez/ComptonScanner/Ba_Data/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5"

pathCs = "/remote/ceph/user/a/alvarez/ComptonScanner/Cs_Data/raw_data/"
file1 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132022Z.lh5"
file2 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132558Z.lh5" 
file3 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T133133Z.lh5" 
file4 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T133709Z.lh5" 
file5 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T134245Z.lh5" 
file6 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T134820Z.lh5" 
file7 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T135356Z.lh5" 
file8 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T135932Z.lh5"

#Comment to run Ba data
file = file1

if n == 0
    file = file0
elseif n == 1
    file = file1
elseif n == 2
    file = file2
elseif n == 3
    file = file3
elseif n == 4
    file = file4
elseif n == 5
    file = file5
elseif n == 6
    file = file6
elseif n == 7
    file = file7
else
    file = file8
end


#This step in terminal shows the keys
#choose_key = ["1","2","3"]
#choose_key = ["4","5","6"]
#choose_key = ["7","8","9"]

t = lh5open(file) do h
  Dict(key => h[key][:] for key in keys(h))
  #Dict(key => h[key][:] for key in choose_key)
end

num_keys = length(keys(t))

#Provisional
#truebaseline = 8546.0
#tau = 59000

#Cs
truebaseline = 8542.0
tau = 56000

dt = 4 #ns
tau_alg = tau / dt

av = 20
gap = 300


#Corrected waveforms (step pulse)

tc = Dict(
    key => @showprogress map(p -> begin
        pc = InvCRFilter(tau_alg)(p .- truebaseline)
        pc .- mean(pc[1:200])
    end, t[key].samples[findall(t[key].channel .== 1)])
    for key in keys(t)
)

corrected_waveforms = collect(Iterators.flatten(values(tc)))

plot(0:4:1200*4-4, corrected_waveforms[1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Baseline- and decay-corrected waveforms")




#ADC SPECTRUM********************************

threshold = 20

filtered_Trapezoids = TrapezoidalChargeFilter(av, gap).(corrected_waveforms)

#Returning just the max of the trapezoid (not accounting for overlapping pulses, doube trapezoids)

max_adc_notresolving = maximum.(filtered_Trapezoids)
println("Trapezoids just one max: $(max_adc_notresolving[1:11])")


# This returns a vector of vectors (one peak can have 2 max if overlapped)

Max_wfrm = Max_TrapFilter.@call_max_height(filtered_Trapezoids, threshold)
filtered_results = filter(x -> x !== nothing, Max_wfrm)
println("My trapezoids max: $(Max_wfrm[1:11])")

flat_max_adcs = collect(Iterators.flatten(filtered_results))

#range1 = 600
#range2 = 615

#range1 = 250
#range2 = 400

#range1 = 325
#range2 = 340

range1 = 655
range2 = 670

range1fit = 658
range2fit = 663


# spectrum considering overlapped pulses
stephist(flat_max_adcs, bins = range1:0.1:range2, fmt = :png, label = "",xlabel = "ADC Counts", ylabel = "Counts", xlimits=(range1,range2))
#savefig("Cs_ADCSpectrum_av_$(av)_gap_$(gap)_threshold_$(threshold)_range$(range1)-$(range2)_file1_key1.png")
#savefig("Ba_ADCSpectrum_av_$(av)_gap_$(gap)_threshold_$(threshold)_range$(range1)-$(range2)_file0_key1ke2key3_zoom.png")

# spectrum considering just the max of 1 trapezoid (not overlapping)
#stephist(max_adc_notresolving, bins = 0:1000, fmt = :png, label = "",xlabel = "ADC Counts", ylabel = "Counts", xlimits=(0,700))




#ENERGY SPECTRUM********************************

Energy_calib = (1.10078168941052 .* flat_max_adcs) .-6.348613639903226

#applying a threshold for the max, we can get 2 max per signal if overlapped pulses
stephist(Energy_calib, bins = 0:0.1:1000, fmt = :png,xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(range1,range2), ylimits = (0,10000), label="Calibrated data")

#plot with just maximum of the trapezoids (one per signal)
#stephist(1.09 .* max_adc_notresolving, bins = 0:1:1000, fmt = :png, label = "",xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(0,500), ylimits = (0,10000))

# Ba lines
#vline!([30.97, 80.9979, 276.3992, 302.8512, 356.0134,383.8491], label=L"\textbf{^{133}\mathrm{\textbf{Ba}}\ \mathrm{\textbf{lines}}}")
#vline!([30.97, 80.9979, 276.3992, 302.8512, 356.0134,383.8491] .+ 30.97, label=L"\textbf{^{133}\mathrm{\textbf{Ba}}\ \mathrm{\textbf{lines + 31 keV}}}")
#vline!([30.97, 80.9979, 276.3992, 302.8512, 356.0134,383.8491] .+ 80.9979, label=L"\textbf{^{133}\mathrm{\textbf{Ba}}\ \mathrm{\textbf{lines + 81 keV}}}")

#Cs line
Etrue_Cs = 661.659
#vline!([Etrue_Cs], label=L"\textbf{^{137}\mathrm{\textbf{Cs}}\ \mathrm{\textbf{line}}}")


#savefig("BaSpectrum_av_$(av)_gap_$(gap)_maxvalue_range0-500.png")
#savefig("BaSpectrumE_av_$(av)_gap_$(gap)_threshold_$(threshold)_range0-500_Cstaubaseline_key1key2key3_1.10calib-6.35_BaLines.png")
#savefig("CsSpectrumE_av_$(av)_gap_$(gap)_threshold_$(threshold)_range640-685_Cstaubaseline_file1_1.10calib-6.35_CsLine.pdf")
#savefig("CsSpectrumE_av_$(av)_gap_$(gap)_threshold_$(threshold)_range640-685_Cstaubaseline_file1_1.10calib-6.35_CsLine.png")



#FIT CALIBRATION********************************

#Fit ADCs
#=
subsetpeak = flat_max_adcs[(flat_max_adcs .> range1) .& (flat_max_adcs .< range2)]
hist = fit(Histogram, flat_max_adcs, range1fit:0.1:range2fit)
xs = hist.edges[1][1:end-1]  # bin left edges
ys = hist.weights            # bin counts
# Initial guess: amplitude, mean, sigma
p0 = [maximum(ys), mean(subsetpeak), std(subsetpeak)]
=#

#Fit Energy
hist = fit(Histogram, Energy_calib, range1fit:0.1:range2fit)
xs = hist.edges[1][1:end-1]  # bin left edges
ys = hist.weights            # bin counts
# Initial guess: amplitude, mean, sigma
p0 = [maximum(ys), mean(Energy_calib), std(Energy_calib)]


println("Fit par before fit: $(p0)")


xplot = range(range1, range2; length=1000)  # Full plot range

# Gaussian function: p = [amplitude, mean, sigma]
gauss(x, p) = p[1] * exp.(-(x .- p[2]).^2 ./ (2 * p[3]^2))


fith = curve_fit(gauss, xs, ys, p0)
p_fit = fith.param

n_entries = sum(hist.weights)
mean_fit = p_fit[2]
sigma_fit = p_fit[3]
mean_error = sigma_fit / sqrt(n_entries)
sigma_error = sigma_fit / sqrt(2 * n_entries)
println("Gauss errors: mean: $mean_fit +- $mean_error, sigma: $sigma_fit +- $sigma_error, entries: $n_entries")

#Chi2
# Compute fitted values at bin positions
y_fit = gauss(xs, p_fit)

# Assume Poisson statistics for histogram: error = sqrt(count)
errors = sqrt.(ys)

# To avoid division by zero (in empty bins), use only bins with counts > 0
valid = ys .> 0

# Chi-squared calculation
chi2 = sum(((ys[valid] .- y_fit[valid]) ./ errors[valid]) .^ 2)

# Degrees of freedom: number of valid data points minus number of fit parameters
dof = count(valid) - length(p_fit)

# Reduced chi-squared
chi2_reduced = chi2 / dof

println("Chi² = $chi2")
println("Degrees of freedom = $dof")
println("Reduced Chi² = $chi2_reduced")

# Covariance matrix
cov = estimate_covar(fith)
# Standard errors are the square roots of the diagonal
param_errors = sqrt.(diag(cov))
println("Fit errors: mean: $mean_fit +- $(param_errors[2]), sigma: $sigma_fit +- $(param_errors[3]), entries: $n_entries")

#Relative error Cs

relE = abs(((mean_fit - Etrue_Cs)/Etrue_Cs )*100)

# Overlay fit
plot!(xplot, gauss(xplot, p_fit), label="Gaussian Fit: \nmean = $(round(mean_fit, digits=3)) ± $(round(param_errors[2], digits=3)) \nσ = $(round(sigma_fit, digits=3)) ± $(round(param_errors[3], digits=3)) \nχ² / ndf = $(round(chi2_reduced, digits=2)) \n∆E = $(round(relE, digits=3)) %", lw=2, color=:red, xlabel = "Energy [keV]", ylabel = "Counts")
#vline!([mean_fit], label="mean = $(round(mean_fit, digits=3)) ± $(round(param_errors[2], digits=3))")


#savefig("BaADCSpectrum_276keV_av_$(av)_gap_$(gap)_file$(n)_key1key2.png")
savefig("Cs_ESpectrum_av_$(av)_gap_$(gap)_file$(n)_allkeys_fit_zoom.png")
savefig("Cs_ESpectrum_av_$(av)_gap_$(gap)_file$(n)_allkeys_fit_zoom.pdf")
