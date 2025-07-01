module test_runtest

using Test
using TestRunner
using TestRunner: JS

const TESTFILE = normpath(pkgdir(TestRunner), "test", "testfile.jl")
@test isfile(TESTFILE)

module SimpleRunnerModule end
@testset "simple" begin
    result = @testset "simple runner" runtest(TESTFILE, ("simple",); topmodule=SimpleRunnerModule)
    @test length(result.results) == 1
    @test only(result.results).n_passed == 2
    @test only(only(result.results).results) isa Test.Broken
end

module StandaloneRunnerModule end
@testset "standalone" begin
    result = @testset "standalone runner" runtest(TESTFILE, (:(@test standalone_test_func(π) ≈ 0),); topmodule=StandaloneRunnerModule)
    @test length(result.results) == 0
    @test result.n_passed == 1
end

module IncludeRunnerModule end
@testset "automatic `include` execution" begin
    result = @testset "automatic `include` execution runner" runtest(TESTFILE, (:(@test included_test_func(π) ≈ 0),); topmodule=IncludeRunnerModule)
    @test length(result.results) == 0
    @test result.n_passed == 1
end

module DependencyRunnerModule end
@testset "top-level dependency execution" begin
    # Test that top-level code (const, push!, etc.) is executed even when running specific tests
    result = @testset "dependency execution runner" runtest(TESTFILE, ("dependency execution",); topmodule=DependencyRunnerModule)
    @test length(result.results) == 1
    @test only(result.results).n_passed == 2
end

module ModuleHandlingModule end
let testmodule_file = normpath(pkgdir(TestRunner), "test", "testfile_module.jl")
    @test isfile(testmodule_file)
    result = @testset "module test runner" runtest(testmodule_file, (:(@test sin(0) == 0),); topmodule=ModuleHandlingModule)
    @test result.n_passed == 1
end

module Nested1RunnerModule end
module Nested2RunnerModule end
@testset "nested testsets" begin
    # Test running a specific nested testset by name
    let result = @testset "nested1 runner" runtest(TESTFILE, ("nested1",); topmodule=Nested1RunnerModule)
        @test length(result.results) == 1
        @test only(result.results).n_passed == 2
        @test only(only(result.results).results) isa Test.Broken
    end

    # Test running another nested testset
    let result = @testset "nested2 runner" runtest(TESTFILE, ("nested2",); topmodule=Nested2RunnerModule)
        @test length(result.results) == 1
        @test only(result.results).n_passed == 2
    end
end

module PatternNestedRunnerModule end
@testset "pattern matching in nested" begin
    # Test expression pattern matching within nested testsets
    result = @testset "pattern in nested1 runner" runtest(TESTFILE, (:(@test nestedfunc1(x_) ≈ y_),); topmodule=PatternNestedRunnerModule)
    @test result.n_passed == 1
    @test length(result.results) == 0
end

module BrokenTestsRunnerModule end
@testset "@test_broken handling" begin
    # Test that @test_broken is properly handled
    result = @testset "broken tests runner" runtest(TESTFILE, ("simple",); topmodule=BrokenTestsRunnerModule)
    @test length(result.results) == 1
    @test only(result.results).n_passed == 2
    @test only(only(result.results).results) isa Test.Broken
end

module SyntaxErrorModule end
@testset "syntax error handling" begin
    # Test that syntax errors in user files are properly reported
    syntax_error_file = normpath(pkgdir(TestRunner), "test", "testfile_syntax_error.jl")
    @test isfile(syntax_error_file)

    @test_throws JS.ParseError runtest(syntax_error_file, ["syntax error test"]; topmodule=SyntaxErrorModule)

    # Verify the error is properly formatted
    io = IOBuffer()
    try
        runtest(syntax_error_file, ["syntax error test"]; topmodule=SyntaxErrorModule)
    catch err
        Base.showerror(io, err)
    end
    s = String(take!(io))
    @test occursin("ParseError", s)
    @test occursin("Expected `]` or `,`", s)
end

module LineFilterModule1 end
module LineFilterModule2 end
@testset "line number based filtering" begin
    # Test that lines argument filters pattern matches correctly
    line_filter_file = normpath(pkgdir(TestRunner), "test", "testfile_line_filter.jl")
    @test isfile(line_filter_file)
    # Without line filter, both tests should match
    let result = @testset "without line filter" runtest(line_filter_file, [:(@test startswith(s, "julia"))]; topmodule=LineFilterModule1)
        @test result.n_passed == 2
    end

    # With line filter specifying line 5, only the first test should run
    let result = @testset "with line filter" runtest(line_filter_file, [:(@test startswith(s, "julia"))]; filter_lines=[5], topmodule=LineFilterModule2)
        @test result.n_passed == 1
    end
end

module LinePatternModule1 end
module LinePatternModule2 end
module LinePatternModule3 end
@testset "line number patterns" begin
    # Test that integer and range patterns work
    line_pattern_file = normpath(pkgdir(TestRunner), "test", "testfile_line_patterns.jl")
    @test isfile(line_pattern_file)

    # Test single line number
    let result = @testset "single line" runtest(line_pattern_file, [4]; topmodule=LinePatternModule1)
        @test result.n_passed == 1  # Only line 4 test
    end

    # Test line range - when selecting lines inside a testset, the whole testset runs
    let result = @testset "line range" runtest(line_pattern_file, [9:15]; topmodule=LinePatternModule2)
        @test length(result.results) == 1
        @test only(result.results).n_passed == 2
    end

    # Test single line number within test set
    let result = @testset "line range" runtest(line_pattern_file, [12]; topmodule=LinePatternModule2)
        @test result.n_passed == 1  # The standalone test on line 12
    end

    # Test combining line numbers with other patterns
    let result = @testset "mixed patterns" runtest(line_pattern_file, ["math tests", 18]; topmodule=LinePatternModule3)
        # "math tests" testset (2 tests) + line 17 standalone test (1 test)
        @test result.n_passed == 1  # The standalone test on line 18
        @test length(result.results) == 1  # The "math tests" testset
        @test only(result.results).n_passed == 2  # Tests in "math tests"
    end
end

# Test local dependency tracking
module DependencyModule1 end
module DependencyModule2 end
let dependency_file = joinpath(@__DIR__, "testfile_dependency_tracking.jl")
    let result = @testset "dependency tracking 1" runtest(dependency_file, [:(@test length(xs1) == 1)]; topmodule=DependencyModule1)
        @test result.n_passed == 1
    end
    let result = @testset "dependency tracking 2" runtest(dependency_file, [:(@test length(xs2) == 2)]; topmodule=DependencyModule2)
        @test result.n_passed == 1
    end
end

end # module test_runtest
