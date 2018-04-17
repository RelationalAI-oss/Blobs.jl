"A fixed-length bit vector whose data is stored in some manually managed region of memory."
struct ManualBitVector <: AbstractArray{Bool, 1}
    ptr::Manual{UInt64}
    length::Int64
end

struct ManualBit
    ptr::Manual{UInt64}
    mask::UInt64
end

function get_address(pv::ManualBitVector, i::Int)
    (i < 1 || i > pv.length) && throw(BoundsError(pv, i))
    i1, i2 = Base.get_chunks_id(i)
    ManualBit(Manual{UInt64}(pv.ptr.ptr + (i1-1)*sizeof(UInt64)), UInt64(1) << i2)
end

function get_address(pv::Manual{ManualBitVector}, i::Int)
    get_address(unsafe_load(pv), i)
end

function Base.unsafe_load(pb::ManualBit)
    (unsafe_load(pb.ptr) & pb.mask) != 0
end

function Base.unsafe_store!(pb::ManualBit, v::Bool)
    c = unsafe_load(pb.ptr)
    c = ifelse(v, c | pb.mask, c & ~pb.mask)
    unsafe_store!(pb.ptr, c)
end

function unsafe_resize!(pb::ManualBitVector, length::Int64)
    @v pb.length = length
end

function Base.findprevnot(pb::ManualBitVector, start::Int)
    start > 0 || return 0
    start > length(pb) && throw(BoundsError(pb, start))

    # TODO placeholder slow implementation; should adapt optimized
    # BitVector code

    @inbounds while start > 0 && pb[start]
        start -= 1
    end

    start

    # Bc = B.chunks
    #
    # chunk_start = Base._div64(start-1)+1
    # mask = ~Base._msk_end(start)
    #
    # @inbounds begin
    #     if Bc[chunk_start] | mask != _msk64
    #         return (chunk_start-1) << 6 + (64 - leading_ones(Bc[chunk_start] | mask))
    #     end
    #
    #     for i = chunk_start-1:-1:1
    #         if Bc[i] != _msk64
    #             return (i-1) << 6 + (64 - leading_ones(Bc[i]))
    #         end
    #     end
    # end
    # return 0
end

function Base.findnextnot(pb::ManualBitVector, start::Int)
    start > 0 || throw(BoundsError(pb, start))
    start > length(pb) && return 0

    # TODO placeholder slow implementation; should adapt optimized
    # BitVector code

    @inbounds while start < length(pb) && pb[start]
        start += 1
    end

    start
end

# array interface

function Base.size(pv::ManualBitVector)
    (pv.length,)
end

function Base.getindex(pv::ManualBitVector, i::Int)
    unsafe_load(get_address(pv, i))
end

function Base.setindex!(pv::ManualBitVector, v::Bool, i::Int)
    unsafe_store!(get_address(pv, i), v)
end

function Base.IndexStyle(_::Type{ManualBitVector})
    Base.IndexLinear()
end
