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

function Blob(ref::Base.RefValue{T}) where T
    Blob{T}(pointer_from_objref(ref), 0, sizeof(T))
end

function Blob(base::Ptr{T}, offset::Int64 = 0, limit::Int64 = sizeof(T)) where {T}
    Blob{T}(Ptr{Nothing}(base), offset, limit)
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
        @assert (getfield(blob, :base) != Ptr{Nothing}(0)) "Null pointer dereference in $(typeof(blob))"
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
Base.@assume_effects :foldable function self_size(::Type{T}) where T
    # This function is marked :total to encourage constant folding for this types-only
    # static computation.
    if isempty(fieldnames(T))
        sizeof(T)
    else
        # Recursion is the fastest way to compile this, confirmed with benchmarks.
        # Alternative considered: +(Iterators.map(self_size, fieldtypes(T))...)
        # ~0.5ms for 5 fields, vs ~5ms for unrolling via splatting the fields.
        # ~3ms for 20 fields, vs ~6ms for splatting.
        # Note that splatting gives up after ~30 fields, whereas recursion remains robust.
        _sum_field_sizes(T)
    end
end
Base.@assume_effects :foldable _sum_field_sizes(::Type{T}) where {T} =
    _sum_field_sizes(T, Val(fieldcount(T)))
Base.@assume_effects :foldable _sum_field_sizes(::Type, ::Val{0}) = 0
Base.@assume_effects :foldable function _sum_field_sizes(::Type{T}, ::Val{i}) where {T,i}
    return self_size(fieldtype(T, i)) + _sum_field_sizes(T, Val(i-1))
end

# Recursion scales better than splatting for large numbers of fields.
Base.@assume_effects :foldable @inline function blob_offset(::Type{T}, i::Int) where {T}
    return _blob_offset(T, i-1)
end
Base.@assume_effects :foldable @inline function _blob_offset(::Type{T}, i::Int) where {T}
    i <= 0 && return 0
    return _blob_offset(T, i-1) + self_size(fieldtype(T, i))
end

@inline function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(isequal(field), fieldnames(T))
    @assert i !== nothing "$T has no field $field"
    Blob{fieldtype(T, i)}(blob + (blob_offset(T, i)))
end

@inline function Base.getindex(blob::Blob{T}, i::Int) where {T}
    @boundscheck if i < 1 || i > fieldcount(T)
        throw(BoundsError(blob, i))
    end
    return Blob{fieldtype(T, i)}(blob + Blobs.blob_offset(T, i))
end

Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
    boundscheck(blob)
    unsafe_store!(blob, value)
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value) where T
    setindex!(blob, convert(T, value))
end

macro _make_new(type, args)
    # :splatnew lets you directly invoke the type's inner constructor with a Tuple,
    # bypassing any effects from any custom constructors.
    return Expr(:splatnew, esc(type), esc(args))
end
@inline function Base.unsafe_load(blob::Blob{T}) where {T}
    if isempty(fieldnames(T))
        unsafe_load(pointer(blob))
    else
        # This recursive definition is *almost* as fast as the `@generated` code. On julia
        # 1.10, it has a single invoke function call here, which adds a few ns overhead.
        # But on julia 1.11, this generates the expected code and is just as fast.
        # We are sticking with this version though, to save the `@generated` compilation time.
        @_make_new(T, _unsafe_load_fields(blob, Val(fieldcount(T))))
    end
end
@inline _unsafe_load_fields(::Blob, ::Val{0}) = ()
function _unsafe_load_fields(blob::Blob{T}, ::Val{I}) where {T, I}
    @inline
    types = fieldnames(T)
    return (_unsafe_load_fields(blob, Val(I-1))..., unsafe_load(getindex(blob, Val{types[I]})))
end

@inline function Base.unsafe_store!(blob::Blob{T}, value::T) where {T}
    if isempty(fieldnames(T))
        unsafe_store!(pointer(blob), value)
        value
    else
        _unsafe_store_struct!(blob::Blob{T}, value::T)
    end
end
@generated function _unsafe_store_struct!(blob::Blob{T}, value::T) where {T}
    quote
        $(Expr(:meta, :inline))
        $(@splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_store!(getindex(blob, $(Val{field})), value.$field)
        end)
        value
    end
end
@generated function Base.unsafe_store!(blob::Blob{T}, value::T) where {T <: Tuple}
    quote
        $(Expr(:meta, :inline))
        $(@splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_store!(getindex(blob, $(Val{field})), value[$field])
        end)
        value
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
function Base.unsafe_store!(blob::Blob{T}, value) where {T}
    unsafe_store!(blob, convert(T, value))
end

# syntax sugar

function Base.propertynames(::Blob{T}, private::Bool=false) where T
    fieldnames(T)
end

function Base.getproperty(blob::Blob{T}, field::Symbol) where T
    getindex(blob, Val{field})
end

function Base.setproperty!(blob::Blob{T}, field::Symbol, value) where T
    setindex!(blob, Val{field}, value)
end

function rewrite_address(expr)
    if !(expr isa Expr)
        esc(expr)
    elseif expr.head == :.
        (object, field) = expr.args
        if field isa QuoteNode
            fieldname = field.value
        elseif field isa Expr && field.head == :quote
            fieldname = field.args[1]
        else
            error("Impossible?")
        end
        :(getindex($(rewrite_address(object)), $(Val{fieldname})))
    elseif expr.head == :ref
        object = expr.args[1]
        :(getindex($(rewrite_address(object)), $(map(esc, expr.args[2:end])...)))
    elseif expr.head == :macrocall
        rewrite_address(macroexpand(expr))
    else
        error("Don't know how to compute address for $expr")
    end
end

"""
    @a blob.x[2].y

Get a `Blob` pointing at the *address* of `blob.x[2].y`.
"""
macro a(expr)
    rewrite_address(expr)
end

function rewrite_value(expr)
    if (expr isa Expr) && (expr.head == :(=))
        if length(expr.args) == 2
            :(unsafe_store!($(rewrite_address(expr.args[1])), $(esc(expr.args[2]))))
        else
            error("Don't know how to compute assignment $expr")
        end
    else
        :(unsafe_load($(rewrite_address(expr))))
    end
end

"""
    @v blob.x[2].y

Get the *value* at `blob.x[2].y`.

    @v blob.x[2].y = 42

Set the *value* at `blob.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v blob.x[2].y < 42

    # valid syntax
    (@v blob.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
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
