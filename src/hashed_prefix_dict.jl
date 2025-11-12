# Requires: BinaryTreePrefixSearch

# Simple bucket: parallel vectors of keys and values
struct SimpleBucket{K,T}
    keys::Vector{K}
    values::Vector{T}
end

struct HashedPrefixDict{K,T,InnerPS}
    buckets::Vector{InnerPS}            # per-bucket simple storage
    bucket_total::Vector{T}             # sum of each bucket's values
    bucket_tree::BinaryTreePrefixSearch{T}  # prefix over bucket totals
    nbuckets::Int
    seed::UInt
end

# Helper: compute prefix sum of all leaves strictly before leaf i in a BinaryTreePrefixSearch
function _prefix_before(pst::BinaryTreePrefixSearch{T}, i::Int) where {T}
    idx = pst.offset - 1 + i
    s = zero(T)
    while idx > 1
        if isodd(idx)                 # right child
            s += pst.array[idx - 1]   # add left sibling
        end
        idx >>>= 1
    end
    return s
end

# Constructor. Pick a power-of-two bucket count.
function HashedPrefixDict{K,T,InnerPS}(; nbuckets::Int=1024, seed::UInt=0) where {K,T,InnerPS}
    @assert nbuckets > 0 && nbuckets & (nbuckets - 1) == 0  # power of two
    buckets = [SimpleBucket(K[], T[]) for _ in 1:nbuckets]
    bucket_total = zeros(T, nbuckets)
    bt = BinaryTreePrefixSearch{T}(nbuckets)
    for _ in 1:nbuckets
        push!(bt, zero(T))            # initialize leaves
    end
    return HashedPrefixDict{K,T,InnerPS}(buckets, bucket_total, bt, nbuckets, seed)
end

# Default inner: SimpleBucket
const DefaultInner{K,T} = SimpleBucket{K,T}
HashedPrefixDict{K,T}(; nbuckets=1024, seed=UInt(0)) where {K,T} =
    HashedPrefixDict{K,T,DefaultInner{K,T}}(; nbuckets, seed)

# 1-based bucket index from hash
@inline function _bix(h::HashedPrefixDict{K,T,PS}, k) where {K,T,PS}
    return (Int((UInt(hash(k, h.seed)) & UInt(h.nbuckets - 1))) + 1)
end

# setindex! with incremental maintenance of bucket totals and top prefix
function Base.setindex!(h::HashedPrefixDict{K,T,PS}, val::T, k::K) where {K,T,PS}
    i = _bix(h, k)
    b = h.buckets[i]

    # Linear search for existing key
    idx = findfirst(==(k), b.keys)
    if idx !== nothing
        old = b.values[idx]
        b.values[idx] = val
        δ = val - old
    else
        # New key: append to both vectors
        push!(b.keys, k)
        push!(b.values, val)
        δ = val
    end

    if δ != zero(T)
        h.bucket_total[i] += δ
        h.bucket_tree[i] = h.bucket_total[i] # updates top prefix in O(log B)
    end
    return val
end

function Base.delete!(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS}
    i = _bix(h, k)
    b = h.buckets[i]

    # Linear search for key
    idx = findfirst(==(k), b.keys)
    if idx !== nothing
        old = b.values[idx]

        # Swap with last element and pop (O(1) removal)
        last_idx = length(b.keys)
        if idx != last_idx
            b.keys[idx] = b.keys[last_idx]
            b.values[idx] = b.values[last_idx]
        end
        pop!(b.keys)
        pop!(b.values)

        h.bucket_total[i] -= old
        h.bucket_tree[i] = h.bucket_total[i]
    end
    return h
end

function Base.getindex(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS}
    b = h.buckets[_bix(h, k)]
    idx = findfirst(==(k), b.keys)
    if idx === nothing
        throw(KeyError(k))
    end
    return b.values[idx]
end

function Base.haskey(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS}
    b = h.buckets[_bix(h, k)]
    return findfirst(==(k), b.keys) !== nothing
end

# Total weight
Base.sum!(h::HashedPrefixDict{K,T,PS}) where {K,T,PS} = sum!(h.bucket_tree)

# Empty all buckets
function Base.empty!(h::HashedPrefixDict{K,T,PS}) where {K,T,PS}
    for i in 1:h.nbuckets
        empty!(h.buckets[i].keys)
        empty!(h.buckets[i].values)
        h.bucket_total[i] = zero(T)
        h.bucket_tree[i] = zero(T)
    end
    return h
end

# Copy from src to dst
function Base.copy!(dst::HashedPrefixDict{K,T,PS}, src::HashedPrefixDict{K,T,PS}) where {K,T,PS}
    @assert dst.nbuckets == src.nbuckets
    for i in 1:src.nbuckets
        copy!(dst.buckets[i].keys, src.buckets[i].keys)
        copy!(dst.buckets[i].values, src.buckets[i].values)
        dst.bucket_total[i] = src.bucket_total[i]
    end
    copy!(dst.bucket_tree.array, src.bucket_tree.array)
    return dst
end

# Number of keys across all buckets
function Base.length(h::HashedPrefixDict{K,T,PS}) where {K,T,PS}
    return sum(length(b.keys) for b in h.buckets)
end

# Iterator over all enabled keys
function enabled(h::HashedPrefixDict{K,T,PS}) where {K,T,PS}
    return Iterators.flatten(b.keys for b in h.buckets)
end

# Check if key is enabled (alias for haskey)
isenabled(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS} = haskey(h, k)

# Type introspection
key_type(::HashedPrefixDict{K,T,PS}) where {K,T,PS} = K
time_type(::HashedPrefixDict{K,T,PS}) where {K,T,PS} = T

# Single-uniform choose: returns (key, weight)
function choose(h::HashedPrefixDict{K,T,PS}, u::T) where {K,T,PS}
    total = sum!(h)
    @assert zero(T) ≤ u && u < total
    (i, _) = choose(h.bucket_tree, u)              # which bucket
    left = _prefix_before(h.bucket_tree, i)        # sum of all prior buckets
    u_in_bucket = u - left

    # Lazy prefix sum within the selected bucket
    b = h.buckets[i]
    cumsum = zero(T)
    for j in 1:length(b.keys)
        cumsum += b.values[j]
        if cumsum > u_in_bucket
            return (b.keys[j], b.values[j])
        end
    end

    # Should never reach here if bucket_total is maintained correctly
    error("choose: u_in_bucket=$u_in_bucket not found in bucket $i with total $(h.bucket_total[i])")
end
