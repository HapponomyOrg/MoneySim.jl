using Plots
using LsqFit
using LaTeXStrings

# The new way

# Monetary mass, Profit retention, Debt, Lending rate, debt Ratio:
M = 1; P = 2; D = 3; L = 4; R = 5

T₀_default = [100.0, 10.0, 110.0]

function init_series(T::Int64, T₀::Array{Float64,1} = T₀_default)
  series = Array{Float64,2}(undef,T,5)
  start = Array{Float64,1}(undef, 5)
  start[M:D] = T₀
  start[L] = 0 # lending rate TODO: this is not the best possible value
  start[R] = T₀[D]/T₀[M] # debt ratio
  series[1,:] = start
  return series
end

function run_series(S::Array{Float64,2}, g::Float64, f::Float64)
  for t = 2:size(S)[1]
    prev = view(S, t - 1, M:D) # the previous values
    current = Array{Float64,1}(undef, 5)
    current[M] = prev[M]*(1 + g)
    current[P] = prev[P] + prev[D]*g*f
    current[D] = current[M] + current[P]
    current[L] = (current[D] - prev[D])/current[M]
    current[R] = current[D]/current[M]
    S[t,:] = current
  end
end

@. model(t, p) = p[1]*(1+p[2])^(t-1)

function run(T,g,f,M0)::Array{Float64,2}
  T0 = [ M0, M0*f/(1-f), M0/(1-f) ]
  println("Starting with: $T0")
  series = init_series(T,T0)
  run_series(series,g,f)
  return series
end

function plot_sim(T::Int64, g::Float64, f::Float64, M0 = 100.0)
  result = run(T,g,f,M0)
  gr = round(g*100)
  fr = round(f*100)
  pc(x) = "$(trunc(Int,x*100))%"
  # latexstring("Monetary mass - growth rate $(gr)% - fraction $(fr)%"))
  plot1 = plot(view(result,:,M:D),labels = ["Monetary mass" "Hoard" "Debt"], title = "Growth $(pc(g)), fraction $(pc(f))")
  fD(t) = M0*((1+g)^(t-1))/(1-f)
  fP(t) = M0*((1+g)^(t-1))*f/(1-f)
  plot!(plot1, 1:T, fD, label = "fD")
  plot!(plot1, 1:T, fP, label = "fP")
  #= 
  plot!(plot1, 1:T, model(1:T, [T₀_default[M],g]), label = "Monetary mass (function)")
  @. model_P(t, p) = T₀_default[P]*(1+p[1])^(t-1)
  fit_P = curve_fit(model_P, 1:T, result[:,P], [g/f])
  println("P coeff: $(round.(coef(fit_P),digits=4))")
  println("P stderror: $(stderror(fit_P)))")
  plot!(plot1, 1:T, model_P(1:T, coef(fit_P)), label = "Hoard (function)")
  fit_D = curve_fit(model, 1:T, view(result,:,D), [T₀_default[D], g/f])
  println("D coeff: $(round.(coef(fit_D),digits=4))")
  =#
  # savefig("pdf/monetary_mass_$(gr)_$(fr).pdf")
  println("M: $(result[T,M]) - P: $(result[T,P]) - D: $(result[T,D])")
  #lending = view(L, 2:T)
  return plot1
end

# plot_growth(f) = plot_sim(100,0.04,f)

# for f = 0.1:0.1:0.9
#   pl = plot_growth(f)
#   display(pl)
# end
# savefig("overview.pdf")

# The old way
#=
function simulate(f = 0.5)
  simulate(1000000.0, 1200, 0.04, f)
end

function simulate(M1::Float64, T::Int64, g::Float64, f::Float64)
  # Monetary mass (timeseries)
  M = Array{Float64}(undef, T)
  M[1] = M1
  # Debt (timeseries)
  D = Array{Float64}(undef, T)
  D[1] = M1
  # Hoard (timeseries)
  H = Array{Float64}(undef, T)
  H[1] = 0
  # Required lending ratio
  L = Array{Float64}(undef, T)
  L[1] = 0.04
  # Debt ratio
  DR = Array{Float64}(undef, T)
  DR[1] = 1

  # Main loop
  for t = 2:T
    M[t] = M[t - 1]*(1 + g)
    H[t] = H[t - 1] + D[t - 1]*g*f
    D[t] = M[t] + H[t]
    L[t] = (D[t] - D[t - 1])/M[t]
    DR[t] = D[t]/M[t]
  end
  # data = [M, H, D]
  # plot(data, labels = ["Monetary mass" "Hoard" "Debt"])
  # savefig("monetary_mass_$f.png")
  @. exponential_model(x, p) = p[1] + p[2]*p[3]^x
  @. linear_model(x,p) = p[1] + p[2]*x
  @. asymptotic_model(x,p) = p[1] - p[2]/p[3]^x
  if f < 1
    model = asymptotic_model
    param =  [0.0, 1.0, 1.0]
  elseif f == 1.0
    model = linear_model
    param =  [0.0, 1.0]
  else
    model = exponential_model
    param =  [0.0, 1.0, 1.0]
  end
  lending = view(L, 2:T)
  fit = curve_fit(model, 2:T, lending, param)
  # println(stderror(fit))
  fitted = model(2:T, coef(fit))
  ps = round.(coef(fit),digits = 6)
  if f < 1
    fit_label = latexstring("$(ps[1]) - $(ps[2])/$(ps[3])^x")
  elseif f == 1.0
    fit_label = latexstring("$(ps[1]) + $(ps[2])*x")
  else
    fit_label = latexstring("$(ps[1]) + $(ps[2])*$(ps[3])^x")
  end
  plot([lending, fitted], label = ["Lending ratio" fit_label], title = "Profit retention ratio $f")
  savefig("plots/lending_ratio_$f.svg")
  # plot(view(DR, 2:T), label = "Debt ratio", title = "Profit retention ratio $f")
  # savefig("debt_ratio_$f.png")
end

for f = 0.1:0.1:1.9
  simulate(f)
end
=#
