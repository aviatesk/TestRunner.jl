using Test

@testset "TestRunner.jl" begin
    @testset "pattern matching" include("test_pattern_matching.jl")
    @testset "runtest" include("test_runtest.jl")
    let default_value = Test.TESTSET_PRINT_ENABLE[]
        # disable test failure printing from `TestRunnerTestSet`
        Test.TESTSET_PRINT_ENABLE[] = false
        try
            @testset "error handling" include("test_error_handling.jl")
        finally
            Test.TESTSET_PRINT_ENABLE[] = default_value
        end
    end
    @testset "json output" include("test_json_output.jl")
end
