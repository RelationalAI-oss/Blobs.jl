"""
    alloc_size(::Type{T}, args...) where {T}

The number of additional bytes needed to allocate `T`, other than `sizeof(T)` itself.

Defaults to 0.
"""
alloc_size(::Type{T}) where T = 0

"""
    init(free::Ptr{Void}, blob::Blob{T}, args...)::Ptr{Void} where T

Initialize `blob`, where `free` is the beginning of the remaining free space. Must return `free + alloc_size(T, args...)`. Override this method to add custom initializers for your types.

The default implementation where `alloc_size(T) == 0` does nothing.
"""
function init(free::Blob{Void}, blob::Blob{T}) where T
    @assert alloc_size(T) == 0 "Default init cannot be used for types for which alloc_size(T) != 0"
    # TODO should we zero memory?
    ptr
end

alloc_size(::Type{Blob{T}}, args...) where T = sizeof(T) + alloc_size(T, args...)

function init(free::Blob{Void}, blob::Blob{Blob{T}}, args...) where T
    nested_blob = Blob{T}(free)
    @v blob = nested_blob
    init(free + sizeof(T), nested_blob, args...)
end

alloc_size(::Type{BlobVector{T}}, length::Int64) where {T} = sizeof(T) * length

function init(free::Blob{Void}, blob::Blob{BlobVector{T}}, length::Int64) where T
    @v blob.data = Blob{T}(free)
    @v blob.length = length
    free + alloc_size(BlobVector{T}, length)
end

alloc_size(::Type{BlobBitVector}, length::Int64) = UInt64(ceil(length / sizeof(UInt64)))

function init(free::Blob{Void}, blob::Blob{BlobBitVector}, length::Int64)
    @v blob.data = Blob{UInt64}(free)
    @v blob.length = length
    free + alloc_size(BlobBitVector, length)
end

alloc_size(::Type{BlobString}, length::Int64) = length

function init(free::Blob{Void}, blob::Blob{BlobString}, length::Int64)
    @v blob.data = Blob{UInt8}(free)
    @v blob.len = length
    free + alloc_size(BlobString, length)
end

alloc_size(::Type{BlobString}, string::Union{String, BlobString}) = string.len

function init(free::Blob{Void}, blob::Blob{BlobString}, string::Union{String, BlobString})
    free = init(free, blob, string.len)
    unsafe_copy!((@v blob), string)
    free
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
function malloc(::Type{T}, args...)::Blob{T} where T
    size = sizeof(T) + alloc_size(T, args...)
    ptr = Libc.malloc(size)
    blob = Blob{T}(ptr)
    free = Blob{Void}(ptr + sizeof(T))
    used = init(free, blob, args...)
    @assert used - blob == size
    blob
end
