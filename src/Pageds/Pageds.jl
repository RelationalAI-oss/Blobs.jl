module Pageds

macro splice(iterator, body)
  @assert iterator.head == :call
  @assert iterator.args[1] == :in
  Expr(:..., :(($(esc(body)) for $(esc(iterator.args[2])) in $(esc(iterator.args[3])))))
end

"""
A pointer to a `T` in some manually managed region of memory.

TODO do we want to also keep the page address/size in here? If we complicate the loading code a little we could avoid writing it to the page, so it would only exist on the stack.
"""
struct Paged{T}
    ptr::Ptr{Void}

    function Paged{T}(ptr::Ptr{Void}) where {T}
        @assert isbits(T)
        new(ptr)
    end
end

"Allocate `size` bytes for an unintialized Paged{T}"
Paged{T}(size::Integer) where {T} = Paged{T}(Libc.malloc(size))

"Allocate `sizeof(T)` bytes for an unintialized Paged{T}"
Paged{T}() where {T} = Paged{T}(sizeof(T))

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
    @a paged.x[2].y

Get a `Paged` pointing at the *address* of `paged.x[2].y`.
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
    @v paged.x[2].y

Get the *value* at `paged.x[2].y`.

    @v paged.x[2].y = 42

Set the *value* at `paged.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v paged.x[2].y < 42

    # valid syntax
    (@v paged.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
end

@generated function get_address(paged::Paged{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0
    quote
        $(Expr(:meta, :inline))
        Paged{$(fieldtype(T, i))}(paged.ptr + $(fieldoffset(T, i)))
    end
end

@generated function Base.unsafe_load(paged::Paged{T}) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_load(convert(Ptr{T}, paged.ptr))
        end
    else
        # is a composite type - recursively load its fields
        # so that specializations of this method can hook in and alter loading
        $(Expr(:meta, :inline))
        Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_load(get_address(paged, $(Val{field})))
        end)
    end
end

# can write to a Paged{T} using the syntax p[] = ...
@generated function Base.unsafe_store!(paged::Paged{T}, value::T) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(convert(Ptr{T}, paged.ptr), value)
        end
    else
        # is a composite type - recursively store its fields
        # so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(get_address(paged, $(Val{field})), value.$field)
            end)
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.unsafe_store!(paged::Paged{T}, value) where {T}
    unsafe_store!(paged, convert(T, value))
end

# pointers to other parts of the page need to be converted into offsets

@inline function Base.unsafe_load(paged::Paged{Paged{T}}) where {T}
    offset = unsafe_load(Paged{UInt64}(paged.ptr))
    Paged{T}(paged.ptr + offset)
end

@inline function Base.unsafe_store!(paged::Paged{Paged{T}}, value::Paged{T}) where {T}
    offset = value.ptr - paged.ptr
    unsafe_store!(Paged{UInt64}(paged.ptr), offset)
end

include("paged_vectors.jl")
include("paged_bit_vectors.jl")
include("paged_strings.jl")
include("packed_memory_array.jl")

export Paged, PagedVector, PagedBitVector, PagedString, PackedMemoryArray, @a, @v
export PagedPrimitive

end
