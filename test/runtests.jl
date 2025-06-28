using Test

@testset "TestRunner.jl" begin
    @testset "pattern matching" include("test_pattern_matching.jl")
    @testset "runtest" include("test_runtest.jl")
end
