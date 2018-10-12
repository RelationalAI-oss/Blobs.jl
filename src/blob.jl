"""
A pointer to a `T` stored inside a Blob.
"""
struct Blob{T}
    ptr::Ptr{Nothing}

    @inline function Blob{T}(ptr::Ptr{Nothing}) where {T}
        # @assert isbitstype(T)
        new(ptr)
    end
end

# @inline function Blob{T}(blob::Blob) where T
#     Blob{T}(getfield(blob, :ptr))
# end

@inline function assert_same_allocation(blob1::Blob, blob2::Blob)
    # @assert getfield(blob1, :ptr) == getfield(blob2, :ptr) "These blobs do not share the same allocation: $blob1 - $blob2"
end

@inline function Base.pointer(blob::Blob{T}) where T
    convert(Ptr{T}, getfield(blob, :ptr))
end

@inline function Base.:+(blob::Blob{T}, offset::Blob) where T
    getfield(blob, :ptr) + getfield(offset, :ptr)
end

@inline function Base.:+(blob::Blob{T}, offset::Integer) where T
    getfield(blob, :ptr) + offset
end

@inline function Base.:-(blob1::Blob, blob2::Blob)
    # assert_same_allocation(blob1, blob2)
    getfield(blob1, :ptr) - getfield(blob2, :ptr)
end

# @inline function boundscheck(blob::Blob{T}) where T
#     @boundscheck begin
#         if (getfield(blob, :offset) < 0)
#             throw(BoundsError(blob))
#         end
#     end
# end

@inline Base.@propagate_inbounds function Base.getindex(blob::Blob{T}) where T
    # boundscheck(blob)
    unsafe_load(blob)
end

# TODO(jamii) do we need to align data?
# """
#     sizeof(::Type{T}, args...) where {T}
# 
# The number of bytes needed to allocate `T` itself.
# 
# Defaults to `sizeof(T)`.
# """
# @generated function self_size(::Type{T}) where T
#     @assert isconcretetype(T)
#     if isempty(fieldnames(T))
#         quote
#             $(Expr(:meta, :inline))
#             $(sizeof(T))
#         end
#     else
#         quote
#             $(Expr(:meta, :inline))
#             $(+(0, @splice i in 1:length(fieldnames(T)) begin
#                 self_size(fieldtype(T, i))
#             end))
#         end
#     end
# end

@inline function blob_offset(::Type{T}, i::Int) where {T}
    +(0, @splice j in 1:(i-1) begin
        sizeof(fieldtype(T, j))
    end)
end

@generated function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(isequal(field), fieldnames(T))
    @assert i != nothing "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Blob{$(fieldtype(T, i))}(getfield(blob, :ptr) + $(blob_offset(T, i)))
    end
end

@inline Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
    # boundscheck(blob)
    unsafe_store!(blob, value)
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value) where T
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
@inline function Base.unsafe_store!(blob::Blob{T}, value) where {T}
    unsafe_store!(blob, convert(T, value))
end

# syntax sugar

# @inline function Base.propertynames(::Blob{T}, private=false) where T
#     fieldnames(T)
# end
# 
# @inline function Base.getproperty(blob::Blob{T}, field::Symbol) where T
#     getindex(blob, Val{field})
# end
# 
# @inline function Base.setproperty!(blob::Blob{T}, field::Symbol, value) where T
#     setindex!(blob, Val{field}, value)
# end

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

@inline function sizeof(::Type{Blob{T}}) where T
    sizeof(Int64)
end

@inline function Base.unsafe_load(blob::Blob{Blob{T}}) where {T}
    offset = unsafe_load(Blob{Int64}(getfield(blob, :ptr)))
    Blob{T}(getfield(blob, :ptr) + offset)
end

@inline function Base.unsafe_store!(blob::Blob{Blob{T}}, value::Blob{T}) where {T}
    # assert_same_allocation(blob, value)
    offset = getfield(value, :ptr) - getfield(blob, :ptr)
    unsafe_store!(Blob{Int64}(getfield(blob, :ptr)), offset)
end
