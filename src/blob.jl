"""
A pointer to a `T` stored inside a Blob.
"""
struct Blob{T}
    base::Ptr{Nothing}
    offset::Int64
    limit::Int64

    function Blob{T}(base::Ptr{Nothing}, offset::Int64, limit::Int64) where {T}
        @assert isbitstype(T)
        new(base, offset, limit)
    end
end

function Blob{T}(blob::Blob) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset), getfield(blob, :limit))
end

function assert_same_allocation(blob1::Blob, blob2::Blob)
    @assert getfield(blob1, :base) == getfield(blob2, :base) "These blobs do not share the same allocation: $blob1 - $blob2"
end

function Base.pointer(blob::Blob{T}) where T
    convert(Ptr{T}, getfield(blob, :base) + getfield(blob, :offset))
end

function Base.:+(blob::Blob{T}, offset::Integer) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset) + offset, getfield(blob, :limit))
end

function Base.:-(blob1::Blob, blob2::Blob)
    assert_same_allocation(blob1, blob2)
    getfield(blob1, :offset) - getfield(blob2, :offset)
end

@inline function boundscheck(blob::Blob{T}) where T
    @boundscheck begin
        if (getfield(blob, :offset) < 0) || (getfield(blob, :offset) + self_size(T) > getfield(blob, :limit))
            throw(BoundsError(blob))
        end
    end
end

Base.@propagate_inbounds function Base.getindex(blob::Blob{T}) where T
    boundscheck(blob)
    unsafe_load(blob)
end

# TODO(jamii) do we need to align data?
"""
    self_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate `T` itself.

Defaults to `sizeof(T)`.
"""
@generated function self_size(::Type{T}) where T
    if VERSION >= v"0.7.0-DEV"
        @assert isconcretetype(T)
    else
        @assert isleaftype(T)
    end
    if isempty(fieldnames(T))
        quote
            $(Expr(:meta, :inline))
            sizeof(T)
        end
    else
        quote
            $(Expr(:meta, :inline))
            +(0, $(@splice i in 1:length(fieldnames(T)) quote
                self_size(fieldtype(T, $i))
            end))
        end
    end
end

@generated function blob_offset(::Type{T}, ::Type{Val{i}}) where {T, i}
    quote
        +(0, $(@splice j in 1:(i-1) quote
            self_size(fieldtype(T, $j))
        end))
    end
end

@generated function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    if VERSION >= v"0.7.0-DEV"
        i = findfirst(isequal(field), fieldnames(T))
        @assert i != nothing "$T has no field $field"
    else
        i = findfirst(fieldnames(T), field)
        @assert i != 0 "$T has no field $field"
    end
    quote
        $(Expr(:meta, :inline))
        Blob{$(fieldtype(T, i))}(blob + blob_offset(T, $(Val{i})))
    end
end

Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
    boundscheck(blob)
    unsafe_store!(blob, value)
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value) where T
    setindex!(blob, convert(T, value))
end

@generated function Base.unsafe_load(blob::Blob{T}) where {T}
    if isempty(fieldnames(T))
        quote
            $(Expr(:meta, :inline))
            unsafe_load(pointer(blob))
        end
    else
        quote
            $(Expr(:meta, :inline))
            $(Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_load(getindex(blob, $(Val{field})))
            end))
        end
    end
end

@generated function Base.unsafe_store!(blob::Blob{T}, value::T) where {T}
    if isempty(fieldnames(T))
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(pointer(blob), value)
            value
        end
    else
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

function self_size(::Type{Blob{T}}) where T
    sizeof(Int64)
end

@inline function Base.unsafe_load(blob::Blob{Blob{T}}) where {T}
    offset = unsafe_load(Blob{Int64}(blob))
    Blob{T}(getfield(blob, :base), getfield(blob, :offset) + offset, getfield(blob, :limit))
end

@inline function Base.unsafe_store!(blob::Blob{Blob{T}}, value::Blob{T}) where {T}
    assert_same_allocation(blob, value)
    offset = getfield(value, :offset) - getfield(blob, :offset)
    unsafe_store!(Blob{Int64}(blob), offset)
end
