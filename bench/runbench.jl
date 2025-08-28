using Blobs, BenchmarkTools

@info "------- Benchmark Runtimes ---------"

@eval struct MixedStruct10
    $((:($(Symbol("f$i"))::Float64) for i in 1:5)...)
    $((:($(Symbol("x$i"))::Int64) for i in 1:5)...)
end
m10 = Blobs.malloc(MixedStruct10)

@eval struct MixedStruct100
    $((:($(Symbol("f$i"))::Float64) for i in 1:50)...)
    $((:($(Symbol("x$i"))::Int64) for i in 1:50)...)
end
m100 = Blobs.malloc(MixedStruct100)

@btime Blobs.malloc(MixedStruct10)
@btime Blobs.malloc(MixedStruct100)

@btime $(m10)[]
@btime $(m100)[]

@btime $(m10)[] = $(m10[])
@btime $(m100)[] = $(m100[])

@btime $(m10).x5[]
@btime $(m100).x5[]
@btime $(m100).x50[]

@btime $(m10).f5[] = 0
@btime $(m10).x5[] = 0
@btime $(m100).f5[] = 0
@btime $(m100).x5[] = 0
@btime $(m100).x50[] = 0


@info "------- Benchmark Compile Times ---------"

# Benchmark Compile Times:
function eval_type(N)
    S = gensym("MixedType$N")
    @eval struct $S
        $((:($(Symbol("f$i"))::Float64) for i in 1:(N÷2) )...)
        $((:($(Symbol("x$i"))::Int64) for i in 1:(N÷2) )...)
    end
    return @eval($S)
end

for N in (10,100)
    @info " --  N = $N -- "

    @btime Blobs.malloc(S) setup=(S=eval_type($N))

    @btime (Blobs.malloc(S))[] setup=(S=eval_type($N))

    @btime (Blobs.malloc(S))[] = (Blobs.malloc(S)[]) setup=(S=eval_type($N))

    @btime (Blobs.malloc(S)).x5[] setup=(S=eval_type($N))
    if N >= 100
        @btime (Blobs.malloc(S)).x50[] setup=(S=eval_type($N))
    end

    @btime (Blobs.malloc(S)).f5[] = 0 setup=(S=eval_type($N))
    @btime (Blobs.malloc(S)).x5[] = 0 setup=(S=eval_type($N))
    if N >= 100
        @btime (Blobs.malloc(S)).x50[] = 0 setup=(S=eval_type($N))
    end

end
