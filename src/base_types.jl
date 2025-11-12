"""
Base types and structures for SamplerDome samplers.
"""

using Distributions: UnivariateDistribution
using Random: AbstractRNG

# Type alias for continuous time values
const ContinuousTime = AbstractFloat

"""
Abstract type for Stochastic Simulation Algorithm (SSA) samplers.
"""
abstract type SSA{K,T} end

"""
Abstract type for samplers that track enabled clocks.
"""
abstract type EnabledWatcher{K,T} <: SSA{K,T} end

"""
Represents an enabled clock with its distribution and enabling time.
"""
struct EnablingEntry{K,T}
    clock::K
    distribution::UnivariateDistribution
    te::T  # enabling time
end

"""
Ordered sample for priority queue, storing a clock and its firing time.
"""
struct OrderedSample{K,T}
    clock::K
    time::T
end

# Define ordering for OrderedSample (for use in heaps)
Base.isless(a::OrderedSample, b::OrderedSample) = isless(a.time, b.time)

"""
A watcher that tracks which clocks are enabled.
Used by samplers that need to maintain a registry of enabled clocks.
"""
mutable struct TrackWatcher{K,T}
    enabled::Dict{K,EnablingEntry{K,T}}
    TrackWatcher{K,T}() where {K,T} = new(Dict{K,EnablingEntry{K,T}}())
end

function Base.iterate(tw::TrackWatcher)
    iterate(values(tw.enabled))
end

function Base.iterate(tw::TrackWatcher, state)
    iterate(values(tw.enabled), state)
end

function Base.keys(tw::TrackWatcher)
    keys(tw.enabled)
end

function Base.haskey(tw::TrackWatcher, clock)
    haskey(tw.enabled, clock)
end

"""
Enable a clock in the TrackWatcher.
"""
function enable!(tw::TrackWatcher{K,T}, clock::K, distribution::UnivariateDistribution,
                 te::T, when::T, rng::AbstractRNG) where {K,T}
    tw.enabled[clock] = EnablingEntry{K,T}(clock, distribution, te)
    nothing
end

"""
Disable a clock in the TrackWatcher.
"""
function disable!(tw::TrackWatcher{K,T}, clock::K, when::T) where {K,T}
    delete!(tw.enabled, clock)
    nothing
end

"""
Common interface: fire! (disable and advance time)
"""
function fire! end

"""
Common interface: reset sampler to initial state
"""
function reset! end

"""
Common interface: enable a clock
"""
function enable! end

"""
Common interface: disable a clock
"""
function disable! end

"""
Common interface: get next event
"""
function next end

"""
Common interface: get enabled clocks
"""
function enabled end

"""
Common interface: check if clock is enabled
"""
function isenabled end

"""
Common interface: clone a sampler
"""
function clone end
