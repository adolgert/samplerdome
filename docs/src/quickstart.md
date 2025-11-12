# SamplerDome Quickstart Guide

## Overview

SamplerDome is a benchmarking framework for continuous-time stochastic process samplers (Gillespie algorithm variants). This guide will help you quickly get started with running benchmarks.

## Initial Setup

Before running any benchmarks, set up the project dependencies:

```bash
cd /Users/adolgert/dev/samplerdome
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Running Benchmarks

There are several ways to run benchmarks, depending on your needs:

### Method 1: Full Benchmark Suite (Comprehensive)

Run all samplers against all benchmark conditions:

```bash
julia --project=. -e 'include("src/run_all.jl"); main()'
```

**What it does:**
- Tests 7 sampler variants
- Runs up to 72 benchmark conditions (filtered for compatibility)
- Takes 100 samples per configuration using BenchmarkTools
- Saves detailed results to `data/observations.csv`
- Prints real-time progress with timing information

**When to use:** For comprehensive performance analysis and comparison across all samplers.

**Expected runtime:** 10-30 minutes depending on your machine.

### Method 2: Minimal Benchmark (Quick Testing)

Run a smaller benchmark suite for quick validation:

```bash
julia --project=. -e 'include("src/minimal_benchmark.jl"); main()'
```

**What it does:**
- Tests only the FirstToFire sampler
- Runs 12 conditions (n_enabled=10, n_changes=[1,5])
- Same output format as full benchmark
- Much faster execution

**When to use:** For quick testing, development, or validating changes.

**Expected runtime:** 1-3 minutes.

### Method 3: Benchmark Runner

Alternative execution path with simpler output:

```bash
julia --project=. src/benchmark_runner.jl
```

**What it does:**
- Similar to full benchmark with less verbose output
- Useful for automated testing

### Method 4: Basic Functionality Tests

Verify samplers work correctly without full benchmarking:

```bash
julia --project=. test_basic.jl
```

**What it does:**
- Tests basic sampler instantiation and operations
- Verifies condition and sampler construction
- Quick validation (~1 second)

**When to use:** To ensure the package is working correctly after installation or changes.

### Method 5: Interactive Julia REPL

For manual testing and exploration:

```julia
# Start Julia with the project
julia --project=.

# Load the package
using SamplerDome
using Distributions
using Random

# Create a sampler
sampler = FirstToFire{Int,Float64}()
rng = MersenneTwister(42)

# Enable some clocks
enable!(sampler, 1, Exponential(1.0), 0.0, 0.0, rng)
enable!(sampler, 2, Exponential(2.0), 0.0, 0.0, rng)
enable!(sampler, 3, Exponential(0.5), 0.0, 0.0, rng)

# Get next event
tau, which = next(sampler, 0.0, rng)
println("Next event at time $tau for clock $which")

# Fire the clock
fire!(sampler, which, tau)
```

**When to use:** For interactive exploration, debugging, or understanding sampler behavior.

### Method 6: Custom Benchmark

Run a single benchmark configuration:

```julia
using SamplerDome, BenchmarkTools, Distributions, Random

# Choose sampler and condition
sampler = FirstToFire{Int,Float64}()
cond = BenchmarkCondition(100, 10, :exponential, :dense)

