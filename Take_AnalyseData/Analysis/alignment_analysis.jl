using LsqFit
using Plots

fn0 = filter(f -> occursin("_150.0deg", f), readdir())

hor_motor_pos = map(fn -> parse(Float64, split(fn, "_")[2][1:end-2]), fn0)
fs = filesize.(fn0)

@. model(x, p) = p[1] * (erf(p[2]*(x - p[3])) + 1)/2 + p[4]
fit_result = LsqFit.curve_fit(model, hor_motor_pos, fs, Float64[2.5e8, 1.0, 50.0, 8e7])

@info "Fit parameters: $(fit_result.param)"

scatter(hor_motor_pos, fs)
plot!(43:0.1:55, x -> model(x, fit_result.param))
