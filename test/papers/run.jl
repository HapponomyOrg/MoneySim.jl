# Entry point for the paper regression + before/after suite.
#
# Usage:
#   PAPER_TESTS=write julia --project=. test/papers/run.jl
#   PAPER_TESTS=fast  julia --project=. test/papers/run.jl
#   PAPER_TESTS=full  julia --project=. test/papers/run.jl
#
# `write` captures the legacy baseline into `fixtures/baseline.toml`.
# `fast` runs the legacy paper checks plus the core-vs-baseline comparison.
# `full` additionally runs all legacy paper-2 equilibria.
#
# The baseline captures paper 3 at `PAPER3_BASELINE_ACTORS` ×
# `PAPER3_BASELINE_YEARS` (defaults 1000 × 10). Set
# `PAPER3_BASELINE_ACTORS=10000 PAPER3_BASELINE_YEARS=100` for a paper-scale
# nightly capture; the core comparison reads the scale back from the baseline.

using Test

const PAPER_TESTS = get(ENV, "PAPER_TESTS", "fast")

@info "Paper regression suite" mode = PAPER_TESTS

include("scenarios.jl")
include("adapter.jl")

if PAPER_TESTS == "write"
    include("capture_baseline.jl")
    capture_baseline()
elseif PAPER_TESTS == "seeds"
    include("seeds.jl")
else
    include("paper1.jl")
    include("paper2.jl")
    include("paper3.jl")
    include("compare.jl")

    if parse(Int, get(ENV, "PAPER_SEEDS", "0")) >= 2
        include("seeds.jl")
    end
end
