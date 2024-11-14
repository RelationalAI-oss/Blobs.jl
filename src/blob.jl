struct InvalidBlobError <: Exception
    type::Type
    base::Ptr{Nothing}
    offset::Int64
    limit::Int64
    length::Int64
end

function Base.showerror(io::IO, e::InvalidBlobError)
    print(io, "InvalidBlobError: $(e.type) needs $(e.length) * $(self_size(e.type)) bytes. \
        Got length($(e.offset):$(e.limit)) == $(e.limit - e.offset) bytes")
end

"""
    Blob{T}

A pointer to a memory array that stores a `T`.

The fields are stored compact in memory without alignment, i.e each basic field f takes up
`sizeof(fieldtype(T, :f))` bytes. Blobs inside `T` take just the offset, i.e. 8 bytes.
This is different from Julia memory layout.

You can just store struct of only primitive types or structs of primitive out of the box,
for example:

```julia
struct Foo
    x::Int64
    y::Float64
end

blob = Blobs.malloc(Foo)
blob[] = Foo(42, 3.14)

In order to store variable size data structures (`BlobVector`, `BlobBitVector`,
`BlobString` or your own implementation) or a `Blob``, you need to implement `child_size`
and `init` for your type.

Example:
```julia
    struct FooString
        s::BlobString
        i::Int64
    end

    function Blobs.child_size(::FooString, string_length::Int64)
        return child_size(BlobString, string_length)
    end

    function Blobs.init(blob::Blob{FooString}, free::Blob{Nothing}, string_length::Int64)
        free = Blobs.init(blob.s, free, string_length)
        blob.i[] = 0
        return free
    end
```
"""
struct Blob{T}
    base::Ptr{Nothing}
    offset::Int64
    limit::Int64

    function Blob{T}(base::Ptr{Nothing}, offset::Int64, limit::Int64) where {T}
        @assert isbitstype(T)
        @boundscheck _bounds_check(base, offset, limit, self_size(T), T)
        new{T}(base, offset, limit)
    end
end

@noinline function _bounds_check(
    base::Ptr{Nothing},
    offset::Int64,
    limit::Int64,
    self_size_T::Int64,
    @nospecialize(T::DataType))
    if offset < 0 || offset + self_size_T > limit
        throw(InvalidBlobError(Blob{T}, base, offset, limit, 1))
    end
    if limit > 0 && base == Ptr{Nothing}(0)
        throw(AssertionError("Null pointer reference Blob{$(T)}"))
    end
end

"""
    Blob{T}(ref::Base.RefValue{T}) where T

Create a `Blob{T}` from an Julia allocated object.
**Danger**: This only works if memory layout of Julia struct is the same as of the Blob.
"""
function Blob(ref::Base.RefValue{T}) where T
    @assert self_size(T) == sizeof(T) "$(T) cannot of aligned fields or Blobs"
    @inbounds Blob{T}(pointer_from_objref(ref), 0, self_size(T))
end

"""
    Blob{T}(base::Ptr{T}, offset::Int64 = 0, limit::Int64 = sizeof(T)) where T

Create a `Blob{T}` from a pointer.
"""
Base.@propagate_inbounds \
function Blob(base::Ptr{T}, offset::Int64 = 0, limit::Int64 = sizeof(T)) where {T}
    Blob{T}(Ptr{Nothing}(base), offset, limit)
end

"""
    Blob{T}(blob::Blob)

    Make a copy and potentially change the type of a `Blob`.
"""
Base.@propagate_inbounds function Blob{T}(blob::Blob) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset), getfield(blob, :limit))
end

"""
    available_size(blob::Blob{T}) where T

The size of memory this `Blob` and it's children own. `blob.limit - blob.offset`.
"""
available_size(blob::Blob{T}) where T = getfield(blob, :limit) - getfield(blob, :offset)

function assert_same_allocation(blob1::Blob, blob2::Blob)
    @assert getfield(blob1, :base) == getfield(blob2, :base) "These blobs do not share the same allocation: $blob1 - $blob2"
end

""""
    pointer(blob::Blob{T}) where T

Get a pointer to the data in the `blob`. Note that you cannot `unsafe_load`
from this pointer, since the data is not aligned.
"""
function Base.pointer(blob::Blob{T}) where T
    convert(Ptr{T}, getfield(blob, :base) + getfield(blob, :offset))
end

""""
    Base:+(::Blob, ::Integer)

Increase the offset of a `Blob` by `offset`.
"""
Base.@propagate_inbounds function Base.:+(blob::Blob{T}, offset::Integer) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset) + offset, getfield(blob, :limit))
end

"""
    Base:-(::Blob, ::Blob)

Get the offset difference of two blobs in the same allocation.
"""
function Base.:-(blob1::Blob, blob2::Blob)
    assert_same_allocation(blob1, blob2)
    getfield(blob1, :offset) - getfield(blob2, :offset)
end

function Base.getindex(blob::Blob{T}) where T
    unsafe_load(blob)
end

"""
    self_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate `T` itself.

Defaults to `sizeof(T)`.
"""
@generated function self_size(::Type{T}) where T
    @assert isconcretetype(T)
    if isempty(fieldnames(T))
        quote
            $(Expr(:meta, :inline))
            $(sizeof(T))
        end
    else
        quote
            $(Expr(:meta, :inline))
            $(+(0, @splice i in 1:length(fieldnames(T)) begin
                self_size(fieldtype(T, i))
            end))
        end
    end
end

function blob_offset(::Type{T}, i::Int) where {T}
    +(0, @splice j in 1:(i-1) begin
        self_size(fieldtype(T, j))
    end)
end

@generated function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(isequal(field), fieldnames(T))
    @assert i !== nothing "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        @inbounds Blob{$(fieldtype(T, i))}(blob) + $(blob_offset(T, i))
    end
end

@inline function Base.getindex(blob::Blob{T}, i::Int) where {T}
    @boundscheck if i < 1 || i > fieldcount(T)
        throw(BoundsError(blob, i))
    end
    return @inbounds Blob{fieldtype(T, i)}(blob) + Blobs.blob_offset(T, i)
end

Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
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
    elseif T <: Tuple
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(getindex(blob, $(Val{field})), value[$field])
            end)
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
