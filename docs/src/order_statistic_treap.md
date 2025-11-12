Yes. Here is an **order‑statistics treap** in Julia. It is a dict‑like map `K ⇒ T` that maintains subtree sums for `sum!` and supports `choose(u)` in O(log n). It plugs into your Direct sampler because it implements `setindex!`, `delete!`, `sum!`, and `rand/choose`. Your array tree requires dense indices, this does not.  

```julia
import Base: setindex!, getindex, delete!, haskey, empty!, length, keys
import Random
using Distributions: Uniform

# ----- Node -----
mutable struct _OTNode{K,T<:Real}
    ok::UInt128               # total order key (hash||counter)
    key::K                    # original key
    val::T                    # weight at this node
    sum::T                    # subtree sum
    prio::UInt64              # heap priority (treap)
    left::Union{Nothing,_OTNode{K,T}}
    right::Union{Nothing,_OTNode{K,T}}
end

@inline _lsum(n::Union{Nothing,_OTNode{K,T}}) where {K,T} = n === nothing ? zero(T) : n.sum
@inline function _recalc!(n::_OTNode{K,T}) where {K,T}
    n.sum = n.val + _lsum(n.left) + _lsum(n.right)
    return n
end

# ----- Treap core (split/merge/insert/erase/find/update/choose) -----
function _merge(a::Union{Nothing,_OTNode{K,T}}, b::Union{Nothing,_OTNode{K,T}}) where {K,T}
    a === nothing && return b
    b === nothing && return a
    if a.prio ≤ b.prio
        a.right = _merge(a.right, b)
        return _recalc!(a)
    else
        b.left = _merge(a, b.left)
        return _recalc!(b)
    end
end

function _split(n::Union{Nothing,_OTNode{K,T}}, ok::UInt128) where {K,T}
    n === nothing && return (nothing, nothing)
    if ok ≤ n.ok
        L, R = _split(n.left, ok)
        n.left = R
        _recalc!(n)
        return (L, n)
    else
        L, R = _split(n.right, ok)
        n.right = L
        _recalc!(n)
        return (n, R)
    end
end

function _insert!(root::Union{Nothing,_OTNode{K,T}}, newn::_OTNode{K,T}) where {K,T}
    root === nothing && return newn
    if newn.prio ≤ root.prio
        L, R = _split(root, newn.ok)
        newn.left, newn.right = L, R
        return _recalc!(newn)
    else
        if newn.ok < root.ok
            root.left  = _insert!(root.left,  newn)
        else
            root.right = _insert!(root.right, newn)
        end
        return _recalc!(root)
    end
end

function _erase!(n::Union{Nothing,_OTNode{K,T}}, ok::UInt128) where {K,T}
    n === nothing && return nothing
    if ok == n.ok
        return _merge(n.left, n.right)
    elseif ok < n.ok
        n.left = _erase!(n.left, ok)
    else
        n.right = _erase!(n.right, ok)
    end
    return _recalc!(n)
end

function _find(n::Union{Nothing,_OTNode{K,T}}, ok::UInt128) where {K,T}
    while n !== nothing
        if ok == n.ok; return n
        elseif ok < n.ok; n = n.left
        else;             n = n.right
        end
    end
    return nothing
end

function _update!(n::Union{Nothing,_OTNode{K,T}}, ok::UInt128, newv::T) where {K,T}
    @assert n !== nothing
    if ok == n.ok
        n.val = newv
        return _recalc!(n)
    elseif ok < n.ok
        n.left  = _update!(n.left,  ok, newv)
    else
        n.right = _update!(n.right, ok, newv)
    end
    return _recalc!(n)
end

function _choose(n::_OTNode{K,T}, x::T) where {K,T}
    while true
        ls = _lsum(n.left)
        if x < ls
            n = n.left
            continue
        end
        x -= ls
        if x < n.val
            return (n.key, n.val)
        end
        x -= n.val
        n = n.right
    end
end

# ----- Public container -----
"""
    OrderStatisticTreap{K,T}(; seed::UInt=0x9e3779b97f4a7c15, rng=Random.default_rng())

Dict-like container with prefix-sum and weighted choice.
Operations: `A[k]=v`, `delete!(A,k)`, `A[k]`, `sum!(A)`, `choose(A, u)`, `rand(rng, A)`.
"""
mutable struct OrderStatisticTreap{K,T<:Real}
    root::Union{Nothing,_OTNode{K,T}}
    key2ok::Dict{K,UInt128}
    seed::UInt
    counter::UInt64
    rng::Random.AbstractRNG
    function OrderStatisticTreap{K,T}(; seed::UInt=0x9e3779b97f4a7c15, rng=Random.default_rng()) where {K,T<:Real}
        new{K,T}(nothing, Dict{K,UInt128}(), seed, 0x0000000000000000, rng)
    end
end

Base.length(A::OrderStatisticTreap) = length(A.key2ok)
Base.keys(A::OrderStatisticTreap)   = keys(A.key2ok)
Base.empty!(A::OrderStatisticTreap) = (A.root = nothing; empty!(A.key2ok); A.counter = 0; nothing)
Base.haskey(A::OrderStatisticTreap{K,T}, k::K) where {K,T} = haskey(A.key2ok, k)

# total
sum!(A::OrderStatisticTreap{K,T}) where {K,T} =
    A.root === nothing ? zero(T) : A.root.sum

# choose: return (key, value)
function choose(A::OrderStatisticTreap{K,T}, x::T) where {K,T}
    total = sum!(A)
    if !(x < total)
        error("value $x not less than total $total")
    end
    return _choose(A.root, x)
end

# sampling integration (same shape as your other prefix structures)
Random.rand(rng::AbstractRNG, d::Random.SamplerTrivial{OrderStatisticTreap{K,T}}) where {K,T} =
    choose(d[], rand(rng, Uniform{T}(zero(T), sum!(d[]))))

# set / get / delete
function setindex!(A::OrderStatisticTreap{K,T}, v::T, k::K) where {K,T}
    if v == zero(T)
        delete!(A, k)
        return v
    end
    if haskey(A.key2ok, k)
        ok = A.key2ok[k]
        A.root = _update!(A.root, ok, v)
    else
        # stable total order: high 64 bits from hash, low 64 bits from a monotone counter
        hi = UInt64(hash(k, A.seed))
        A.counter += 1
        ok = (UInt128(hi) << 64) | UInt128(A.counter)
        A.key2ok[k] = ok
        node = _OTNode{K,T}(ok, k, v, v, rand(A.rng, UInt64), nothing, nothing)
        A.root = _insert!(A.root, node)
    end
    return v
end

function getindex(A::OrderStatisticTreap{K,T}, k::K) where {K,T}
    ok = A.key2ok[k]              # throw KeyError if absent, like KeyedRemovalPrefixSearch
    n = _find(A.root, ok)
    n === nothing && error("inconsistent: key present but node missing")
    return n.val
end

function delete!(A::OrderStatisticTreap{K,T}, k::K) where {K,T}
    if !haskey(A.key2ok, k); return A; end
    ok = A.key2ok[k]
    A.root = _erase!(A.root, ok)
    delete!(A.key2ok, k)
    return A
end

# Optional: expose an "enabled" view usable with your enabled(dc) pattern.
enabled(A::OrderStatisticTreap) = keys(A)  # all stored keys are enabled
isenabled(A::OrderStatisticTreap{K,T}, k::K) where {K,T} = haskey(A, k)
```

