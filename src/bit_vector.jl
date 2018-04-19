"A fixed-length bit vector whose data is stored in a Blob."
struct BlobBitVector <: AbstractArray{Bool, 1}
    data::Blob{UInt64}
    length::Int64

    function BlobBitVector(data::Blob{UInt64}, length::Int64)
        blob = new(data, length)
        get_address(blob, length) # bounds check
        blob
    end
end

struct BlobBit
    data::Blob{UInt64}
    mask::UInt64
end

function get_address(blob::BlobBitVector, i::Int)
    (i < 1 || i > blob.length) && throw(BoundsError(blob, i))
    i1, i2 = Base.get_chunks_id(i)
    BlobBit(blob.data + (i1-1)*sizeof(UInt64), UInt64(1) << i2)
end

function get_address(blob::Blob{BlobBitVector}, i::Int)
    get_address(unsafe_load(blob), i)
end

function Base.unsafe_load(blob::BlobBit)
    (unsafe_load(blob.data) & blob.mask) != 0
end

function Base.unsafe_store!(blob::BlobBit, v::Bool)
    c = unsafe_load(blob.data)
    c = ifelse(v, c | blob.mask, c & ~blob.mask)
    unsafe_store!(blob.data, c)
end

function unsafe_resize!(blob::BlobBitVector, length::Int64)
    @v blob.length = length
end

# array interface

function Base.size(blob::BlobBitVector)
    (blob.length,)
end

function Base.getindex(blob::BlobBitVector, i::Int)
    unsafe_load(get_address(blob, i))
end

function Base.setindex!(blob::BlobBitVector, v::Bool, i::Int)
    unsafe_store!(get_address(blob, i), v)
end

function Base.IndexStyle(_::Type{BlobBitVector})
    Base.IndexLinear()
end

function Base.findprevnot(blob::BlobBitVector, start::Int)
    start > 0 || return 0
    start > length(blob) && throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start > 0 && blob[start]
        start -= 1
    end
    start
end

function Base.findnextnot(blob::BlobBitVector, start::Int)
    start > 0 || throw(BoundsError(blob, start))
    start > length(blob) && return 0
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start < length(blob) && blob[start]
        start += 1
    end
    start
end
