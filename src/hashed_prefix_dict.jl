# Requires: BinaryTreePrefixSearch, CumSumPrefixSearch,
#           KeyedRemovalPrefixSearch, KeyedKeepPrefixSearch
# from your files.

struct HashedPrefixDict{K,T,InnerPS}
    buckets::Vector{InnerPS}            # per-bucket keyed prefix search
    bucket_total::Vector{T}             # mirror of each bucket's total
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
    buckets = [InnerPS() for _ in 1:nbuckets]
    bucket_total = zeros(T, nbuckets)
    bt = BinaryTreePrefixSearch{T}(nbuckets)
    for _ in 1:nbuckets
        push!(bt, zero(T))            # initialize leaves
    end
    return HashedPrefixDict{K,T,InnerPS}(buckets, bucket_total, bt, nbuckets, seed)
end

# Default inner: removal + binary tree per bucket.
const DefaultInner{K,T} = KeyedRemovalPrefixSearch{K, BinaryTreePrefixSearch{T}}
HashedPrefixDict{K,T}(; nbuckets=1024, seed=0x00000000) where {K,T} =
    HashedPrefixDict{K,T,DefaultInner{K,T}}(; nbuckets, seed)

# 1-based bucket index from hash
@inline function _bix(h::HashedPrefixDict{K,T,PS}, k) where {K,T,PS}
    return (Int((UInt(hash(k, h.seed)) & UInt(h.nbuckets - 1))) + 1)
end

# setindex! with incremental maintenance of bucket totals and top prefix
function Base.setindex!(h::HashedPrefixDict{K,T,PS}, val::T, k::K) where {K,T,PS}
    i = _bix(h, k)
    b = h.buckets[i]
    old = isenabled(b, k) ? b[k] : zero(T)   # both keyed variants support this
    b[k] = val                               # updates inner prefix
    δ = val - old
    if δ != zero(T)
        h.bucket_total[i] += δ
        h.bucket_tree[i] = h.bucket_total[i] # updates top prefix in O(log B)
    end
    return val
end

function Base.delete!(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS}
    i = _bix(h, k)
    b = h.buckets[i]
    if isenabled(b, k)
        old = b[k]
        delete!(b, k)
        h.bucket_total[i] -= old
        h.bucket_tree[i] = h.bucket_total[i]
    end
    return h
end

Base.getindex(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS} = h.buckets[_bix(h, k)][k]
Base.haskey(h::HashedPrefixDict{K,T,PS}, k::K) where {K,T,PS} = isenabled(h.buckets[_bix(h, k)], k)

# Total weight
Base.sum!(h::HashedPrefixDict{K,T,PS}) where {K,T,PS} = sum!(h.bucket_tree)

# Single-uniform choose: returns (key, weight)
function choose(h::HashedPrefixDict{K,T,PS}, u::T) where {K,T,PS}
    total = sum!(h)
    @assert zero(T) ≤ u && u < total
    (i, _) = choose(h.bucket_tree, u)              # which bucket
    left = _prefix_before(h.bucket_tree, i)        # sum of all prior buckets
    u_in_bucket = u - left
    return choose(h.buckets[i], u_in_bucket)       # returns (key, weight)
end
