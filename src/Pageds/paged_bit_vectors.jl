"A fixed-length bit vector whose data is stored in some manually managed region of memory."
struct PagedBitVector <: AbstractArray{Bool, 1}
    ptr::Paged{UInt64}
    length::Int64
end

struct PagedBit
    ptr::Paged{UInt64}
    mask::UInt64
end

"Create a `PagedBitVector{T}` pointing at an existing allocation"
function PagedBitVector(ptr::Ptr{Void}, length::Int64)
    PagedBitVector(Paged{UInt64}(ptr), length)
end

"Allocate a new `PagedBitVector{T}`"
function PagedBitVector(length::Int64)
    size = UInt64(ceil(length / sizeof(UInt64)))
    PagedBitVector(Paged{UInt64}(size), length)
end

function get_address(pv::PagedBitVector, i::Int)
    @assert i <= pv.length # TODO bounds check
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
