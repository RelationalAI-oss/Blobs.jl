# Implementation of adaptive packed-memory arrays [1].
#
# [1] Bender, M.A. and Hu, Haodong. 2007. An Adaptive Packed-Memory Array.
#     In ACM Transactions on Database Systems, Vol 32, Issue 4.

using Compat
using DataStructures

struct Thresholds
    r0::Float64         # Lower density thresholds
    rh::Float64
    t0::Float64         # Upper density thresholds
    th::Float64
end

const pma_default_thresholds = Thresholds(0.25, 0.50, 1.0, 0.75)
const pma_min_size = 4

# mutable struct PredictorCell{K}
#     has_key::Bool     # Avoiding union type due to https://github.com/JuliaLang/julia/issues/23567
#     key::K
#     leaf_index::Int
#     count::Int
# end
#
# predictor_size(n) = convert(Int, ceil(log2(n)))

struct TreeDimensions
    height::Int
    segment_size::Int

    function TreeDimensions(n)
        num_segments = nextpow2(convert(Int, round(n / log2(n))))
        height = convert(Int, log2(num_segments)) + 1
        segment_size = div(n, num_segments)
        new(height, segment_size)
    end
end

struct PackedMemoryArray{K,V} <: Compat.AbstractDict{K,V}
    keys::PagedVector{K}
    values::PagedVector{V}
    mask::PagedBitVector
    count::Int
    capacity::Int
    max_capacity::Int
    rts::Thresholds
    dims::TreeDimensions
    # pred::CircularBuffer{PredictorCell{K}}

    # function PackedMemoryArray{K,V}(buffersize::Int, rts::Thresholds) where {K,V}
    #     if buffersize < pma_min_size
    #         error("Buffer size must be at least $pma_min_size")
    #     end
    #
    #     n = buffersize
    #     new{K,V}(Vector{K}(n), Vector{V}(n), falses(n), 0, rts,
    #         TreeDimensions(n))
    # end
end

function Pageds.is_paged_type(x::Type{PackedMemoryArray{K,V}}) where {K,V}
    true
end

"Initializes a `PackedMemoryArray{K,V}` pointing at an existing (or fresh) allocation"
function init_pma(pma::Paged{PackedMemoryArray{K,V}}, length::Int, fresh::Bool) where {K,V}
    if fresh
        fill!((@v pma.mask), false)
        @v pma.count = 0
        @v pma.max_capacity = length
        pma_update_capacity!(pma, pma_min_size)
        @v pma.rts = pma_default_thresholds
    else
        @assert (@v pma.max_capacity) == length
    end

    pma
end

"Allocate a new `PackedMemoryArray{T}` capable of storing length elements"
function Paged{PackedMemoryArray{K,V}}(length::Int) where {K,V}
    if !ispow2(length)
        throw(ArgumentError("PackedMemoryArray length must be a power of two"))
    elseif length < pma_min_size
        throw(ArgumentError("PackedMemoryArray has minimum length $pma_min_size"))
    end
    
    pma = pagedalloc(PackedMemoryArray{K,V}, Libc.malloc,
            Val{(:keys, length)}, Val{(:values, length)} , Val{(:mask, length)})

    init_pma(pma, length, true)
end

function Paged{PackedMemoryArray{K,V}}(ptr::Ptr{Void}, length::Int) where {K,V}
    pma = pagedwire(Paged{PackedMemoryArray{K,V}}(ptr),
            Val{(:keys, length)}, Val{(:values, length)} , Val{(:mask, length)})

    init_pma(pma, length, true)
end

