"A fixed-length bit vector whose data is stored in some manually managed region of memory."
struct PagedBitVector <: AbstractArray{Bool, 1}
    ptr::Paged{UInt64}
    length::Int64
end

struct PagedBit
    ptr::Paged{UInt64}
    mask::UInt64
end

"Create a `PagedBitVector` pointing at an existing allocation"
function PagedBitVector(ptr::Ptr{Void}, length::Int64)
    PagedBitVector(Paged{UInt64}(ptr), length)
end

function Pageds.is_paged_type(x::Type{PagedBitVector})
    true
end

function Base.sizeof(x::Type{PagedBitVector}, length::Int64)
    UInt64(ceil(length / sizeof(UInt64)))
end

"Allocate a new `PagedBitVector`"
function PagedBitVector(length::Int64)
    size = sizeof(PagedBitVector, length)
    PagedBitVector(Paged{UInt64}(size), length)
end

function get_address(pv::PagedBitVector, i::Int)
    (i < 1 || i > pv.length) && throw(BoundsError(pv, i))
    i1, i2 = Base.get_chunks_id(i)
    PagedBit(Paged{UInt64}(pv.ptr.ptr + (i1-1)*sizeof(UInt64)), UInt64(1) << i2)
end

function get_address(pv::Paged{PagedBitVector}, i::Int)
    get_address(unsafe_load(pv), i)
end

function Base.unsafe_load(pb::PagedBit)
    (unsafe_load(pb.ptr) & pb.mask) != 0
end

function Base.unsafe_store!(pb::PagedBit, v::Bool)
    c = unsafe_load(pb.ptr)
    c = ifelse(v, c | pb.mask, c & ~pb.mask)
    unsafe_store!(pb.ptr, c)
end

function unsafe_resize!(pb::PagedBitVector, length::Int64)
    @v pb.length = length
end

function Base.findprevnot(pb::PagedBitVector, start::Int)
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

function Base.findnextnot(pb::PagedBitVector, start::Int)
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

function Base.size(pv::PagedBitVector)
    (pv.length,)
end

function Base.getindex(pv::PagedBitVector, i::Int)
    unsafe_load(get_address(pv, i))
end

function Base.setindex!(pv::PagedBitVector, v::Bool, i::Int)
    unsafe_store!(get_address(pv, i), v)
end

function Base.IndexStyle(_::Type{PagedBitVector})
    Base.IndexLinear()
end
