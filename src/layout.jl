"""
    child_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate children of `T`, not including `self_size(T)`.

Defaults to 0.
"""
@inline child_size(::Type{T}) where T = 0

"""
    init(blob::Blob{T}, args...) where T

Initialize `blob`.

Assumes that `blob` it at least `self_size(T) + child_size(T, args...)` bytes long.
"""
@inline function init(blob::Blob{T}, args...) where T
    init(blob, getfield(blob, :ptr) + self_size(T), args...)
end

"""
    init(blob::Blob{T}, free::Ptr{Nothing}, args...)::Blob{Nothing} where T

Initialize `blob`, where `free` is the beginning of the remaining free space. Must return `free + child_size(T, args...)`.

The default implementation where `child_size(T) == 0` does nothing. Override this method to add custom initializers for your types.
"""
@inline function init(blob::Blob{T}, free::Ptr{Nothing}) where T
    # @assert child_size(T) == 0 "Default init cannot be used for types for which child_size(T) != 0"
    # TODO should we zero memory?
    free
end

@inline child_size(::Type{Blob{T}}, args...) where T = self_size(T) + child_size(T, args...)

@inline function init(blob::Blob{Blob{T}}, free::Ptr{Nothing}, args...) where T
    nested_blob = Blob{T}(free)
    @v blob = nested_blob
    init(nested_blob, free + self_size(T), args...)
end

@inline child_size(::Type{BlobVector{T}}, length::Int64) where {T} = self_size(T) * length

@inline function init(blob::Blob{BlobVector{T}}, free::Ptr{Nothing}, length::Int64) where T
    @v blob.data = Blob{T}(free)
    @v blob.length = length
    free + child_size(BlobVector{T}, length)
end

@inline child_size(::Type{BlobBitVector}, length::Int64) = self_size(UInt64) * Int64(ceil(length / 64))

@inline function init(blob::Blob{BlobBitVector}, free::Ptr{Nothing}, length::Int64)
    @v blob.data = Blob{UInt64}(free)
    @v blob.length = length
    free + child_size(BlobBitVector, length)
end

@inline child_size(::Type{BlobString}, length::Int64) = length

@inline function init(blob::Blob{BlobString}, free::Ptr{Nothing}, length::Int64)
    @v blob.data = Blob{UInt8}(free)
    @v blob.len = length
    free + child_size(BlobString, length)
end

@inline child_size(::Type{BlobString}, string::Union{String, BlobString}) = sizeof(string)

@inline function init(blob::Blob{BlobString}, free::Ptr{Nothing}, string::Union{String, BlobString})
    free = init(blob, free, sizeof(string))
    unsafe_copyto!((@v blob), string)
    free
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate an uninitialized `Blob{T}`.
"""
@inline function malloc(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    Blob{T}(Libc.malloc(size))
end

"""
    malloc_and_init(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
@inline function malloc_and_init(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    blob = Blob{T}(Libc.malloc(size))
    used = init(blob, args...)
    # @assert used - blob == size
    blob
end

"""
    free(blob::Blob)

Free the underlying allocation for `blob`.
"""
@inline function free(blob::Blob)
    Libc.free(getfield(blob, :base))
end
