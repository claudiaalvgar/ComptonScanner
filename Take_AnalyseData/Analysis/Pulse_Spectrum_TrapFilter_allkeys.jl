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

include("Max_TrapFilter.jl")
using .Max_TrapFilter

n = parse(Int, ARGS[1])

#file = "/remote/ceph/user/a/alvarez/ComptonScanner/Ba_Data/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5"

pathCs = "/remote/ceph/user/a/alvarez/ComptonScanner/Cs_Data/raw_data/"
file1 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132022Z.lh5"
file2 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132558Z.lh5" 
file3 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T133133Z.lh5" 
file4 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T133709Z.lh5" 
file5 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T134245Z.lh5" 
file6 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T134820Z.lh5" 
file7 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T135356Z.lh5" 
file8 = pathCs*"R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T135932Z.lh5"

file = file1


if n == 1
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
choose_key = ["1"]


t = lh5open(file) do h
  Dict(key => h[key][:] for key in keys(h))
  #Dict(key => h[key][:] for key in choose_key)
end

num_keys = length(keys(t))

#Ba
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




#ADC SPECTRUM

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

range1 = 600
range2 = 615
# spectrum considering overlapped pulses
stephist(flat_max_adcs, bins = range1:0.1:range2, fmt = :png, label = "",xlabel = "ADC Counts", ylabel = "Counts", xlimits=(range1,range2))
#savefig("Cs_ADCSpectrum_av_$(av)_gap_$(gap)_threshold_$(threshold)_range0-700_file1_key1.png")

# spectrum considering just the max of 1 trapezoid (not overlapping)
#stephist(max_adc_notresolving, bins = 0:1000, fmt = :png, label = "",xlabel = "ADC Counts", ylabel = "Counts", xlimits=(0,700))
#savefig("Cs_ADCSpectrum_av_$(av)_gap_$(gap)_max_range0-700_file1_key1.png")



#FIT CALIBRATION

subsetpeak = flat_max_adcs[(flat_max_adcs .> range1) .& (flat_max_adcs .< range2)]

hist = fit(Histogram, flat_max_adcs, range1:0.1:range2)
xs = hist.edges[1][1:end-1]  # bin left edges
ys = hist.weights            # bin counts

# Gaussian function: p = [amplitude, mean, sigma]
gauss(x, p) = p[1] * exp.(-(x .- p[2]).^2 ./ (2 * p[3]^2))

# Initial guess: amplitude, mean, sigma
p0 = [maximum(ys), mean(subsetpeak), std(subsetpeak)]
println("Fit par before fit: $(p0)")

fith = curve_fit(gauss, xs, ys, p0)
p_fit = fith.param

n_entries = sum(hist.weights)
mean_fit = p0[2]
sigma_fit = p0[3]
mean_error = sigma_fit / sqrt(n_entries)
sigma_error = sigma_fit / sqrt(2 * n_entries)
println("Gauss errors: mean: $mean_fit +- $mean_error, sigma: $sigma_fit +- $sigma_error, entries: $n_entries")

# Covariance matrix
cov = estimate_covar(fith)
# Standard errors are the square roots of the diagonal
param_errors = sqrt.(diag(cov))
println("Fit errors: mean: $mean_fit +- $(param_errors[2]), sigma: $sigma_fit +- $(param_errors[3]), entries: $n_entries")

# Overlay fit
plot!(xs, gauss(xs, p_fit), label="Gaussian Fit", lw=2, color=:red, xlabel = "ADC Counts", ylabel = "Counts")
vline!([mean_fit], label="mean = $(round(mean_fit, digits=4)) ± $(round(param_errors[2], digits=4)) \nsigma = $(round(sigma_fit, digits=4)) ± $(round(param_errors[3], digits=4))")

savefig("CsADCSpectrum_av_$(av)_gap_$(gap)_file$(n).png")




#ENERGY SPECTRUM

#applying a threshold for the max, we can get 2 max per signal if overlapped pulses
#stephist(1.09 .* flat_max_adcs, bins = 0:1000, fmt = :png, label = "",xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(0,500), ylimits = (0,10000))

#plot with just maximum of the trapezoids (one per signal)
#stephist(1.09 .* max_adc_notresolving, bins = 0:1:1000, fmt = :png, label = "",xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(0,500), ylimits = (0,10000))

#vline!([31,81,276,302,356,383], label = "133Ba lines")
#vline!([31,81,276,302,356,383] .+ 31, label = "133Ba lines + 31 keV")
#vline!([31,81,276,302,356,383] .+ 81, label = "133Ba lines + 81 keV")

#savefig("BaSpectrum_av_$(av)_gap_$(gap)_maxvalue_range0-500.png")
#savefig("BaSpectrum_av_$(av)_gap_$(gap)_threshold_$(threshold)_range0-500.png")