Usage sketch

```julia
const K = Symbol
const T = Float64

ps = OrderStatisticTreap{K,T}()  # dict-like
ps[:a] = 1.0
ps[:b] = 2.5
ps[:c] = 0.5

total = sum!(ps)                  # 4.0
k, v = choose(ps, 2.6)            # returns some key, weight by prefix
```

Direct sampler wiring
`DirectCall` only relies on `setindex!`, `delete!`, `sum!`, and `rand/choose`, so you can drop this in as the `prefix_tree` implementation. Example: 

```julia
ps = OrderStatisticTreap{K,T}()
dc = DirectCall{K,T,typeof(ps)}(ps, zero(T), 0.0, false)  # same struct, different P
```

Notes

* **Complexity.** Insert, update, delete, and `choose(u)` are O(log n) expected due to the treap heap property. The constant factor is small.
* **Stability.** The ordered key `ok` uses `hash(k, seed)` in the high 64 bits and a monotone counter in the low 64 bits for uniqueness. No ordering requirement on `K`.
* **Semantics.** Setting a weight to zero removes the key. `getindex` throws on absent keys, matching your removal wrapper style. 
* **Comparison.** Your array tree gives O(log n) with tight constants but needs dense 1…N indices. This tree handles arbitrary keys without a K→index table and keeps prefix sums current incrementally. 

If you want a red‑black version instead of a treap, the only changes are rotations and color bookkeeping; the subtree‑sum maintenance and `choose` walk are identical.
