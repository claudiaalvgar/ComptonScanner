using LegendHDF5IO
using Statistics
using ProgressMeter
using Plots
using StatsBase
using LsqFit

using RadiationDetectorDSP
using LegendDSP

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

file = file8

#This step in terminal shows the keys

t = lh5open(file) do h
  Dict(key => h[key][:] for key in keys(h))
end

num_keys = length(keys(t))

samples_per_key = Dict(key => t[key].samples[findall(t[key].channel .== 1)] for key in keys(t))

num_wfrm_key = []

#num of waveforms per key
for i in keys(t)
 num_wfrm = length(samples_per_key[i])
 local key = i
 push!(num_wfrm_key, (key, num_wfrm))
end


for i in 1:num_keys
    println("num of waveforms per key ($(num_wfrm_key[i][1])) : $(num_wfrm_key[i][2])")
end

dt = 4 #ns


# Correct exponential shape
# mean baseline

#for 1 key
#b = broadcast(p -> mean(p[1:500]), t["1"].samples[findall(t["1"].channel .== 1)])

#for all keys
b = Dict(k => broadcast(p -> mean(p[1:500]), t[k].samples[findall(t[k].channel .== 1)]) for k in keys(t))
#println(values(b))
baselines = collect(Iterators.flatten(values(b)))
stephist(baselines, bins = 8500:1:8700, label = "data", xlabel = "ADC Counts")
mean_b = mean(x for x in baselines if x < 8555)
vline!([mean_b], label="baseline = $(round(mean_b, digits=2))")


#savefig("Average500ADCvalues_perpeak_file8.png")

#=
# Fit baseline
hist = fit(Histogram, b, 8000:1:15000)
xs = hist.edges[1][1:end-1]  # bin left edges
ys = hist.weights            # bin counts

# Gaussian function: p = [amplitude, mean, sigma]
gauss(x, p) = p[1] * exp.(-(x .- p[2]).^2 ./ (2 * p[3]^2))

# Initial guess: amplitude, mean, sigma
p0 = [maximum(ys), mean(b), std(b)]

fith = curve_fit(gauss, xs, ys, p0)
p_fit = fith.param

# Step histogram
stephist(b, bins=8000:1:15000, label="Data", normalize=false, xlabel = "ADC Counts")

n_entries = sum(hist.weights)
mean_fit = p0[2]
println("mean: $mean_fit, entries: $n_entries")

# Overlay fit
plot!(xs, gauss(xs, p_fit), label="Gaussian Fit", lw=2, color=:red)
vline!([mean_fit], label="mean = $(round(mean_fit, digits=2))")
=#


# mean decay constant
mean_fit = 8546
#τ = broadcast(p -> LegendDSP.tailstats(p .- mean_fit, 900, 1200).τ, t["1"].samples[findall(t["1"].channel .== 1 .&& t["1"].energy .> 1.5e6)])
#τ = broadcast(p -> LegendDSP.tailstats(p .- mean_fit, 900, 1200).τ, t["1"].samples[findall(t["1"].channel .== 1)])
#lengths = [length(s) for s in t.samples]


τ = Dict(k => broadcast(p -> LegendDSP.tailstats(p .- mean_b, 900, 1200).τ, t[k].samples[findall(t[k].channel .== 1)]) for k in keys(t))
τ_array = collect(Iterators.flatten(values(τ)))
mean_τ = mean(x for x in τ_array if x > 5000 && x < 20000)

#stephist(τ_array, bins = 5000:100:20000, xlabel = "τ [ADC]")
stephist(τ_array*dt, bins = 20000:400:100000, xlabel = "τ [ns]", label = false)
vline!([mean_τ*dt], label="mean = $(round(mean_τ*dt, digits=2)) ns")


savefig("TauValue_Cs_file8.png")