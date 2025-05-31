using LegendHDF5IO
using Statistics
using ProgressMeter
using Plots

using RadiationDetectorDSP
using LegendDSP

t = lh5open("ComptonScanner/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5") do h
    h["1"][:]
end

# lh5open("Claudia.lh5", "cw") do h
#     h["Data"] = t
# end

Ec = @showprogress map(p -> let pc = InvCRFilter(14000)(p .- 8546.0)
    mean(pc[1000:1200]) - mean(pc[1:200])
end, t.samples[findall(t.channel .== 1)]);

stephist(Ec, bins = 0:1:1200, fmt = :png, title = "133Ba spectrum", size = (600,400), xlabel = "Uncalibrated energy in ADC units", ylabel = "Counts / ADC unit", label = "")

tc = @showprogress map(p -> let pc = InvCRFilter(14000)(p .- 8546.0)
    pc .- mean(pc[1:200]) # mean(pc[1000:1200]) - mean(pc[1:200])
    end, t.samples[findall(t.channel .== 1)]);

plot(0:4:1200*4-4, t.samples[findall(t.channel .== 1)][1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Raw waveforms")
hline!([8546])

plot(0:4:1200*4-4, tc[1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Baseline- and decay-corrected waveforms")

flt_wvf = maximum.(TrapezoidalChargeFilter(20,150).(tc))

plot(TrapezoidalChargeFilter(20,150).(tc)[1:10])

stephist(1.09.*flt_wvf, bins = 0:1000, fmt = :png, label = "",xlabel = "Calibrated energies / keV", ylabel = "Counts / keV")
vline!([81,276,302,356,383], label = "133Ba lines")
vline!([81,276,302,356,383] .+ 31, label = "133Ba lines + 31 keV")
vline!([81,276,302,356,383] .+ 81, label = "133Ba lines + 81 keV")

s = lh5open("ComptonScanner/err_data/Salt_ComptonR_0.0mm_Z_-0.0mm_Phi_0.0deg_T_80.0K_measuretime_60sec-ICPC-20250522T130750Z.lh5") do h
    h["1"][:]
end

stephist(s.energy[findall(s.channel .== 1)])

sc = @showprogress map(p -> let pc = InvCRFilter(14000)(p .- 8546.0)
    pc .- mean(pc[1:200]) # mean(pc[1000:1200]) - mean(pc[1:200])
    end, s.samples[findall(s.channel .== 1)]);

Esc = @showprogress map(p -> let pc = InvCRFilter(14000)(p .- 8546.0)
    mean(pc[1000:1200]) - mean(pc[1:200])
end, s.samples[findall(s.channel .== 1)]);

stephist(Esc, bins = 0:5:2000, yscale = :log10, fmt = :png, title = "Salt spectrum", size = (600,400), xlabel = "Uncalibrated energy in ADC units", ylabel = "Counts / ADC unit", label = "")


# mean baseline
b = broadcast(p -> mean(p[1:250]), s.samples[findall(s.channel .== 1)])
stephist(b, bins = 8500:1:8600)
vline!([8546])

# mean decay constant
τ = broadcast(p -> LegendDSP.tailstats(p .- 8546.0, 900, 1200).τ, s.samples[findall(s.channel .== 1 .&& s.energy .> 1.5e6)])
stephist(τ, bins = 12000:100:16000)