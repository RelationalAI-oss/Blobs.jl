function rewrite_getindex(expr)
    if @capture(expr, object_.field_)
        :(getindex($(rewrite_getindex(object)), $(Val{field})))
    elseif @capture(expr, object_[ixes__])
        :(getindex($(rewrite_getindex(object)), $(map(esc, ixes)...)))
    elseif @capture(expr, object_Symbol)
        esc(object)
    else
        error("Don't know how to compute address for $expr")
    end
end

function rewrite_setindex!(expr)
    if @capture(expr, address_[] = value_)
        :(setindex!($(rewrite_getindex(address)), $(esc(value))))
    else
        rewrite_getindex(expr)
    end
end

if VERSION >= v"0.7.0-DEV"

function Base.propertynames(::Blob{T}, private=false) where T
    Base.propertynames(T, private)
end

function Base.getproperty(blob::Blob{T}, field::Symbol) where T
    getindex(blob, Val{field})
end

function Base.setproperty!(blob::Blob{T}, field::Symbol, value) where T
    setindex!(blob, Val{field}, value)
end

macro blob(expr)
    esc(expr)
end

else

"""
    @blob blob.x

Get a `Blob` pointing at `blob.x`.

    @blob blob.x[]

Get the value of `blob.x`.

    @blob blob.x[] = v

Set the value of `blob.x`.

    @blob blob.vec[i]

Get a `Blob` pointing at the i'th element of the Blob(Bit)Vector at `blob.vec`

    @blob blob.vec[i][]

Get the value of the i'th element of the Blob(Bit)Vector at `blob.vec`

    @blob blob.vec[i][] = v

Set the value of the i'th element of the Blob(Bit)Vector at `blob.vec`
"""
macro blob(expr)
    rewrite_setindex!(expr)
end

end
