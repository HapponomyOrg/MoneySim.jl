using Plots
using LsqFit
using LaTeXStrings

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
