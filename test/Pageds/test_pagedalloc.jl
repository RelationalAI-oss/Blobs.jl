using Base.Test
using Delve
using Delve.Pageds

module TestPagedalloc
import Delve.Pageds

struct Bar
    a::Int
    b::Pageds.PagedBitVector
    c::Bool
    d::Pageds.PagedVector{Float64}
end
end

Bar = TestPagedalloc.Bar

blen = 10

dlen = 20

c = false

memalloc(size::Integer) = Libc.malloc(size)

@test_throws AssertionError Pageds.pagedalloc(Bar, memalloc, Val{(:b, blen)}, Val{(:c,c)}, Val{(:d,dlen)})

@test_throws AssertionError Pageds.pagedalloc(Bar, memalloc, Val{(:b, blen)})

bar = Pageds.pagedalloc(Bar, memalloc, Val{(:b, blen)}, Val{(:d,dlen)})

@v bar.c = c

@test (@v bar.c) == c
@test (length(@v bar.b)) == 10
@test (length(@v bar.d)) == 20
