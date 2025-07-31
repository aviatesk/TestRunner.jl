module test_error_handling

using Test
using TestRunner

module ErrorTest end
@testset "Test failure handling" TestRunner.TestRunnerMetaTestSet begin
    testfile = joinpath(@__DIR__, "testfile_error_handling.jl")
    result = try
        @testset TestRunnerTestSet "Test failure testset" runtest(testfile, ["Test failure"]; topmodule=ErrorTest)
    catch e
        e
    end
    @test result isa Test.DefaultTestSet # testset for `TestRunnerMetaTestSet`
    counts = Test.get_test_counts(result)
    @test counts.cumulative_fails == 1
    @test counts.cumulative_passes == counts.cumulative_broken == counts.cumulative_errors == 0
    @test length(result.results) == 1
    results1 = only(result.results)
    @test results1 isa Test.DefaultTestSet # testset for `TestRunnerTestSet`
    @test length(results1.results) == 1
    results11 = only(results1.results)
    @test results11 isa Test.Fail
    @test results11.orig_expr == "sin(0) == π"
    @test results11.test_type === :test
end

module ExceptionTest1 end
@testset "Exception handling 1" TestRunner.TestRunnerMetaTestSet begin
    testfile = joinpath(@__DIR__, "testfile_error_handling.jl")
    result = try
        @testset TestRunnerTestSet "Exception handling testset 1" runtest(testfile, ["Exception inside of `@test` 1"]; topmodule=ExceptionTest1)
    catch e
        e
    end
    @test result isa Test.DefaultTestSet # testset for `TestRunnerMetaTestSet`
    counts = Test.get_test_counts(result)
    @test counts.cumulative_passes == counts.cumulative_errors == 1
    @test counts.cumulative_broken == counts.cumulative_fails == 0
    @test length(result.results) == 1
    results1 = only(result.results)
    @test results1 isa Test.DefaultTestSet # testset for `TestRunnerTestSet`
    @test length(results1.results) == 1
    results11 = only(results1.results)
    @test results11 isa Test.Error
    @test results11.orig_expr == "sin(Inf) == π"
    @test results11.test_type === :test_error
    @test occursin("DomainError with Inf", sprint(show, results11))
    @test occursin("sin_domain_error", results11.backtrace)
end

module ExceptionTest2 end
@testset "Exception handling 2" TestRunner.TestRunnerMetaTestSet begin
    testfile = joinpath(@__DIR__, "testfile_error_handling.jl")
    result = try
        @testset TestRunnerTestSet "Exception handling testset 2" runtest(testfile, ["Exception inside of `@test` 2"]; topmodule=ExceptionTest2)
    catch e
        e
    end
    @test result isa Test.DefaultTestSet # testset for `TestRunnerMetaTestSet`
    counts = Test.get_test_counts(result)
    @test counts.cumulative_passes == counts.cumulative_errors == 1
    @test counts.cumulative_broken == counts.cumulative_fails == 0
    @test length(result.results) == 1
    results1 = only(result.results)
    @test results1 isa Test.DefaultTestSet # testset for `TestRunnerTestSet`
    @test length(results1.results) == 1
    results11 = only(results1.results)
    @test results11 isa Test.Error
    @test results11.orig_expr == "funccall(cos, Inf) == π"
    @test results11.test_type === :test_error
    @test occursin("DomainError with Inf", sprint(show, results11))
    @test occursin("cos_domain_error", results11.backtrace)
end

module ExceptionTest3 end
@testset "Exception handling 3" TestRunner.TestRunnerMetaTestSet begin
    testfile = joinpath(@__DIR__, "testfile_error_handling.jl")
    result = try
        @testset TestRunnerTestSet "Exception handling testset 3" runtest(testfile, ["Exception outside of `@test`"]; topmodule=ExceptionTest3)
    catch e
        e
    end
    @test result isa Test.DefaultTestSet # testset for `TestRunnerMetaTestSet`
    counts = Test.get_test_counts(result)
    @test counts.cumulative_errors == 1
    @test counts.cumulative_broken == counts.cumulative_passes == counts.cumulative_fails == 0
    @test length(result.results) == 1
    results1 = only(result.results)
    @test results1 isa Test.DefaultTestSet # testset for `TestRunnerTestSet`
    @test length(results1.results) == 1
    results11 = only(results1.results)
    @test results11 isa Test.Error
    @test results11.test_type === :nontest_error
    @test occursin("DomainError with Inf", sprint(show, results11))
    @test occursin("sin_domain_error", results11.backtrace)
end

module ExceptionTest4 end
@testset "Exception handling 4" TestRunner.TestRunnerMetaTestSet begin
    testfile = joinpath(@__DIR__, "testfile_error_handling.jl")
    result = try
        @testset TestRunnerTestSet "Exception handling testset 4" runtest(testfile, ["Exception outside of `@testset`"]; topmodule=ExceptionTest4)
    catch e
        e
    end
    @test result isa Test.DefaultTestSet # testset for `TestRunnerMetaTestSet`
    counts = Test.get_test_counts(result)
    @test counts.cumulative_errors == 1
    @test counts.cumulative_broken == counts.cumulative_passes == counts.cumulative_fails == 0
    @test length(result.results) == 1
    results1 = only(result.results)
    @test results1 isa Test.DefaultTestSet # testset for `TestRunnerTestSet`
    @test length(results1.results) == 1
    results11 = only(results1.results)
    @test results11 isa Test.Error
    @test results11.test_type === :test_error
    @test_broken occursin("DomainError with Inf", sprint(show, results11))
    @test_broken occursin("sin_domain_error", results11.backtrace)
end

end # module test_error_handling
