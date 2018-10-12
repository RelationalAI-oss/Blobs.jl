struct BlobBit
    data::Blob{UInt64}
    mask::UInt64
end

@inline Base.@propagate_inbounds function Base.getindex(blob::BlobBit)::Bool
    blob_data = blob.data
    ((@v blob_data) & blob.mask) != 0
end

@inline Base.@propagate_inbounds function Base.setindex!(blob::BlobBit, v::Bool)::Bool
    blob_data = blob.data
    c = @v blob_data
    c = ifelse(v, c | blob.mask, c & ~blob.mask)
    @v blob_data = c
    v
end

"A fixed-length bit vector whose data is stored in a Blob."
struct BlobBitVector <: AbstractArray{Bool, 1}
    data::Blob{UInt64}
    length::Int64
end

@inline Base.@propagate_inbounds function get_address(blob::BlobBitVector, i::Int)::BlobBit
    # @boundscheck begin
    #     (i < 1 || i > blob.length) && throw(BoundsError(blob, i))
    # end
    i1, i2 = Base.get_chunks_id(i)
    BlobBit(Blob{UInt64}(blob.data + (i1-1)*self_size(UInt64)), UInt64(1) << i2)
end

# blob interface

@inline function Base.size(blob::Blob{BlobBitVector})
    ((@v blob.length),)
end

@inline function Base.IndexStyle(_::Type{Blob{BlobBitVector}})
    Base.IndexLinear()
end

@inline Base.@propagate_inbounds function Base.getindex(blob::Blob{BlobBitVector}, i::Int)::BlobBit
    get_address((@v blob), i)
end

@inline function unsafe_resize!(blob::BlobBitVector, length::Int64)
    blob_len = blob.length
    @v blob_len = length
end

# array interface

@inline function Base.size(blob::BlobBitVector)
    (blob.length,)
end

@inline function Base.IndexStyle(_::Type{BlobBitVector})
    Base.IndexLinear()
end

@inline Base.@propagate_inbounds function Base.getindex(blob::BlobBitVector, i::Int)::Bool
    get_address(blob, i)[]
end

@inline Base.@propagate_inbounds function Base.setindex!(blob::BlobBitVector, v::Bool, i::Int)::Bool
    get_address(blob, i)[] = v
end

@inline function Base.findprevnot(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > length(blob) && throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start > 0 && blob[start]
        start -= 1
    end
    start > 0 ? start : nothing
end

@inline function Base.findnextnot(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > 0 || throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start <= length(blob) && blob[start]
        start += 1
    end
    start <= length(blob) ? start : nothing
end

@inline function Base.findnext(blob::BlobBitVector, start::Int)::Union{Nothing,Int}
    start > 0 || throw(BoundsError(blob, start))
    # TODO(tjgreen) placeholder slow implementation; should adapt optimized BitVector code
    @inbounds while start <= length(blob) && !blob[start]
        start += 1
    end
    start <= length(blob) ? start : nothing
end
