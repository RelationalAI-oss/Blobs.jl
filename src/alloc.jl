"""
    alloc_size(::Type{T}, args...) where {T}

The number of additional bytes needed to allocate `T`, other than `sizeof(T)` itself.

Defaults to 0.
"""
alloc_size(::Type{T}) where T = 0

"""
    init(blob::Blob{T}, args...) where T

Initialize `blob`.
"""
function init(blob::Blob{T}, args...) where T
    init(blob.ptr + sizeof(T), blob, args...)
    nothing
end

"""
    init(ptr::Ptr{Void}, blob::Blob{T}, args...)::Ptr{Void} where T

Initialize `blob`, where `ptr` is the beginning of the remaining free space. Must return `ptr + alloc_size(T, args...)`. Override this method to add custom initializers for your types.

The default implementation where `alloc_size(T) == 0` does nothing.
"""
function init(ptr::Ptr{Void}, blob::Blob{T}) where T
    @assert alloc_size(T) == 0 "Default init cannot be used for types for which alloc_size(T) != 0"
    # TODO should we zero memory?
    ptr
end

alloc_size(::Type{Blob{T}}, args...) where T = sizeof(T) + alloc_size(T, args...)

function init(ptr::Ptr{Void}, blob::Blob{Blob{T}}, args...) where T
    @v blob = Blob{T}(ptr)
    t = Blob{T}(ptr)
    t_ptr = ptr + sizeof(T)
    init(t_ptr, t, args...)
end

alloc_size(::Type{BlobVector{T}}, length::Int64) where {T} = sizeof(T) * length

function init(ptr::Ptr{Void}, pv::Blob{BlobVector{T}}, length::Int64) where T
    @v pv.ptr = Blob{T}(ptr)
    @v pv.length = length
    ptr + alloc_size(BlobVector{T}, length)
end

alloc_size(::Type{BlobBitVector}, length::Int64) = UInt64(ceil(length / sizeof(UInt64)))

function init(ptr::Ptr{Void}, pv::Blob{BlobBitVector}, length::Int64)
    @v pv.ptr = Blob{UInt64}(ptr)
    @v pv.length = length
    ptr + alloc_size(BlobBitVector, length)
end

alloc_size(::Type{BlobString}, length::Int64) = length

function init(ptr::Ptr{Void}, ps::Blob{BlobString}, length::Int64)
    @v ps.ptr = Blob{UInt8}(ptr)
    @v ps.len = length
    ptr + alloc_size(BlobString, length)
end

alloc_size(::Type{BlobString}, string::Union{String, BlobString}) = string.len

function init(ptr::Ptr{Void}, ps::Blob{BlobString}, string::Union{String, BlobString})
    ptr = init(ptr, ps, string.len)
    unsafe_copy!((@v ps), string)
    ptr
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
function malloc(::Type{T}, args...)::Blob{T} where T
    size = sizeof(T) + alloc_size(T, args...)
    ptr = Libc.malloc(size)
    blob = Blob{T}(ptr)
    end_ptr = init(ptr + sizeof(T), blob, args...)
    @assert end_ptr - ptr == size
    blob
end
