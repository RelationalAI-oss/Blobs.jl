
"""
A fixed-length bit vector whose data is stored in some manually managed region of memory.

Note that currently if a `PagedVector` is itself stored in a `Paged` you must dereference it before using it as an array.

    # broken
    @paged p.v[3] = false

    # works
    v = @paged p.v[]
    v[3] = false

    # works
    (@paged p.v[])[3] = false
"""
struct PagedBitVector <: AbstractArray{Bool, 1}
    ptr::Paged{UInt64}
    length::Int64
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

function Base.size(pv::PagedBitVector)
    (pv.length,)
end

function Base.getindex(pv::PagedBitVector, i::Int)
    @assert i <= pv.length # TODO bounds check
    ptr = convert(Ptr{UInt64}, pv.ptr.ptr)
    i1, i2 = Base.get_chunks_id(i)
    u = UInt64(1) << i2
    (unsafe_load(ptr, i1) & u) != 0
end

function Base.setindex!(pv::PagedBitVector, v::Bool, i::Int)
    @assert i <= pv.length # TODO bounds check
    ptr = convert(Ptr{UInt64}, pv.ptr.ptr)
    i1, i2 = Base.get_chunks_id(i)
    u = UInt64(1) << i2
    c = unsafe_load(ptr, i1)
    c = ifelse(v, c | u, c & ~u)
    unsafe_store!(ptr, c, i1)
end

function Base.IndexStyle(_::Type{PagedBitVector})
    Base.IndexLinear()
end
