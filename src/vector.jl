"A fixed-length vector whose data is stored in a Blob."
struct BlobVector{T} <: AbstractArray{T, 1}
    data::Blob{T}
    length::Int64

    function BlobVector{T}(data::Blob{T}, length::Int64) where T
        @assert length >= 0
        @boundscheck begin
            if length * self_size(T) > allocated_size
                throw(InvalidBlobError(
                    BlobVector{T}, getfield(data, :base), getfield(data, :offset),
                    getfield(data, :limit), length),
                )
            end
        end
        new{T}(data, length)
    end
end

function Base.pointer(bv::BlobVector{T}, i::Integer=1) where {T}
    return get_address(bv, i)
end

Base.@propagate_inbounds function get_address(blob::BlobVector{T}, i::Int)::Blob{T} where T
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

Base.@propagate_inbounds function Base.getindex(blob::Blob{BlobVector{T}}, i::Int)::Blob{T} where T
    get_address(blob[], i)
end

# array interface

function Base.size(blob::BlobVector)
    (blob.length,)
end

function Base.IndexStyle(_::Type{BlobVector{T}}) where T
    Base.IndexLinear()
end

Base.@propagate_inbounds function Base.getindex(blob::BlobVector{T}, i::Int)::T where T
    get_address(blob, i)[]
end

Base.@propagate_inbounds function Base.setindex!(blob::BlobVector{T}, v, i::Int)::T where T
    get_address(blob, i)[] = v
end

# copying, with correct handling of overlapping regions
function Base.copy!(
    dest::BlobVector{T}, doff::Int, src::BlobVector{T}, soff::Int, n::Int
) where T
    @boundscheck begin
        if doff < 1 || doff + n - 1 > length(dest)
            throw(BoundsError(dest, doff:doff+n-1))
        elseif soff < 1 || soff + n - 1 > length(src)
            throw(BoundsError(src, soff:soff+n-1))
        end
    end
    # Use memmove for speedy copying. Note: this correctly handles overlapping regions.
    blob_size = Blobs.self_size(T)
    ccall(
        :memmove,
        Ptr{Cvoid},
        (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
        Base.pointer(dest.data) + (doff - 1) * blob_size,
        Base.pointer(src.data) + (soff - 1) * blob_size,
        n * blob_size,
    )
end

# iterate interface

@inline function Base.iterate(blob::BlobVector, i=1)
    (i % UInt) - 1 < length(blob) ? (@inbounds blob[i], i + 1) : nothing
end
