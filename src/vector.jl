"A fixed-length vector whose data is stored in a Blob."
struct BlobVector{T} <: AbstractArray{T, 1}
    data::Blob{T}
    length::Int64

    function BlobVector{T}(data::Blob{T}, length::Int64) where {T}
        @assert isbits(T)
        new(data, length)
    end
end

@inline function get_address(blob::BlobVector{T}, i::Int) where {T}
    (0 < i <= blob.length) || throw(BoundsError(blob, i))
    blob.data + (i-1)*sizeof(T)
end

function get_address(blob::Blob{BlobVector{T}}, i::Int) where {T}
    get_address(unsafe_load(blob), i)
end

# array interface

function Base.size(blob::BlobVector)
    (blob.length,)
end

@inline function Base.getindex(blob::BlobVector{T}, i::Int) where {T}
    unsafe_load(get_address(blob, i))
end

@inline function Base.setindex!(blob::BlobVector{T}, v, i::Int) where {T}
    unsafe_store!(get_address(blob, i), v)
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
