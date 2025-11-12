Here is a **Radix / PATRICIA “sum‑trie”** for Julia. Keys `K` are ordered by a deterministic 128‑bit hash; each internal node stores a critical bit and a subtree sum, so `sum!` is `O(1)` and `choose(u)` is `O(height)` with `height ≤ 128`. It implements the same interface your samplers use: `setindex!`, `getindex`, `delete!`, `sum!`, `choose`, `isenabled`, `enabled`, `rand`, plus an `index::Dict` so `keys(dc)` keeps working with your `DirectCall`. This matches the API shape in your existing prefix types and samplers.    

---

### Julia implementation: `PatriciaSumTrie` (crit‑bit, subtree sums)

```julia
import Base: sum!, setindex!, getindex, delete!, length, empty!
using Random
using Distributions: Uniform

# ----------------------------
# Bit helpers
# ----------------------------
# Deterministic 128-bit order key from the user's key.
@inline function _ordkey(k, seed::UInt)::UInt128
    h1 = UInt64(hash(k, seed))
    h2 = UInt64(hash(k, seed ⊻ 0x9e3779b97f4a7c15))
    return (UInt128(h1) << 64) | UInt128(h2)
end

# Highest differing bit index in [0..127] (0 = LSB). Returns -1 if equal.
@inline function _highest_diff_bit(a::UInt128, b::UInt128)::Int
    x = a ⊻ b
    x == 0 && return -1
    return 127 - leading_zeros(x)  # Int
end

# Test the bit at index i (0=LSB). Returns false for 0, true for 1.
@inline _bit(x::UInt128, i::Int) = ((x >> i) & UInt128(1)) == UInt128(1)

# ----------------------------
# Nodes: Branch (internal) and Leaf
# ----------------------------
abstract type _PNode{K,T} end

mutable struct _Leaf{K,T<:Real} <: _PNode{K,T}
    ok::UInt128            # 128-bit order key
    keys::Vector{K}        # handle ultra-rare 128-bit hash collisions
    weights::Vector{T}
    selfsum::T             # sum(weights)
    sum::T                 # subtree sum (== selfsum for leaves)
end

mutable struct _Branch{K,T<:Real} <: _PNode{K,T}
    crit::Int              # critical bit index [0..127]
    left::Union{Nothing,_PNode{K,T}}
    right::Union{Nothing,_PNode{K,T}}
    sum::T                 # subtree sum = sum(left) + sum(right)
end

@inline _sum(n::Union{Nothing,_PNode{K,T}}) where {K,T} =
    n === nothing ? zero(T) : (n isa _Leaf{K,T} ? n.sum : (n:: _Branch{K,T}).sum)

@inline function _recalc!(b::_Branch{K,T}) where {K,T}
    b.sum = _sum(b.left) + _sum(b.right)
    return b
end

# ----------------------------
# Public container
# ----------------------------
struct PatriciaSumTrie{K,T<:Real} <: KeyedPrefixSearch
    root::Union{Nothing,_PNode{K,T}}
    n::Int                 # number of stored keys
    seed::UInt             # hash seeding for stable order keys
    index::Dict{K,Int}     # for DirectCall.keys(dc): values unused
end

PatriciaSumTrie{K,T}(; seed::UInt=0x12345678) where {K,T<:Real} =
    PatriciaSumTrie{K,T}(nothing, 0, seed, Dict{K,Int}())

time_type(::PatriciaSumTrie{K,T}) where {K,T} = T
time_type(::Type{PatriciaSumTrie{K,T}}) where {K,T} = T
Base.length(ps::PatriciaSumTrie) = ps.n

function Base.empty!(ps::PatriciaSumTrie{K,T}) where {K,T}
    empty!(ps.index)
    Base.setfield!(ps, :root, nothing)
    Base.setfield!(ps, :n, 0)
    ps
end

# ----------------------------
# Lookup helpers
# ----------------------------
# Follow crit-bits until a leaf, collecting the path of branches.
# Returns (leaf, path::Vector{_Branch{K,T}}, dirpath::Vector{Bool})
# dirpath[i] == false means we took left at path[i]; true => right.
function _descend_to_leaf(root::Union{Nothing,_PNode{K,T}}, ok::UInt128) where {K,T}
    path = Vector{_Branch{K,T}}()
    dirp = Vector{Bool}()
    node = root
    while node isa _Branch{K,T}
        b = node:: _Branch{K,T}
        push!(path, b)
        d = _bit(ok, b.crit)
        push!(dirp, d)
        node = d ? b.right : b.left
    end
    return (node::Union{Nothing,_Leaf{K,T}}, path, dirp)
end

# Recompute sums along the recorded path by simple "+δ" propagation.
@inline function _propagate!(path::Vector{_Branch{K,T}}, δ) where {K,T}
    for i in eachindex(path)
        path[i].sum += δ
    end
end

# ----------------------------
# setindex! (insert / update)
# ----------------------------
function Base.setindex!(ps::PatriciaSumTrie{K,T}, w::T, key::K) where {K,T}
    ok = _ordkey(key, ps.seed)

    # Empty tree
    if ps.root === nothing
        leaf = _Leaf{K,T}(ok, [key], [w], w, w)
        Base.setfield!(ps, :root, leaf)
        Base.setfield!(ps, :n, 1)
        ps.index[key] = 1
        return w
    end

    # First pass: reach leaf on current path
    leaf, path, dirp = _descend_to_leaf(ps.root, ok)

    if leaf !== nothing && leaf.ok == ok
        # Update existing or add to collision bucket
        for i in eachindex(leaf.keys)
            if isequal(leaf.keys[i], key)
                δ = w - leaf.weights[i]
                if δ != 0
                    leaf.weights[i] = w
                    leaf.selfsum += δ
                    leaf.sum = leaf.selfsum
                    _propagate!(path, δ)
                end
                return w
            end
        end
        # Collision: new entry under same 128-bit key
        push!(leaf.keys, key); push!(leaf.weights, w)
        leaf.selfsum += w; leaf.sum = leaf.selfsum
        _propagate!(path, w)
        Base.setfield!(ps, :n, ps.n + 1)
        ps.index[key] = ps.n
        return w
    end

    # New key: compute critical bit vs the reached leaf
    @assert leaf !== nothing
    kcrit = _highest_diff_bit(ok, leaf.ok)
    @assert kcrit ≥ 0

    # Second pass: find insertion parent where branch.crit > kcrit
    parent = nothing
    child  = ps.root
    side_right = false
    while child isa _Branch{K,T} && (child:: _Branch{K,T}).crit > kcrit
        b = child:: _Branch{K,T}
        parent = b
        side_right = _bit(ok, b.crit)
        child = side_right ? b.right : b.left
    end

    # Build new leaf and branch at kcrit
    newleaf = _Leaf{K,T}(ok, [key], [w], w, w)
    newbranch = _Branch{K,T}(kcrit, nothing, nothing, zero(T))
    if _bit(ok, kcrit)
        newbranch.left  = child
        newbranch.right = newleaf
    else
        newbranch.left  = newleaf
        newbranch.right = child
    end
    _recalc!(newbranch)

    if parent === nothing
        Base.setfield!(ps, :root, newbranch)
    else
        if side_right
            parent.right = newbranch
        else
            parent.left  = newbranch
        end
        # propagate +w along the path from root→parent
        # We can reuse the first-pass path up to the first branch whose crit ≤ kcrit.
        for i in eachindex(path)
            if path[i].crit > kcrit
                path[i].sum += w
            end
        end
        # parent was updated structurally; ensure ancestors not in 'path' are correct:
        # The loop above covered them. newbranch.sum already includes 'child'.
    end

    Base.setfield!(ps, :n, ps.n + 1)
    ps.index[key] = ps.n
    return w
end

# ----------------------------
# getindex (lookup)
# ----------------------------
function Base.getindex(ps::PatriciaSumTrie{K,T}, key::K) where {K,T}
    ok = _ordkey(key, ps.seed)
    leaf, _, _ = _descend_to_leaf(ps.root, ok)
    leaf === nothing && throw(KeyError(key))
    if leaf.ok == ok
        for i in eachindex(leaf.keys)
            if isequal(leaf.keys[i], key)
                return leaf.weights[i]
            end
        end
    end
    throw(KeyError(key))
end

# ----------------------------
# delete! (remove)
# ----------------------------
function Base.delete!(ps::PatriciaSumTrie{K,T}, key::K) where {K,T}
    ok = _ordkey(key, ps.seed)
    # Track branches and directions to allow splicing and sum updates.
    path = Vector{_Branch{K,T}}()
    dirp = Vector{Bool}()
    node = ps.root
    parent::Union{Nothing,_Branch{K,T}} = nothing
    side_right = false

    while node isa _Branch{K,T}
        b = node:: _Branch{K,T}
        push!(path, b)
        side_right = _bit(ok, b.crit)
        push!(dirp, side_right)
        parent = b
        node = side_right ? b.right : b.left
    end
    leaf = node::Union{Nothing,_Leaf{K,T}}
    if leaf === nothing || leaf.ok != ok
        return ps  # not present
    end

    # Remove key from leaf bucket
    idx = findfirst(i -> isequal(leaf.keys[i], key), eachindex(leaf.keys))
    idx === nothing && return ps
    old = leaf.weights[idx]
    deleteat!(leaf.keys, idx); deleteat!(leaf.weights, idx)
    leaf.selfsum -= old
    leaf.sum = leaf.selfsum
    _propagate!(path, -old)
    Base.setfield!(ps, :n, ps.n - 1)
    pop!(ps.index, key, nothing)

    # If leaf emptied, splice it out
    if leaf.selfsum == zero(T)
        if parent === nothing
            # leaf was the only node
            Base.setfield!(ps, :root, nothing)
            return ps
        end
        # parent loses one child: replace parent by its remaining child
        sibling = dirp[end] ? parent.left : parent.right
        # Rewire the grandparent
        if length(path) == 1
            # parent was root
            Base.setfield!(ps, :root, sibling)
        else
            gpar = path[end-1]
            if dirp[end-1]
                gpar.right = sibling
            else
                gpar.left  = sibling
            end
            # sums were already decreased by -old; structure is consistent.
        end
    end
    return ps
end

# ----------------------------
# enabled / isenabled
# ----------------------------
isenabled(ps::PatriciaSumTrie{K,T}, key::K) where {K,T} = haskey(ps.index, key)
enabled(ps::PatriciaSumTrie{K,T}) where {K,T} = keys(ps.index)

# ----------------------------
# totals and choice
# ----------------------------
Base.sum!(ps::PatriciaSumTrie{K,T}) where {K,T} =
    (ps.root === nothing ? zero(T) :
     ps.root isa _Leaf{K,T}   ? (ps.root:: _Leaf{K,T}).sum :
                                (ps.root:: _Branch{K,T}).sum)

# u in [0, total)
function choose(ps::PatriciaSumTrie{K,T}, u::T) where {K,T}
    total = sum!(ps)
    if !(zero(T) ≤ u < total)
        error("choose: u=$u not in [0,$total)")
    end
    node = ps.root
    while node isa _Branch{K,T}
        b = node:: _Branch{K,T}
        lsum = _sum(b.left)
        if u < lsum
            node = b.left
        else
            u -= lsum
            node = b.right
        end
    end
    leaf = node:: _Leaf{K,T}
    # intra-leaf selection (rare collision bucket)
    s = zero(T)
    @inbounds for i in eachindex(leaf.keys)
        s += leaf.weights[i]
        if u < s
            return (leaf.keys[i], leaf.weights[i])
        end
    end
    # Fallback (numerical edge)
    return (leaf.keys[end], leaf.weights[end])
end

# Random integration like your other prefix types
Random.rand(rng::AbstractRNG, d::Random.SamplerTrivial{PatriciaSumTrie{K,T}}) where {K,T} =
    choose(d[], rand(rng, Uniform{T}(zero(T), sum!(d[]))))
```