# Run benchmark
time_ns, mem_bytes = benchmark_config(sampler, cond)
println("Time: $(time_ns)ns, Memory: $(mem_bytes) bytes")
```

**When to use:** For targeted performance analysis of specific configurations.

## Understanding Benchmark Parameters

Benchmarks test samplers across multiple dimensions:

### Number of Enabled Clocks (`n_enabled`)
- **Values:** 10, 100, 1,000, 10,000
- **Meaning:** How many concurrent active clocks are in the simulation
- **Impact:** Tests scalability

### Number of Changes (`n_changes`)
- **Values:** 1, 10, 100
- **Meaning:** "Churn" - how many clocks are disabled and re-enabled per step
- **Impact:** Tests dynamic update performance
- **Constraint:** Must be ≤ n_enabled

### Distributions
- **Values:** `:exponential`, `:gamma`, `:weibull`
- **Meaning:** Distribution type for inter-event times
- **Note:** DirectCall sampler only works with exponential distributions

### Key Strategy
- **Values:** `:dense`, `:sparse`
- **dense:** Keys are sequential (1, 2, 3, ...)
- **sparse:** Keys are random Int32 values
- **Impact:** Tests data structure efficiency with different key distributions

## Samplers Tested

The benchmark suite includes 7 sampler variants:

1. **FirstToFire** - Pre-samples all clocks, best for non-exponential distributions
2. **FirstReaction** - Classic method, samples all enabled distributions
3. **CombinedNextReaction** - Hybrid optimized approach
4. **DirectCall variants (4 types)** - Only for exponential distributions:
   - DirectCall_Removal_BinaryTree
   - DirectCall_Keep_BinaryTree
   - DirectCall_Removal_CumSum
   - DirectCall_Keep_CumSum

## Benchmark Output

### CSV Output

Results are saved to `data/observations.csv` with columns:

```csv
sampler_type,n_enabled,n_changes,distributions,key_strategy,time_ns,memory_bytes
FirstToFire,10,1,exponential,dense,12345,5678
DirectCall_Removal_BinaryTree,10,1,exponential,dense,23456,4321
...
```

### Console Output

During execution, you'll see progress:

```
[1/504] FirstToFire: n=10, churn=1, dist=exponential, keys=dense... ✓ 12.3μs
[2/504] FirstToFire: n=10, churn=1, dist=exponential, keys=sparse... ✓ 14.5μs
[3/504] DirectCall_Removal_BinaryTree: n=10, churn=1, dist=exponential, keys=dense... ✓ 8.7μs
```

## Customizing Benchmarks

To customize benchmark parameters, edit `src/conditions.jl`:

```julia
# Modify these constants
const N_ENABLED = [10, 100, 1_000, 10_000]
const N_CHANGES = [1, 10, 100]
const DISTRIBUTIONS = [:exponential, :gamma, :weibull]
const KEY_STRATEGIES = [:dense, :sparse]
```

Then run the full benchmark suite to test with your custom parameters.

## Analyzing Results

After running benchmarks, analyze the CSV output:

```julia
using DataFrames, CSV

# Load results
df = CSV.read("data/observations.csv", DataFrame)

# Find fastest sampler for each condition
using Statistics
grouped = groupby(df, [:n_enabled, :n_changes, :distributions, :key_strategy])
fastest = combine(grouped, :time_ns => minimum => :min_time)

# Compare samplers
by_sampler = groupby(df, :sampler_type)
comparison = combine(by_sampler, :time_ns => mean => :avg_time, :time_ns => median => :median_time)
sort!(comparison, :median_time)
```

## Troubleshooting

### Package Dependencies

If you encounter missing dependencies:

```bash
julia --project=. -e "using Pkg; Pkg.resolve(); Pkg.instantiate()"
```

### Manifest.toml Issues

The repository has an untracked `Manifest.toml`. If you have issues, regenerate it:

```bash
julia --project=. -e "using Pkg; Pkg.resolve()"
```

### Performance Variability

For more stable benchmarks:
- Close other applications
- Run multiple times and average results
- Adjust BenchmarkTools samples (default is 100) in `src/measure.jl`

## Next Steps

- Review the [README.md](../../README.md) for detailed package structure
- Explore individual sampler implementations in `src/`
- Read technical documentation for data structures in `docs/src/`
- Modify benchmark parameters for your use case
- Implement custom samplers using the `SSA{K,T}` interface

## Quick Reference

| Task | Command |
|------|---------|
| Full benchmark | `julia --project=. -e 'include("src/run_all.jl"); main()'` |
| Quick test | `julia --project=. test_basic.jl` |
| Minimal benchmark | `julia --project=. -e 'include("src/minimal_benchmark.jl"); main()'` |
| Interactive mode | `julia --project=.` then `using SamplerDome` |
| Install dependencies | `julia --project=. -e "using Pkg; Pkg.instantiate()"` |
