"A fixed-length vector whose data is stored in some manually managed region of memory."
struct ManualVector{T} <: AbstractArray{T, 1}
    ptr::Manual{T}
    length::Int64

    function ManualVector{T}(ptr::Manual{T}, length::Int64) where {T}
        @assert isbits(T)
        new(ptr, length)
    end
end

@inline function get_address(pv::ManualVector{T}, i::Int) where {T}
    (0 < i <= pv.length) || throw(BoundsError(pv, i))
    Manual{T}(pv.ptr.ptr + (i-1)*sizeof(T))
end

function get_address(pv::Manual{ManualVector{T}}, i::Int) where {T}
    get_address(unsafe_load(pv), i)
end

# array interface

function Base.size(pv::ManualVector)
    (pv.length,)
end

@inline function Base.getindex(pv::ManualVector{T}, i::Int) where {T}
    unsafe_load(get_address(pv, i))
end

@inline function Base.setindex!(pv::ManualVector{T}, v, i::Int) where {T}
    unsafe_store!(get_address(pv, i), v)
end

function Base.IndexStyle(_::Type{ManualVector{T}}) where {T}
    Base.IndexLinear()
end

# copying, with correct handling of overlapping regions
# TODO use memcopy
function Base.copy!(dest::ManualVector{T}, doff::Int, src::ManualVector{T},
    soff::Int, n::Int) where {T}
    if doff < soff
        for i in 0:n-1 dest[doff+i] = src[soff+i] end
    else
        for i in n-1:-1:0 dest[doff+i] = src[soff+i] end
    end
end
