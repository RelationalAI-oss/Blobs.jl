"""
A pointer to a `T` store!d inside a Blob.
"""
struct Blob{T}
    base::Ptr{Void}
    offset::UInt64
    limit::UInt64

    function Blob{T}(base::Ptr{Void}, offset::UInt64, limit::UInt64) where {T}
        @assert isbits(T)
        new(base, offset, limit)
    end
end

function assert_same_allocation(blob1::Blob, blob2::Blob)
    @assert blob1.base == blob2.base "These blobs do not share the same allocation: $blob1 - $blob2"
end

function Base.pointer(blob::Blob{T}) where T
    convert(Ptr{T}, blob.base + blob.offset)
end

function Base.convert(::Type{Blob{T}}, blob::Blob) where T
    Blob{T}(blob.base, blob.offset, blob.limit)
end

function Base.:+(blob::Blob{T}, offset::Integer) where T
    Blob{T}(blob.base, blob.offset + offset, blob.limit)
end

function Base.:-(blob1::Blob, blob2::Blob)
    assert_same_allocation(blob1, blob2)
    blob1.offset - blob2.offset
end

@inline function boundscheck(blob::Blob{T}) where T
    @boundscheck begin
        if (blob.offset < 0) || (blob.offset + self_size(T) > blob.limit)
            throw(BoundsError(blob))
        end
    end
end

Base.@propagate_inbounds function Base.getindex(blob::Blob{T}) where T
    boundscheck(blob)
    unsafe_load(blob)
end

"""
    self_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate `T` itself.

Defaults to `sizeof(T)`.
"""
self_size(::Type{T}) where T = sizeof(T)

@generated function blob_offset(::Type{T}, ::Type{Val{i}}) where {T, i}
    quote
        +(0, $(@splice j in 1:(i-1) quote
            self_size(fieldtype(T, $j))
        end))
    end
end

@generated function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Blob{$(fieldtype(T, i))}(blob + $(blob_offset(T, Val{i})))
    end
end

Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
    boundscheck(blob)
    unsafe_store!(blob, value)
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.setindex!(blob::Blob{T}, value) where T
    setindex!(blob, convert(T, value))
end

@generated function Base.unsafe_load(blob::Blob{T}) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_load(pointer(blob))
        end
    else
        # is a composite type - recursively load its fields so that specializations of this method can hook in and alter loading
        $(Expr(:meta, :inline))
        Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_load(getindex(blob, $(Val{field})))
        end)
    end
end

@generated function Base.unsafe_store!(blob::Blob{T}, value::T) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(pointer(blob), value)
            value
        end
    else
        # is a composite type - recursively store! its fields so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(getindex(blob, $(Val{field})), value.$field)
            end)
            value
        end
    end
end

# patch pointers on the fly during load/store!

function self_size(blob::Blob{T}) where T
    sizeof(UInt64)
end

@inline function Base.unsafe_load(blob::Blob{Blob{T}}) where {T}
    offset = unsafe_load(Blob{UInt64}(blob))
    Blob{T}(blob.base, blob.offset + offset, blob.limit)
end

@inline function Base.unsafe_store!(blob::Blob{Blob{T}}, value::Blob{T}) where {T}
    assert_same_allocation(blob, value)
    offset = value.offset - blob.offset
    unsafe_store!(Blob{UInt64}(blob), offset)
end
