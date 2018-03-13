"""
A fixed-length vector whose data is stored in some manually managed region of memory.

Note that currently if a `PagedVector` is itself stored in a `Paged` you must dereference it before using it as an array.

    # broken
    @paged p.v[3] = 42

    # works
    v = @paged p.v[]
    v[3] = 42

    # works
    (@paged p.v[])[3] = 42
"""
struct PagedVector{T} <: AbstractArray{T, 1}
    ptr::Paged{T}
    length::Int64

    function PagedVector{T}(ptr::Paged{T}, length::Int64) where {T}
        @assert isbits(T)
        new(ptr, length)
    end
end

"Create a `PagedVector{T}` pointing at an existing allocation"
function PagedVector{T}(ptr::Ptr{Void}, length::Int64) where {T}
    PagedVector{T}(Paged{T}(ptr), length)
end

"Allocate a new `PagedVector{T}`"
function PagedVector{T}(length::Int64) where {T}
    PagedVector{T}(Paged{T}(length * sizeof(T)), length)
end

function Base.size(pv::PagedVector)
    (pv.length,)
end

@inline function Base.getindex(pv::PagedVector{T}, i::Int) where {T}
    @assert i <= pv.length # TODO bounds check
    unsafe_load(convert(Ptr{T}, pv.ptr.ptr), i)
end

@inline function Base.setindex!(pv::PagedVector{T}, v, i::Int) where {T}
    @assert i <= pv.length # TODO bounds check
    unsafe_store!(convert(Ptr{T}, pv.ptr.ptr), v, i)
end

function Base.IndexStyle(_::Type{PagedVector{T}}) where {T}
    Base.IndexLinear()
end
