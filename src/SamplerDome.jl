"""
SamplerDome - Benchmarking suite for continuous-time stochastic samplers

This package provides implementations of various sampling algorithms for continuous-time
stochastic systems (e.g., Gillespie algorithm variants) along with a comprehensive
benchmarking framework to compare their performance.

# Samplers Included
- DirectCall: Direct method with various data structures
- FirstReaction: Classic first reaction method
- FirstToFire: Optimized next reaction method
- CombinedNextReaction: Hybrid approach combining multiple strategies
- PSSACR: Composition-rejection sampling over groups (exponential distributions only)

# Usage
```julia
using SamplerDome

# Run benchmarks
include(joinpath(pkgdir(SamplerDome), "src", "run_all.jl"))
main()
```
"""
module SamplerDome

# Core dependencies
using Distributions
using Random
using DataStructures
using BenchmarkTools
using CSV
using DataFrames
using Logging

# Export base types and interfaces
export SSA, EnabledWatcher, ContinuousTime
export enable!, disable!, fire!, reset!, next, enabled, isenabled, clone

# Include base types first
include("base_types.jl")

# Utility structures
include("setofsets.jl")
include("lefttrunc.jl")

# Data structures for samplers
include("binarytreeprefixsearch.jl")
include("cumsumprefixsearch.jl")
include("keyedprefixsearch.jl")

# Sampler implementations
include("direct.jl")
include("firstreaction.jl")
include("firsttofire.jl")
include("combinednr.jl")
include("pssa_cr.jl")

# Benchmarking framework
include("conditions.jl")
include("measure.jl")

# Export samplers
export DirectCall, DirectCallExplicit
export FirstReaction, ChatReaction
export FirstToFire
export CombinedNextReaction
export PSSACR

# Export benchmarking utilities
export BenchmarkCondition, generate_conditions, construct_samplers
export is_compatible, setup_sampler, benchmark_step!, benchmark_config
export sampler_name

# Export configuration constants
export N_ENABLED, N_CHANGES, DISTRIBUTIONS, KEY_STRATEGIES

end # module SamplerDome
