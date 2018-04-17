struct ManualString <: AbstractString
    ptr::Manual{UInt8}
    len::Int64 # in bytes
end

# creation

function Base.unsafe_copy!(ps::ManualString, string::Union{ManualString, String})
    @assert ps.len >= string.len
    unsafe_copy!(convert(Ptr{UInt8}, ps.ptr.ptr), pointer(string), string.len)
end

function Base.String(ps::ManualString)
    unsafe_string(convert(Ptr{UInt8}, ps.ptr.ptr), ps.len)
end

# fields

function Base.pointer(ps::ManualString)
    convert(Ptr{UInt8}, ps.ptr.ptr)
end

# string interface - this is largely copied from Base and will almost certainly break when we move to 0.7

Base.sizeof(s::ManualString) = s.len

@inline function Base.codeunit(s::ManualString, i::Integer)
    @boundscheck if (i < 1) | (i > s.len)
        throw(BoundsError(s,i))
    end
    unsafe_load(pointer(s),i)
end

Base.write(io::IO, s::ManualString) = unsafe_write(io, pointer(s), reinterpret(UInt, s.len))

function Base.cmp(a::ManualString, b::ManualString)
    c = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt),
              a, b, min(a.len,b.len))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(a.len,b.len)
end

function Base.:(==)(a::ManualString, b::ManualString)
    a.len == b.len && 0 == ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, a.len)
end

function Base.prevind(s::ManualString, i::Integer)
    j = Int(i)
    e = s.len
    if j > e
        return endof(s)
    end
    j -= 1
    @inbounds while j > 0 && Base.is_valid_continuation(codeunit(s,j))
        j -= 1
    end
    j
end

function Base.nextind(s::ManualString, i::Integer)
    j = Int(i)
    if j < 1
        return 1
    end
    e = s.len
    j += 1
    @inbounds while j <= e && Base.is_valid_continuation(codeunit(s,j))
        j += 1
    end
    j
end

Base.byte_string_classify(s::ManualString) =
    ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), s, s.len)

Base.isvalid(::Type{ManualString}, s::ManualString) = byte_string_classify(s) != 0
Base.isvalid(s::ManualString) = isvalid(ManualString, s)

function Base.endof(s::ManualString)
    p = pointer(s)
    i = s.len
    while i > 0 && Base.is_valid_continuation(unsafe_load(p,i))
        i -= 1
    end
    i
end

function Base.length(s::ManualString)
    p = pointer(s)
    cnum = 0
    for i = 1:s.len
        cnum += !Base.is_valid_continuation(unsafe_load(p,i))
    end
    cnum
end

Base.done(s::ManualString, state) = state > s.len

@inline function Base.next(s::ManualString, i::Int)
    @boundscheck if (i < 1) | (i > s.len)
        throw(BoundsError(s,i))
    end
    p = pointer(s)
    b = unsafe_load(p, i)
    if b < 0x80
        return Char(b), i + 1
    end
    return Base.slow_utf8_next(p, b, i, s.len)
end

function Base.reverseind(s::ManualString, i::Integer)
    j = s.len + 1 - i
    p = pointer(s)
    while Base.is_valid_continuation(unsafe_load(p,j))
        j -= 1
    end
    return j
end

Base.isvalid(s::ManualString, i::Integer) =
    (1 <= i <= s.len) && !Base.is_valid_continuation(unsafe_load(pointer(s),i))

function Base.getindex(s::ManualString, r::UnitRange{Int})
    isempty(r) && return ""
    i, j = first(r), last(r)
    l = s.len
    if i < 1 || i > l
        throw(BoundsError(s, i))
    end
    @inbounds si = Base.codeunit(s, i)
    if Base.is_valid_continuation(si)
        throw(UnicodeError(UTF_ERR_INVALID_INDEX, i, si))
    end
    if j > l
        throw(BoundsError())
    end
    j = nextind(s,j)-1
    unsafe_string(pointer(s,i), j-i+1)
end

function Base.search(s::ManualString, c::Char, i::Integer = 1)
    if i < 1 || i > sizeof(s)
        i == sizeof(s) + 1 && return 0
        throw(BoundsError(s, i))
    end
    if Base.is_valid_continuation(Base.codeunit(s,i))
        throw(UnicodeError(UTF_ERR_INVALID_INDEX, i, Base.codeunit(s,i)))
    end
    c < Char(0x80) && return search(s, c%UInt8, i)
    while true
        i = search(s, Base.first_utf8_byte(c), i)
        (i==0 || s[i] == c) && return i
        i = next(s,i)[2]
    end
end

function Base.search(a::ManualString, b::Union{Int8,UInt8}, i::Integer = 1)
    if i < 1
        throw(BoundsError(a, i))
    end
    n = sizeof(a)
    if i > n
        return i == n+1 ? 0 : throw(BoundsError(a, i))
    end
    p = pointer(a)
    q = ccall(:memchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), p+i-1, b, n-i+1)
    q == C_NULL ? 0 : Int(q-p+1)
end

function Base.rsearch(s::ManualString, c::Char, i::Integer = s.len)
    c < Char(0x80) && return rsearch(s, c%UInt8, i)
    b = Base.first_utf8_byte(c)
    while true
        i = rsearch(s, b, i)
        (i==0 || s[i] == c) && return i
        i = prevind(s,i)
    end
end

function Base.rsearch(a::ManualString, b::Union{Int8,UInt8}, i::Integer = s.len)
    if i < 1
        return i == 0 ? 0 : throw(BoundsError(a, i))
    end
    n = sizeof(a)
    if i > n
        return i == n+1 ? 0 : throw(BoundsError(a, i))
    end
    p = pointer(a)
    q = ccall(:memrchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), p, b, i)
    q == C_NULL ? 0 : Int(q-p+1)
end

function Base.string(a::ManualString...)
    if length(a) == 1
        return String(a[1]::ManualString)
    end
    n = 0
    for str in a
        n += str.len
    end
    out = Base._string_n(n)
    offs = 1
    for str in a
        unsafe_copy!(pointer(out,offs), pointer(str), str.len)
        offs += str.len
    end
    return out
end
