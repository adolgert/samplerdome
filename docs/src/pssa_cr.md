Here is a drop‑in **PSSA‑CR** sampler that matches your sampler interface. It is exact, continuous‑time, and expects **Exponential** clocks. It uses two‑stage **composition–rejection** selection over groups, with an idempotent `next` that caches one candidate until `fire!`, `enable!`, `disable!`, or `jitter!` invalidates it. 

**Download:** [pssa_cr.jl](sandbox:/mnt/data/pssa_cr.jl)

### What it implements

* Same API shape as your example: `next`, `enable!`, `fire!`, `disable!`, `reset!`, `clone`, `copy_clocks!`, `jitter!`, `getindex`, `keys`, `length`, `haskey`. 
* Time to next event: (\Delta t \sim \mathrm{Exp}(a_0)) with (a_0=\sum_k \lambda_k).
* Channel selection: pick a **group** with probability proportional to its rate sum, then pick a **reaction within the group** by **rejection** with acceptance (\lambda/\lambda_{\max,\text{group}}). This is the PSSA‑CR composition–rejection pattern over partials; if you supply owner‑style grouping, you get the expected O(1) behavior. Exactness follows from standard CR/SSA theory.

### How to use

```julia
# Construct for your key and time types
sampler = PSSACRSampler.PSSACR{Int,Float64}(; ngroups=64)

# Optional: place related clocks into the same group before enabling
PSSACRSampler.assign_group!(sampler, 7, 3)   # clock 7 → group 3

# Enable or update clocks (Exponential only)
enable!(sampler, 7, Exponential(1/2.3), 0.0, t, rng)   # rate λ=2.3
enable!(sampler, 9, Exponential(1/1.1), 0.0, t, rng)

# Query next without consuming it
(tnext, k) = next(sampler, t, rng)

# After you fire it in your model, invalidate cache
fire!(sampler, k, tnext)

# Update affected clocks via enable!/disable! as usual
```

### Notes

* **Exactness:** Continuous‑time and rejection‑free in time; CR inside groups preserves the correct categorical distribution over channels. This matches the PSSA‑CR construction (partial‑propensity view) and the earlier SSA‑CR foundation.
* **Performance knobs:** Set `ngroups` and group clocks that share an “owner” (e.g., first reactant) to keep (\lambda_{\max}/\text{mean}) small per group. That reproduces the partial‑propensity efficiency profile.
* **Scope:** This sampler accepts **Exponential** hazards only. For non‑exponential clocks, keep using your `FirstToFire`. PSSA‑CR targets mass‑action CTMCs.

### References

PSSA‑CR and partial‑propensity family: Ramaswamy & Sbalzarini (2010, 2011). SSA‑CR foundation: Slepoy et al. (2008). Comparative discussions: Thanh et al. (2015–2017).

If you want me to tune the default grouping or add an alias‑based inner selection for small groups, say so and I will ship a variant.
