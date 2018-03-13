"A fixed-length vector whose data is stored in some manually managed region of memory."
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

@inline function get_address(pv::PagedVector{T}, i::Int) where {T}
    @assert i <= pv.length # TODO bounds check
    Paged{T}(pv.ptr.ptr + (i-1)*sizeof(T))
end

function get_address(pv::Paged{PagedVector{T}}, i::Int) where {T}
    get_address(unsafe_load(pv), i)
end

# array interface

function Base.size(pv::PagedVector)
    (pv.length,)
end

@inline function Base.getindex(pv::PagedVector{T}, i::Int) where {T}
    unsafe_load(get_address(pv, i))
end

@inline function Base.setindex!(pv::PagedVector{T}, v, i::Int) where {T}
    unsafe_store!(get_address(pv, i), v)
end

function Base.IndexStyle(_::Type{PagedVector{T}}) where {T}
    Base.IndexLinear()
end
