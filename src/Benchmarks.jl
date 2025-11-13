module Benchmarks

# Dependencies
using Distributions
using Random
using DataStructures
using BenchmarkTools

export BenchmarkCondition, generate_conditions, is_compatible, construct_samplers
export setup_sampler, benchmark_step!, benchmark_config, sampler_name
export N_ENABLED, N_CHANGES, DISTRIBUTIONS, KEY_STRATEGIES

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
include("rssa.jl")

# Benchmarking framework
include("conditions.jl")
include("measure.jl")

end # module
