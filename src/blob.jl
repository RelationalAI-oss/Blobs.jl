"""
A pointer to a `T` stored inside a Blob.
"""
# TODO do we want to also keep the page address/size in here? If we complicate the loading code a little we could avoid writing it to the page, so it would only exist on the stack.
struct Blob{T}
    base::Ptr{Void}
    offset::UInt64
    limit::UInt64

    function Blob{T}(base::Ptr{Void}, offset::UInt64, limit::UInt64) where {T}
        @assert isbits(T)
        @assert offset + sizeof(T) <= limit "Out of bounds: Blob{$T}($base, $offset, $limit)"
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

# avoid double boundscheck in the common case of Blob{T}(blob) + offset
function Blob{T}(blob::Blob, offset::Integer) where T
    Blob{T}(blob.base, blob.offset + offset, blob.limit)
end

function Base.:+(blob::Blob{T}, offset::Integer) where T
    Blob{T}(blob.base, blob.offset + offset, blob.limit)
end

function Base.:-(blob1::Blob, blob2::Blob)
    assert_same_allocation(blob1, blob2)
    blob1.offset - blob2.offset
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
        :(get_address($(rewrite_address(object)), $(Val{fieldname})))
    elseif expr.head == :ref
        object = expr.args[1]
        :(get_address($(rewrite_address(object)), $(map(esc, expr.args[2:end])...)))
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

@generated function get_address(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Blob{$(fieldtype(T, i))}(blob, $(fieldoffset(T, i)))
    end
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
            unsafe_load(get_address(blob, $(Val{field})))
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
        # is a composite type - recursively store its fields so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(get_address(blob, $(Val{field})), value.$field)
            end)
            value
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.unsafe_store!(blob::Blob{T}, value) where {T}
    unsafe_store!(blob, convert(T, value))
end

# patch pointers on the fly during load/store
@inline function Base.unsafe_load(blob::Blob{Blob{T}}) where {T}
    unpatched_blob = unsafe_load(pointer(blob))
    Blob{T}(blob.base, blob.offset + unpatched_blob.offset, blob.limit)
end
@inline function Base.unsafe_store!(blob::Blob{Blob{T}}, value::Blob{T}) where {T}
    assert_same_allocation(blob, value)
    unpatched_blob = Blob{T}(blob.base, value.offset - blob.offset, blob.limit)
    unsafe_store!(pointer(blob), unpatched_blob)
end
