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

function replace_dots(expr)
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
        :(getproperty($(replace_dots(object)), $(Val{fieldname})))
    else
        error("Don't know how to rewrite $expr")
    end
end

function _paged(expr)
    if expr.head == :.
        # p.x.y
        replace_dots(expr)
    elseif expr.head == :ref
        # p.x.y[]
        @assert length(expr.args) == 1
        Expr(:ref, replace_dots(expr.args[1]))
    elseif (expr.head == :(=)) && (expr.args[1].head == :ref)
        # p.x.y[] = ...
        @assert length(expr.args[1].args) == 1
        Expr(:(=), Expr(:ref, replace_dots(expr.args[1].args[1])), esc(expr.args[2]))
    else
        error("Don't know how to rewrite $expr")
    end
end

"""
Syntactic sugar for accessing fields of `Paged{T}`.

    @paged p.x.y

Return a `Paged` pointing at `p.x.y`

    @paged p.x.y[]

Return a copy of the value of `p.x.y`

    @paged p.x.y[] = z

Write a copy of `z` into `p.x.y`

(This syntax will be supported without needing a macro in Julia 0.7)
"""
macro paged(expr)
    _paged(expr)
end

# @paged turns `p.x` into `getproperty(p, Val{x})`
@generated function getproperty(paged::Paged{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0
    quote
        $(Expr(:meta, :inline))
        Paged{$(fieldtype(T, i))}(paged.ptr + $(fieldoffset(T, i)))
    end
end

# tell the autocomplete about this
propertynames(::Type{Paged{T}}) where {T} = fieldnames(T)

# can read from a Paged{T} using the syntax p[]
@generated function Base.getindex(paged::Paged{T}) where {T}
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
            getindex(getproperty(paged, $(Val{field})))
        end)
    end
end

# can write to a Paged{T} using the syntax p[] = ...
@generated function Base.setindex!(paged::Paged{T}, value::T) where {T}
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
                setindex!(getproperty(paged, $(Val{field})), value.$field)
            end)
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.setindex!(paged::Paged{T}, value) where {T}
    setindex!(paged, convert(T, value))
end

# pointers to other parts of the page need to be converted into offsets

@inline function Base.getindex(paged::Paged{Paged{T}}) where {T}
    offset = getindex(Paged{UInt64}(paged.ptr))
    Paged{T}(paged.ptr + offset)
end

@inline function Base.setindex!(paged::Paged{Paged{T}}, value::Paged{T}) where {T}
    offset = value.ptr - paged.ptr
    setindex!(Paged{UInt64}(paged.ptr), offset)
end

include("paged_vectors.jl")
include("paged_bit_vectors.jl")

export Paged, PagedVector, PagedBitVector, @paged

end
