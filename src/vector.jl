"A fixed-length vector whose data is stored in some manually managed region of memory."
struct BlobVector{T} <: AbstractArray{T, 1}
    ptr::Blob{T}
    length::Int64

    function BlobVector{T}(ptr::Blob{T}, length::Int64) where {T}
        @assert isbits(T)
        new(ptr, length)
    end
end

@inline function get_address(pv::BlobVector{T}, i::Int) where {T}
    (0 < i <= pv.length) || throw(BoundsError(pv, i))
    Blob{T}(pv.ptr.ptr + (i-1)*sizeof(T))
end

function get_address(pv::Blob{BlobVector{T}}, i::Int) where {T}
    get_address(unsafe_load(pv), i)
end

# array interface

function Base.size(pv::BlobVector)
    (pv.length,)
end

@inline function Base.getindex(pv::BlobVector{T}, i::Int) where {T}
    unsafe_load(get_address(pv, i))
end

@inline function Base.setindex!(pv::BlobVector{T}, v, i::Int) where {T}
    unsafe_store!(get_address(pv, i), v)
end

function Base.IndexStyle(_::Type{BlobVector{T}}) where {T}
    Base.IndexLinear()
end

# copying, with correct handling of overlapping regions
# TODO use memcopy
function Base.copy!(dest::BlobVector{T}, doff::Int, src::BlobVector{T},
    soff::Int, n::Int) where {T}
    if doff < soff
        for i in 0:n-1 dest[doff+i] = src[soff+i] end
    else
        for i in n-1:-1:0 dest[doff+i] = src[soff+i] end
    end
end