# function PackedMemoryArray{K,V}(rts::Thresholds, kv) where {K,V}
#     if DataStructures.not_iterator_of_pairs(kv)
#         throw(ArgumentError("PackedMemoryArray(kv): kv needs to be an iterator of tuples or pairs"))
#     end
#     p = PackedMemoryArray{K,V}(pma_min_size, rts)
#     for (k,v) in kv
#         p[k] = v
#     end
#     p
# end
#
# PackedMemoryArray{K,V}(buffersize::Int) where {K,V} =
#     PackedMemoryArray{K,V}(buffersize, pma_default_thresholds)
#
# PackedMemoryArray{K,V}(rts::Thresholds = pma_default_thresholds) where {K,V} =
#     PackedMemoryArray{K,V}(pma_min_size, rts)
#
# PackedMemoryArray{K,V}(ps::Pair{K,V}...) where {K,V} =
#     PackedMemoryArray{K,V}(pma_default_thresholds, ps)
#
# PackedMemoryArray(ps::Pair...) = pma_with_eltype(ps, eltype(ps))
#
# PackedMemoryArray(d::Compat.AbstractDict) = pma_with_eltype(d, eltype(d))
#
# pma_with_eltype(ps, ::Type{Pair{K,V}}) where {K,V} =
#     PackedMemoryArray{K,V}(pma_default_thresholds, ps)

# PackedMemoryArray{K,V}(kv) where {K,V} = PackedMemoryArray(pma_default_thresholds, kv)

function pma_maxcapacity(K, V, buffersize)
    fixed_overhead = sizeof(PackedMemoryArray{K,V})
    if fixed_overhead > buffersize
        throw(ArgumentError(("Cannot store even a 0-element PackedMemoryArray")))
    end

    element_overhead = sizeof(K) + sizeof(V) + 1/8
    capacity = convert(Int, floor((buffersize - fixed_overhead) / element_overhead))
    prevpow2(capacity)
end

function pma_lower_threshold(p::Paged{PackedMemoryArray{K,V}}, level) where {K,V}
    (@v p.rts.rh) - ((@v p.rts.rh) - (@v p.rts.r0)) *
        ((@v p.dims.height) - level) / (@v p.dims.height)
end

function pma_upper_threshold(p::Paged{PackedMemoryArray{K,V}}, level) where {K,V}
    (@v p.rts.th) + ((@v p.rts.t0) - (@v p.rts.th)) *
        ((@v p.dims.height) - level) / (@v p.dims.height)
end

"""
Finds a valid index near the midpoint of the open interval (left,right).
Returns 0 if no valid index found.
"""
function pma_find_midpoint(p::Paged{PackedMemoryArray{K,V}}, left, right) where {K,V}
    if left < right-1
        c = left + div(right-left, 2)
        @assert c > left && c < right
        n = findnext((@v p.mask), c)
        if n > 0 && n < right
            return n
        end
        p = findprev((@v p.mask), c)
        if p > 0 && p > left
            return p
        end
    end
    return 0
end

