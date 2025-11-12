# SamplerDome

A comprehensive benchmarking suite for continuous-time stochastic samplers (Gillespie algorithm variants).

## Overview

SamplerDome provides implementations of various sampling algorithms for continuous-time stochastic systems along with a benchmarking framework to compare their performance across different scenarios.

## Samplers Included

- **DirectCall**: Direct method with various data structure optimizations
  - Binary tree prefix search (with removal or keep strategies)
  - Cumulative sum prefix search (with removal or keep strategies)
- **FirstReaction**: Classic first reaction method for general distributions
- **FirstToFire**: Optimized approach using a priority queue
- **CombinedNextReaction**: Hybrid next reaction method supporting multiple distributions

## Installation

From the Julia REPL:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Quick Start

### Basic Usage

```julia
using SamplerDome
using Distributions
using Random

# Create a sampler
sampler = FirstToFire{Int,Float64}()
rng = MersenneTwister(42)

# Enable some clocks with exponential distributions
enable!(sampler, 1, Exponential(1.0), 0.0, 0.0, rng)
enable!(sampler, 2, Exponential(2.0), 0.0, 0.0, rng)
enable!(sampler, 3, Exponential(0.5), 0.0, 0.0, rng)

# Get the next event
tau, which = next(sampler, 0.0, rng)
println("Next event at time $tau for clock $which")
```

### Running Benchmarks

```julia
using SamplerDome

# Run the complete benchmark suite
include(joinpath(pkgdir(SamplerDome), "src", "run_all.jl"))
main()
```

The benchmark will:
- Test all samplers across various configurations
- Vary the number of enabled clocks (10, 100, 1,000, 10,000)
- Test different churn rates (1, 10, 100 changes per step)
- Try different distributions (exponential, gamma, Weibull)
- Test both dense and sparse key strategies
- Save results to `data/observations.csv`

## Package Structure

```
samplerdome/
├── Project.toml           # Package metadata and dependencies
├── README.md              # This file
└── src/
    ├── SamplerDome.jl     # Main module file
    ├── base_types.jl      # Core types and interfaces
    ├── direct.jl          # DirectCall sampler
    ├── firstreaction.jl   # FirstReaction sampler
    ├── firsttofire.jl     # FirstToFire sampler
    ├── combinednr.jl      # CombinedNextReaction sampler
    ├── conditions.jl      # Benchmark configuration
    ├── measure.jl         # Benchmarking utilities
    ├── run_all.jl         # Main benchmark script
    └── ...                # Data structures and utilities
```

## Testing

Run the basic test suite:

```bash
julia --project=. test_basic.jl
```

## Dependencies

- BenchmarkTools: Performance measurement
- CSV, DataFrames: Results output
- DataStructures: Priority queues and other structures
- Distributions: Statistical distributions
- Random: Random number generation

## License

See LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
