module TestManualalloc

using Base.Test
using ManualMemory

struct Bar
    a::Int
    b::ManualMemory.ManualBitVector
    c::Bool
    d::ManualMemory.ManualVector{Float64}
end

Bar = TestManualalloc.Bar

blen = 10

dlen = 20

c = false

memalloc(size::Integer) = Libc.malloc(size)

@test_throws AssertionError ManualMemory.manual_alloc(Bar, memalloc, Val{(:b, blen)}, Val{(:c,c)}, Val{(:d,dlen)})

@test_throws AssertionError ManualMemory.manual_alloc(Bar, memalloc, Val{(:b, blen)})

bar = ManualMemory.manual_alloc(Bar, memalloc, Val{(:b, blen)}, Val{(:d,dlen)})

@v bar.c = c

@test (@v bar.c) == c
@test (length(@v bar.b)) == 10
@test (length(@v bar.d)) == 20

end
