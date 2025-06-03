using LegendHDF5IO
using Statistics
using ProgressMeter
using Plots
using StatsBase
using LsqFit

using RadiationDetectorDSP
using LegendDSP

file = "/remote/ceph/user/a/alvarez/ComptonScanner/Ba_Data/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5"

key = "1"

t = lh5open(file) do h
    h[key][:]
end

dt = 4 #ns

# Correct exponential shape, not accounting for pileup of different events
# mean baseline

b = broadcast(p -> mean(p[1:25]), t.samples[findall(t.channel .== 1)])
#stephist(b, bins = 8000:1:15000)
#vline!([11000])

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

# mean decay constant

#τ = broadcast(p -> LegendDSP.tailstats(p .- mean_fit, 900, 1200).τ, t.samples[findall(t.channel .== 1 .&& t.energy .> 1.5e6)])
lengths = [length(s) for s in t.samples]

τ = broadcast(p -> LegendDSP.tailstats(p .- truebaseline_previousdata, 900, 1200).τ, t.samples[findall(t.channel .== 1 .&& lengths .> 1000)])

#stephist(τ, bins = 12000:100:20000, xlabel = "τ [ADC]")
stephist(τ*dt, bins = 40000:400:80000, xlabel = "τ [ns]")
vline!([59000], label="mean = 59000 ns")