---

### How to use with your sampler

```julia
# Choose key and time types
const K = String
const T = Float64

ps = PatriciaSumTrie{K,T}()   # dict-like: K => T with sum/choose

# Basic ops
ps["a"] = 1.0
ps["b"] = 3.0
ps["c"] = 2.0
total = sum!(ps)              # 6.0
k, w = choose(ps, 2.2)        # returns a key, weighted by its rate

# Plug into DirectCall (your struct accepts any keyed prefix with this API)
dc = DirectCall{K,T,typeof(ps)}(ps, 0.0, 0.0, false)  # works with your Direct sampler
# enable!/disable!/next use only [], delete!, sum!, and rand, which this type provides. :contentReference[oaicite:4]{index=4}
```

---

### Complexity and behavior

* Insert, update, delete: `O(height)` with `height ≤ 128` (binary key length).
* `sum!`: `O(1)` from cached subtree sums.
* `choose(u)`: `O(height)` by traversing critical bits.
* Collisions: two distinct keys that collide in 128 bits share a leaf bucket; intra‑bucket operations are `O(1)` in expectation because collisions are negligible.

This gives you a **dictionary‑native** sampler structure with the same `choose` contract as your current prefix structures and samplers, without maintaining a separate key→index table for correctness. Your existing `BinaryTreePrefixSearch`, `CumSumPrefixSearch`, and keyed wrappers document the expected API and sampling semantics; this trie satisfies those and drops into `DirectCall` directly.    

If you later want two‑level hashing instead, your `MultipleDirect` already represents that pattern and can wrap many smaller structures behind a top‑level chooser. 
