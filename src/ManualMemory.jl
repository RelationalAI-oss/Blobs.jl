module ManualMemory

macro splice(iterator, body)
  @assert iterator.head == :call
  @assert iterator.args[1] == :in
  Expr(:..., :(($(esc(body)) for $(esc(iterator.args[2])) in $(esc(iterator.args[3])))))
end

"""
A pointer to a `T` in some manually managed region of memory.
"""
# TODO do we want to also keep the page address/size in here? If we complicate the loading code a little we could avoid writing it to the page, so it would only exist on the stack.
struct Manual{T}
    ptr::Ptr{Void}

    function Manual{T}(ptr::Ptr{Void}) where {T}
        @assert isbits(T)
        new(ptr)
    end
end

get_ptr(man::Manual{T}) where {T} = man.ptr

"Allocate `size` bytes for an unintialized Manual{T}"
Manual{T}(size::Integer) where {T} = Manual{T}(Libc.malloc(size))

"Allocate `sizeof(T)` bytes for an unintialized Manual{T}"
Manual{T}() where {T} = Manual{T}(sizeof(T))

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
    @a man.x[2].y

Get a `Manual` pointing at the *address* of `man.x[2].y`.
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
    @v man.x[2].y

Get the *value* at `man.x[2].y`.

    @v man.x[2].y = 42

Set the *value* at `man.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v man.x[2].y < 42

    # valid syntax
    (@v man.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
end

function get_address(man::Manual{Manual{T}}, ::Type{Val{field}}) where {T, field}
    get_address(Manual{T}(get_ptr(man)), Val{field})
end

@generated function get_address(man::Manual{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Manual{$(fieldtype(T, i))}(get_ptr(man) + $(fieldoffset(T, i)))
    end
end

@generated function Base.unsafe_load(man::Manual{T}) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_load(convert(Ptr{T}, get_ptr(man)))
        end
    else
        # is a composite type - recursively load its fields
        # so that specializations of this method can hook in and alter loading
        $(Expr(:meta, :inline))
        Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_load(get_address(man, $(Val{field})))
        end)
    end
end

@generated function Base.unsafe_store!(man::Manual{T}, value::T) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(convert(Ptr{T}, get_ptr(man)), value)
            value
        end
    else
        # is a composite type - recursively store its fields
        # so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(get_address(man, $(Val{field})), value.$field)
            end)
            value
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.unsafe_store!(man::Manual{T}, value) where {T}
    unsafe_store!(man, convert(T, value))
end

# pointers to other parts of the region need to be converted into offsets

@inline function Base.unsafe_load(man::Manual{Manual{T}}) where {T}
    offset = unsafe_load(Manual{UInt64}(man.ptr))
    Manual{T}(get_ptr(man) + offset)
end

@inline function Base.unsafe_store!(man::Manual{Manual{T}}, value::Manual{T}) where {T}
    offset = value.ptr - get_ptr(man)
    unsafe_store!(Manual{UInt64}(get_ptr(man)), offset)
end

include("manual_vectors.jl")
include("manual_bit_vectors.jl")
include("manual_strings.jl")
include("manual_alloc.jl")

export Manual, ManualVector, ManualBitVector, ManualString, @a, @v, manual_alloc

end
