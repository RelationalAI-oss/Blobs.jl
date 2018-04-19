"""
    alloc_size(::Type{T}, args...) where {T}

The number of additional bytes needed to allocate `T`, other than `sizeof(T)` itself.

Defaults to 0.
"""
alloc_size(::Type{T}) where T = 0

"""
    init(blob::Blob{T}, args...) where T

Initialize `blob`.

Assumes that `blob` it at least `sizeof(T) + alloc_size(T, args...)` bytes long.
"""
function init(blob::Blob{T}, args...) where T
    init(blob, Blob{Void}(blob + sizeof(T)), args...)
end

"""
    init(blob::Blob{T}, free::Blob{Void}, args...)::Blob{Void} where T

Initialize `blob`, where `free` is the beginning of the remaining free space. Must return `free + alloc_size(T, args...)`.

The default implementation where `alloc_size(T) == 0` does nothing. Override this method to add custom initializers for your types.
"""
function init(blob::Blob{T}, free::Blob{Void}) where T
    @assert alloc_size(T) == 0 "Default init cannot be used for types for which alloc_size(T) != 0"
    # TODO should we zero memory?
    free
end

alloc_size(::Type{Blob{T}}, args...) where T = sizeof(T) + alloc_size(T, args...)

function init(blob::Blob{Blob{T}}, free::Blob{Void}, args...) where T
    nested_blob = Blob{T}(free)
    @v blob = nested_blob
    init(nested_blob, free + sizeof(T), args...)
end

alloc_size(::Type{BlobVector{T}}, length::Int64) where {T} = sizeof(T) * length

function init(blob::Blob{BlobVector{T}}, free::Blob{Void}, length::Int64) where T
    @v blob.data = Blob{T}(free)
    @v blob.length = length
    free + alloc_size(BlobVector{T}, length)
end

alloc_size(::Type{BlobBitVector}, length::Int64) = UInt64(ceil(length / sizeof(UInt64)))

function init(blob::Blob{BlobBitVector}, free::Blob{Void}, length::Int64)
    @v blob.data = Blob{UInt64}(free)
    @v blob.length = length
    free + alloc_size(BlobBitVector, length)
end

alloc_size(::Type{BlobString}, length::Int64) = length

function init(blob::Blob{BlobString}, free::Blob{Void}, length::Int64)
    @v blob.data = Blob{UInt8}(free)
    @v blob.len = length
    free + alloc_size(BlobString, length)
end

alloc_size(::Type{BlobString}, string::Union{String, BlobString}) = string.len

function init(blob::Blob{BlobString}, free::Blob{Void}, string::Union{String, BlobString})
    free = init(blob, free, string.len)
    unsafe_copy!((@v blob), string)
    free
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate an uninitialized `Blob{T}`.
"""
function malloc(::Type{T}, args...)::Blob{T} where T
    size = sizeof(T) + alloc_size(T, args...)
    Blob{T}(Libc.malloc(size))
end

"""
    malloc_and_init(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
function malloc_and_init(::Type{T}, args...)::Blob{T} where T
    size = sizeof(T) + alloc_size(T, args...)
    blob = Blob{T}(Libc.malloc(size))
    used = init(blob, args...)
    @assert used - blob == size
    blob
end

"""
    free(blob::Blob)

Free the underlying allocation for `blob`.
"""
function free(blob::Blob)
    Libc.free(blob.ptr)
end
