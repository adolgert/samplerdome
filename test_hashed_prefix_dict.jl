# Simple test for HashedPrefixDict
using Random

# Load dependencies
include("src/binarytreeprefixsearch.jl")
include("src/hashed_prefix_dict.jl")

println("Testing HashedPrefixDict...")

# Create a HashedPrefixDict with 4 buckets for easy testing
h = HashedPrefixDict{Symbol,Float64}(nbuckets=4, seed=UInt(0))
println("✓ Created HashedPrefixDict{Symbol,Float64} with 4 buckets")

# Test setindex! - add some keys
h[:a] = 10.0
h[:b] = 20.0
h[:c] = 5.0
h[:d] = 15.0
println("✓ Added 4 keys with values 10.0, 20.0, 5.0, 15.0")

# Test haskey and getindex
@assert haskey(h, :a) "Should have key :a"
@assert haskey(h, :b) "Should have key :b"
@assert !haskey(h, :z) "Should not have key :z"
@assert h[:a] == 10.0 "Value for :a should be 10.0"
@assert h[:b] == 20.0 "Value for :b should be 20.0"
println("✓ haskey and getindex work correctly")

# Test sum!
total = sum!(h)
@assert total == 50.0 "Total should be 50.0, got $total"
println("✓ sum! returns correct total: $total")

# Test length
len = length(h)
@assert len == 4 "Length should be 4, got $len"
println("✓ length returns correct count: $len")

# Test update existing key
h[:a] = 25.0
@assert h[:a] == 25.0 "Updated value for :a should be 25.0"
new_total = sum!(h)
@assert new_total == 65.0 "Total after update should be 65.0, got $new_total"
println("✓ Updating existing key works correctly")

# Test choose
rng = MersenneTwister(42)
for i in 1:10
    u = rand(rng) * sum!(h)
    key, val = choose(h, u)
    @assert haskey(h, key) "Chosen key should exist"
    @assert h[key] == val "Chosen value should match"
end
println("✓ choose returns valid keys 10 times")

# Test delete!
delete!(h, :b)
@assert !haskey(h, :b) "Key :b should be deleted"
@assert length(h) == 3 "Length should be 3 after deletion"
total_after_delete = sum!(h)
@assert total_after_delete == 45.0 "Total after deleting :b should be 45.0, got $total_after_delete"
println("✓ delete! works correctly")

# Test enabled
enabled_keys = collect(enabled(h))
@assert length(enabled_keys) == 3 "Should have 3 enabled keys"
@assert :a in enabled_keys "Should contain :a"
@assert :c in enabled_keys "Should contain :c"
@assert :d in enabled_keys "Should contain :d"
println("✓ enabled() returns correct keys")

# Test isenabled
@assert isenabled(h, :a) "Key :a should be enabled"
@assert !isenabled(h, :b) "Key :b should not be enabled"
println("✓ isenabled works correctly")

# Test empty!
empty!(h)
@assert length(h) == 0 "Length should be 0 after empty!"
@assert sum!(h) == 0.0 "Sum should be 0.0 after empty!"
println("✓ empty! clears all data")

# Test copy!
h1 = HashedPrefixDict{Symbol,Float64}(nbuckets=4, seed=UInt(0))
h1[:x] = 100.0
h1[:y] = 200.0

h2 = HashedPrefixDict{Symbol,Float64}(nbuckets=4, seed=UInt(0))
copy!(h2, h1)
@assert haskey(h2, :x) "Copied dict should have :x"
@assert h2[:x] == 100.0 "Copied value should be 100.0"
@assert sum!(h2) == 300.0 "Copied sum should be 300.0"
println("✓ copy! works correctly")

# Test type introspection
@assert key_type(h1) == Symbol "key_type should be Symbol"
@assert time_type(h1) == Float64 "time_type should be Float64"
println("✓ Type introspection works")

println("\n✅ All HashedPrefixDict tests passed!")
