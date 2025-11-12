Yes. Build a dict‑like container whose values contribute to a maintained prefix sum. Three workable designs:

1. **Hash‑to‑buckets + prefix over bucket totals.**
   Hash each key into one of B buckets. Keep a prefix‑sum tree over the B bucket totals. Inside each bucket, keep a tiny keyed prefix structure. `choose(u)` finds the bucket by prefix, subtracts the bucket’s left prefix, then chooses within that bucket. Updates are `O(log B)` for the top tree plus expected `O(1)` for the small bucket. This drops cleanly into your existing code because you already have:

* a segment tree with `choose` (`BinaryTreePrefixSearch`) 
* keyed wrappers that turn any prefix structure into a dict‑like map (`KeyedKeepPrefixSearch` and `KeyedRemovalPrefixSearch`) 
* a hierarchical sampler that first selects a subset then selects within it (`MultipleDirect`)—exactly the two‑level idea 

2. **Order‑statistics tree (treap/AVL/RB) augmented with subtree sums.**
   Each node stores its value and the sum of its subtree. `choose(u)` walks left/right by comparing `u` with the left subtree sum. All operations are `O(log n)`. You can key nodes by `(hash(key), key)` to break collisions. This looks like a sorted dictionary with a maintained prefix sum.

3. **Radix/PATRICIA “sum‑trie” over 64‑bit hashes.**
   A compressed binary trie indexed by hash bits. Each internal node stores the sum of its descendants. `choose(u)` follows the bits using the stored sums. Updates are `O(height)`; with compression the height is practical. This behaves like a dictionary indexed by hashed integers without a separate index map.

---

### You can implement #1 now with your types

* Top level: one `BinaryTreePrefixSearch{T}` over `B` buckets. Each leaf stores the total weight of its bucket. `choose` on this tree gives the bucket index in `O(log B)`. 
* Bucket level: for each bucket, use `KeyedRemovalPrefixSearch{K, BinaryTreePrefixSearch{T}}` (removes disabled keys, reuses slots) or `KeyedKeepPrefixSearch{K, CumSumPrefixSearch{T}}` (keeps zeros, cheap for small buckets). Both already expose `setindex!`, `delete!`, `sum!`, and `choose` that returns the original key.  

**Complexity.** With a fixed load factor, expected bucket size is constant.

* `setindex!` or `delete!`: `O(log B)` to update the top tree.
* `sum!`: `O(1)` at the top if you maintain bucket totals incrementally.
* `choose(u)`: `O(log B)` for the bucket, plus `O(log b)` or `O(b)` inside the bucket depending on the inner structure.

---

### Minimal Julia sketch: a hashed‑bucket prefix “dict”

This composes your pieces. It uses one uniform `u` and computes the intra‑bucket residual by a constant‑time tree walk.

```julia
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
```

Usage choices for the inner bucket:

* Small buckets and many toggles: `InnerPS = KeyedKeepPrefixSearch{K, CumSumPrefixSearch{T}}` (cheap to update, lazy cumsum).  
* Larger buckets: `InnerPS = KeyedRemovalPrefixSearch{K, BinaryTreePrefixSearch{T}}` (logarithmic choose inside the bucket).  

This container “looks like a Dict” (`setindex!`, `getindex`, `haskey`, `delete!`), and it exposes `sum!` and `choose`. It stays stable under churn because `KeyedRemovalPrefixSearch` reuses freed slots. 

---

### If you want a single‑structure alternative

* **Order‑statistics treap.** Each node: `(key, weight, priority, sumLeft+self+sumRight)`. Insertion, deletion, weight edits update sums along the path. `choose(u)` follows the sums.
* **Patricia “sum‑trie.”** Nodes store a bit index and `(sum_left, sum_right)`. Insertion splits on the first differing bit. `choose(u)` branches by comparing `u` to `sum_left`.

Both give `O(log n)` operations. They avoid array rehash moves, but they are more code than the two‑level approach.

---

### How this lines up with your samplers

* Your `DirectCall` already expects a keyed prefix structure with `sum!` and `choose`; you can drop `HashedPrefixDict` in as that structure. It will behave like a dictionary and still support Direct sampling. 
* Your `MultipleDirect` is the general two‑level version; using a hash‑based chooser maps keys to buckets and yields the same effect. 

**Summary.** The cleanest path is the hash‑to‑buckets prefix with your existing `BinaryTreePrefixSearch` and keyed wrappers. It gives dict semantics, `sum!`, and `choose` with predictable `O(log B)` outer cost and tiny inner cost, and it leverages code you already wrote.    
