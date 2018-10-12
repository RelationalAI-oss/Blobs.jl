"A string whose data is stored in a Blob."
struct BlobString <: AbstractString
    data::Blob{UInt8}
    len::Int64 # in bytes
end

Base.pointer(blob::BlobString) = pointer(blob, 1)
function Base.pointer(blob::BlobString, i::Integer)
    # TODO(jamii) would prefer to boundscheck on load, but this will do for now
    getindex(blob.data + (blob.len - 1))
    pointer(blob.data + (i-1))
end

function Base.unsafe_copyto!(blob::BlobString, string::Union{BlobString, String})
    @assert blob.len >= sizeof(string)
    unsafe_copyto!(pointer(blob), pointer(string), sizeof(string))
end

function Base.String(blob::BlobString)
    unsafe_string(pointer(blob), blob.len)
end

# string interface - this is largely copied from Base

Base.sizeof(s::BlobString) = s.len

Base.ncodeunits(s::BlobString) = sizeof(s)
Base.codeunit(s::BlobString) = UInt8

@inline function Base.codeunit(s::BlobString, i::Integer)
    @boundscheck checkbounds(s, i)
    GC.@preserve s unsafe_load(pointer(s, i))
end

## comparison ##

function Base.cmp(a::BlobString, b::BlobString)
    al, bl = sizeof(a), sizeof(b)
    c = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt),
    a, b, min(al,bl))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(al,bl)
end

function Base.:(==)(a::BlobString, b::BlobString)
    al = sizeof(a)
    al == sizeof(b) && 0 == ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, al)
end

## thisind, nextind ##

Base.thisind(s::BlobString, i::Int) = Base._thisind_str(s, i)

Base.nextind(s::BlobString, i::Int) = Base._nextind_str(s, i)

## checking UTF-8 & ACSII validity ##

byte_string_classify(s::BlobString) =
ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), s, sizeof(s))
# 0: neither valid ASCII nor UTF-8
# 1: valid ASCII
# 2: valid UTF-8

## required core functionality ##

Base.@propagate_inbounds function Base.iterate(s::BlobString, i::Int=firstindex(s))
    i > ncodeunits(s) && return nothing
    b = codeunit(s, i)
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return next_continued(s, i, u)
end

function next_continued(s::BlobString, i::Int, u::UInt32)
    u < 0xc0000000 && (i += 1; @goto ret)
    n = ncodeunits(s)
    # first continuation byte
    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16
    # second continuation byte
    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8
    # third continuation byte
    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b); i += 1
    @label ret
    return reinterpret(Char, u), i
end

Base.@propagate_inbounds function Base.getindex(s::BlobString, i::Int)
    b = codeunit(s, i)
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u)
    return getindex_continued(s, i, u)
end

function getindex_continued(s::BlobString, i::Int, u::UInt32)
    if u < 0xc0000000
        # called from `getindex` which checks bounds
        @inbounds isvalid(s, i) && @goto ret
        Base.string_index_err(s, i)
    end
    n = ncodeunits(s)

    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 1
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16

    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 2
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8

    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i) # cont byte 3
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b)
    @label ret
    return reinterpret(Char, u)
end

Base.getindex(s::BlobString, r::UnitRange{<:Integer}) = s[Int(first(r)):Int(last(r))]

function Base.getindex(s::BlobString, r::UnitRange{Int})
    isempty(r) && return ""
    i, j = first(r), last(r)
    @boundscheck begin
        checkbounds(s, r)
        @inbounds isvalid(s, i) || Base.string_index_err(s, i)
        @inbounds isvalid(s, j) || Base.string_index_err(s, j)
    end
    j = nextind(s, j) - 1
    # n = j - i + 1
    # ss = _string_n(n)
    # p = pointer(ss)
    # for k = 1:n
    #     unsafe_store!(p, codeunit(s, i + k - 1), k)
    # end
    # return ss
    BlobString(s.data + (i-1), j-i+1)
end

function Base.length(s::BlobString, i::Int, j::Int)
    @boundscheck begin
        0 < i ≤ ncodeunits(s)+1 || throw(BoundsError(s, i))
        0 ≤ j < ncodeunits(s)+1 || throw(BoundsError(s, j))
    end
    j < i && return 0
    @inbounds i, k = thisind(s, i), i
    c = j - i + (i == k)
    _length(s, i, j, c)
end

Base.length(s::BlobString) = _length(s, 1, ncodeunits(s), ncodeunits(s))

@inline function _length(s::BlobString, i::Int, n::Int, c::Int)
    i < n || return c
    @inbounds b = codeunit(s, i)
    @inbounds while true
        while true
            (i += 1) ≤ n || return c
            0xc0 ≤ b ≤ 0xf7 && break
            b = codeunit(s, i)
        end
        l = b
        b = codeunit(s, i) # cont byte 1
        c -= (x = b & 0xc0 == 0x80)
        x & (l ≥ 0xe0) || continue

        (i += 1) ≤ n || return c
        b = codeunit(s, i) # cont byte 2
        c -= (x = b & 0xc0 == 0x80)
        x & (l ≥ 0xf0) || continue

        (i += 1) ≤ n || return c
        b = codeunit(s, i) # cont byte 3
        c -= (b & 0xc0 == 0x80)
    end
end

## overload methods for efficiency ##

Base.isvalid(s::BlobString, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

