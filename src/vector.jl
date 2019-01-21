"A fixed-length vector whose data is stored in a Blob."
struct BlobVector{T} <: AbstractArray{T, 1}
    data::Blob{T}
    length::Int64
end

function get_address(blob::BlobVector{T}, i::Int)::Blob{T} where T
    @boundscheck begin
        (0 < i <= blob.length) || throw(BoundsError(blob, i))
    end
    blob.data + (i-1)*self_size(T)
end

# blob interface

function Base.size(blob::Blob{BlobVector})
    (blob.length[],)
end

function Base.IndexStyle(_::Type{Blob{BlobVector{T}}}) where T
    Base.IndexLinear()
end

function Base.getindex(blob::Blob{BlobVector{T}}, i::Int)::Blob{T} where T
    get_address(blob[], i)
end

# array interface

function Base.size(blob::BlobVector)
    (blob.length,)
end

function Base.IndexStyle(_::Type{BlobVector{T}}) where T
    Base.IndexLinear()
end

function Base.getindex(blob::BlobVector{T}, i::Int)::T where T
    get_address(blob, i)[]
end

function Base.setindex!(blob::BlobVector{T}, v, i::Int)::T where T
    get_address(blob, i)[] = v
end

# copying, with correct handling of overlapping regions
# TODO use memcopy
function Base.copy!(dest::BlobVector{T}, doff::Int, src::BlobVector{T}, soff::Int, n::Int) where T
    if doff < soff
        for i in 0:n-1 dest[doff+i] = src[soff+i] end
    else
        for i in n-1:-1:0 dest[doff+i] = src[soff+i] end
    end
end

# iterate interface

function Base.iterate(blob::BlobVector, i=1)
    (i % UInt) - 1 < length(blob) ? (@inbounds blob[i], i + 1) : nothing
end