function pma_find_glb(p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    left = 0
    right = (@v p.capacity) + 1
    best = 0
    last = abs(right-left)
    while left < right-1
        c = pma_find_midpoint(p, left, right)
        if c == 0
            break
        elseif (@v p.keys[c]) ≤ key
            best = c
            left = c
        else
            right = c
        end
        @assert abs(right-left) < last
        last = abs(right-left)
    end
    return best
end

function pma_find_exact(p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    i = pma_find_glb(p, key)
    if i != 0 && (@v p.keys)[i] == key
        return i
    end
    return 0
end

struct Window
    left::Int
    right::Int
end

function pma_find_window(p::Paged{PackedMemoryArray{K,V}}, i, level) where {K,V}
    size = (@v p.dims.segment_size) * (1 << (level-1))
    start = size * div(i-1, size)
    Window(start+1, start+size)
end

function popcount(a::PagedBitVector, window)
    # NOTE: placeholder implementation, could rewrite using count_ones which
    # exploits popcount instruction, but this means relying on internal details
    # of the BitVector implementation and is also fiddly, so punting until
    # we have evidence that there is a bottleneck here.
    #
    # NOTE: the more straightfoward placeholder implementation
    #
    #    reduce(+, a[window.left:window.right])
    #
    # yields a heap allocation due to the splice operator.
    count=0
    for i in window.left:window.right
        @inbounds count += a[i]
    end
    count
end

cap(window::Window) = window.right - window.left + 1

function pma_density(p::Paged{PackedMemoryArray{K,V}}, window) where {K,V}
    load = popcount((@v p.mask), window)
    capacity = cap(window)
    load / capacity
end

function pma_move_item!(p::Paged{PackedMemoryArray{K,V}}, dst, src) where {K,V}
    @v p.keys[dst] = @v p.keys[src]
    @v p.values[dst] = @v p.values[src]
    @v p.mask[src] = false
    @v p.mask[dst] = true
end

# function find_marker(p::PackedMemoryArray, i)
#     testfun = (i == 0) ? (x -> !x.has_key) :
#         (x -> x.has_key && x.key == p.keys[i])
#
#     key = p.keys[i]
#     for (i, cell) in enumerate(p.pred)
#         if testfun(cell)
#             return i
#         end
#     end
#     return 0
# end
#
# pred_max(p::PackedMemoryArray) = p.dims.height    # i.e., log_2(p.capacity)
#
# function update_predictor!(p::PackedMemoryArray, ins_index)
#     (x,y) = (ins_index-1, ins_index)
#     pred = p.pred
#     xm = find_marker(p, x)
#     if xm != 0
#         if xm != 1
#             (pred[xm-1], pred[xm]) = (pred[xm], pred[xm-1])
#             xm -= 1
#         end
#         if pred[xm].count < pred_max(p)
#             pred[xm].count += 1
#         else
#             pred[end].count -= 1
#         end
#     elseif length(pred) == capacity(pred)
#         pred[end].count -= 1
#     else
#         leaf_index = find_window(p, ins_index, 1).left
#         unshift!(pred, PredictorCell(p.keys[y]), left_index, 1)
#     end
#
#     if pred[end].count == 0
#         pop!(pred)
#     end
# end

function pma_pack_left!(p::Paged{PackedMemoryArray{K,V}}, window) where {K,V}
    count = 0
    dst = window.left
    for src in window.left:window.right
        if (@v p.mask[src])
            pma_move_item!(p, dst, src)
            dst += 1
        end
    end
    dst - window.left
end

function pma_spread_right!(p::Paged{PackedMemoryArray{K,V}}, window, count) where {K,V}
    moved = 0
    spacing = cap(window)/count
    for src in window.right:-1:window.left
        if (@v p.mask[src])
            dst = window.right - convert(Int, round(moved*spacing))
            pma_move_item!(p, dst, src)
            moved += 1
        end
    end
end

function pma_sweep!(p::Paged{PackedMemoryArray{K,V}}, window) where {K,V}
    count = pma_pack_left!(p, window)
    pma_spread_right!(p, window, count)
end

function pma_update_capacity!(p::Paged{PackedMemoryArray{K,V}}, length::Int) where {K,V}
    @v p.capacity = length
    @v p.dims = TreeDimensions(length)
    @v p.keys.length = length
    @v p.values.length = length
    @v p.mask.length = length
end

function pma_grow_or_shrink!(p::Paged{PackedMemoryArray{K,V}}, grow::Bool) where {K,V}
    old_size = @v p.capacity
    if grow
        new_size = old_size*2
        if new_size > (@v p.max_capacity)
            error("Maximum capacity limited to $(@v p.max_capacity)")
        end
    else
        if old_size == pma_min_size
            return
        end
        new_size = div(old_size,2)
    end

    pma_pack_left!(p, Window(1, old_size))
    pma_update_capacity!(p, new_size)
    # p.pred = CircularBuffer{PredictorCell{K}}(predictor_size(new_size))

    if grow
        for i in (old_size+1):new_size
            @v p.mask[i] = false
        end
    end

    pma_spread_right!(p, Window(1, new_size), @v p.count)
end

# function uneven_rebalance!(p::PackedMemoryArray, after_insert::Bool)
#
# end

function pma_rebalance!(p::Paged{PackedMemoryArray{K,V}}, i, after_insert::Bool) where {K,V}
    for level in 1:(@v p.dims.height)
        window = pma_find_window(p, i, level)
        d = pma_density(p, window)
        if (after_insert && d ≤ pma_upper_threshold(p, level)) ||
           (!after_insert && pma_lower_threshold(p, level) ≤ d)
            if level == 1
                return  # We're good
            else
                pma_sweep!(p, window)
                return
            end
        end
    end

    # Root node is out of threshold; need to resize entire PackedMemoryArray
    if (!after_insert || (@v p.capacity) < (@v p.max_capacity))
        pma_grow_or_shrink!(p, after_insert)
    end
end

function memmove!(dst, doff, src, soff, len)
    # Three cases are possible:
    #
    #  1. The ranges are for different vectors or don't overlap.
    #  2. The ranges overlap, with dst to the right of src
    #  3. The ranges overlap, with dst to the left of src
    #  4. The ranges exactly coincide.
    #
    # For case 2, we copy right-to-left.  For case 3, we copy left-to-right.
    # For cases 1 and 4, it doesn't matter which order we copy.

    # NOTE: we should be able to use copyto! instead of this function
    # pending resolution of https://github.com/JuliaLang/julia/issues/25968
    range = doff < soff ? (1:len) : (len:-1:1)
    for i in range
        dst[doff+i-1] = src[soff+i-1]
    end
end

function pma_bump!(p::Paged{PackedMemoryArray{K,V}}, doff, soff, len) where {K,V}
    copy!((@v p.keys), doff, (@v p.keys), soff, len)
    copy!((@v p.values), doff, (@v p.values), soff, len)
    memmove!((@v p.mask), doff, (@v p.mask), soff, len)
end

function pma_insert_at!(p::Paged{PackedMemoryArray{K,V}}, i, key, value) where {K,V}
    @v p.keys[i] = key
    @v p.values[i] = value
    @v p.mask[i] = true
end

function pma_insert_after!(p::Paged{PackedMemoryArray{K,V}}, i, key, value) where {K,V}
    @assert 0 ≤ i ≤ (@v p.capacity)
    # Search for empty space to the right of i
    j = Base.findnextnot((@v p.mask), i+1)
    if j ≠ 0
        pma_bump!(p, i+2, i+1, j-(i+1))
        pma_insert_at!(p, i+1, key, value)
        # update_predictor!(p, i+1)
    else
        # There must be empty space to the left of i
        j = Base.findprevnot((@v p.mask), i)
        pma_bump!(p, j, j+1, i-j)
        pma_insert_at!(p, i, key, value)
        # update_predictor!(p, i)
    end

    @v p.count = (@v p.count) + 1

    pma_rebalance!(p, i, true)
end

function maxlength(p::Paged{PackedMemoryArray{K,V}}) where {K,V}
    @v p.max_capacity
end

# AbstractDict methods (don't forget get(dict, key, default); haskey())
# import Base: haskey, get, get!, getkey, delete!, push!, pop!, empty!,
#              setindex!, getindex, length, isempty, start,
#              next, done, keys, values, setdiff, setdiff!,
#              union, union!, intersect, filter, filter!,
#              hash, eltype, ValueIterator, convert, copy,
#              merge
#
# import Base: , , , , , , , ,
#              , , , , ,
#              , , keys, values, setdiff, setdiff!,
#              union, union!, intersect, filter, filter!,
#              hash, , ValueIterator, convert, copy,
#              merge

function Base.get(f::Function, p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    i = pma_find_exact(p, key)
    if i == 0
        f()
    else
        @v p.values[i]
    end
end

function Base.get!(f::Function, p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    i = find_exact(p, key)
    if i == 0
        value = f()
        setindex!(p, key, value)
        value
    else
        @v p.values[i]
    end
end

Base.getkey(p::PackedMemoryArray{K,V}, key, default) where {K,V} =
    Base.get(p, key, () -> default)

function Base.setindex!(p::Paged{PackedMemoryArray{K,V}}, value, key) where {K,V}
    i = pma_find_glb(p, key)
    if i > 0 && (@v p.keys[i]) == key
        @v p.values[i] = value
    elseif (@v p.count) < (@v p.max_capacity)
        pma_insert_after!(p, i, key, value)
    else
        error("Maximum capacity limited to $(@v p.max_capacity)")
    end
    p
end

function Base.delete!(p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    i = pma_find_exact(p, key)
    if i != 0
        @v p.mask[i] = false
        @v p.count = (@v p.count) - 1
        pma_rebalance!(p, i, false)
    end
    p
end

function Base.getindex(p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    i = pma_find_exact(p, key)
    if i == 0
        throw(KeyError(key))
    end
    @v p.values[i]
end

function Base.haskey(p::Paged{PackedMemoryArray{K,V}}, key) where {K,V}
    pma_find_exact(p, key) != 0
end

Base.isempty(p::Paged{PackedMemoryArray{K,V}}) where {K,V} = (@v p.count) == 0

Base.push!(p::Paged{PackedMemoryArray{K,V}}, kv) where {K,V} =
    Base.setindex!(p, kv[2], kv[1])

# Custom iterator
Base.start(p::Paged{PackedMemoryArray{K,V}}) where {K,V} =
    findnext((@v p.mask), 1)
Base.next(p::Paged{PackedMemoryArray{K,V}}, state) where {K,V} =
    ((@v p.keys[state]) => (@v p.values[state])), findnext((@v p.mask), state+1)
Base.done(p::Paged{PackedMemoryArray{K,V}}, state) where {K,V} = state == 0
Base.eltype(::Type{Paged{PackedMemoryArray{K,V}}}) where {K,V} = Pair{K,V}
Base.length(p::Paged{PackedMemoryArray{K,V}}) where {K,V} = @v p.count
# Base.convert(::Type{Array}, p::Paged{PackedMemoryArray{K,V}}{K,V}) where {K,V} =
#     Pair{K,V}[kv for kv in p]

function Base.empty!(p::Paged{PackedMemoryArray{K,V}}) where {K,V}
    pma_update_capacity!(p, pma_min_size)
    fill!((@v p.mask), false)
    @v p.count = 0
    # p.pred = CircularBuffer{PredictorCell}(predictor_size(n))
    p
end

function showfirst(io::IO, p::Paged{PackedMemoryArray{K,V}}, count) where {K,V}
    shown = 0
    for kv in p
        print(io, "\n $kv")
        shown += 1
        if shown > count
            break
        end
    end
end

function showlast(io::IO, p::Paged{PackedMemoryArray{K,V}}, count) where {K,V}
    mask = @v p.mask
    kvs = Vector{Pair{K,V}}()
    i = (@v p.capacity) + 1
    while count > 0
        i = Base.findprev(mask, i-1)
        if i == 0
            break
        else
            push!(kvs, Pair{K,V}((@v p.keys)[i], (@v p.values)[i]))
            count -= 1
        end
    end
    for i in length(kvs):-1:1
        print(io, "\n $(kvs[i])")
    end
end

function Base.show(io::IO, p::Paged{PackedMemoryArray{K,V}}) where {K,V}
    print(io, "$(@v p.count)-element PackedMemoryArray{$K,$V} (with $(@v p.max_capacity)-element max capacity))")
    if (@v p.count) == 0
        return
    end
    print(io, ":")
    if (@v p.count) > 30
        showfirst(io, p, 20)
        print(io, "\n     ⋮")
        showlast(io, p, 10)
    else
        showfirst(io, p, (@v p.count))
    end
end
