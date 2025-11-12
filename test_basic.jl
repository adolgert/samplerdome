using SamplerDome
using Distributions
using Random

println("Testing basic sampler functionality...")

# Create a sampler
sampler = FirstToFire{Int,Float64}()
println("✓ Created FirstToFire sampler")

# Initialize RNG
rng = MersenneTwister(42)

# Reset sampler
reset!(sampler)
println("✓ Reset sampler")

# Enable some clocks
enable!(sampler, 1, Exponential(1.0), 0.0, 0.0, rng)
enable!(sampler, 2, Exponential(2.0), 0.0, 0.0, rng)
enable!(sampler, 3, Exponential(0.5), 0.0, 0.0, rng)
println("✓ Enabled 3 clocks")

# Get next event
tau, which = next(sampler, 0.0, rng)
println("✓ Next event at time $tau for clock $which")

# Test sampler construction
println("\nTesting sampler construction...")
samplers = construct_samplers()
println("✓ Constructed $(length(samplers)) samplers:")
for s in samplers
    println("  - $(sampler_name(typeof(s)))")
end

# Test condition generation
println("\nTesting condition generation...")
conditions = generate_conditions()
println("✓ Generated $(length(conditions)) benchmark conditions")

println("\n✅ All basic tests passed!")
