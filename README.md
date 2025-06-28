# TestRunner.jl

A Julia package for selective test execution using pattern matching.
TestRunner allows you to run specific tests from a test file based on testset
names, test expressions, or line numbers, while ensuring all necessary
dependencies are executed.

## Features

- **Pattern-based test selection**: Run only the tests that match your
  specified patterns
- **Multiple pattern types**: String matching, regex patterns, and expression
  patterns
- **Line-based execution**: Run tests on specific line numbers
- **Dependency-aware execution**: Conservatively executes required top-level
  definitions
- **Fast execution**: Test code is interpreted only at top-level; function
  calls within tests are compiled normally

## Requirements

- Julia 1.12 or higher

## Installation

```julia
using Pkg
Pkg.add(path="/path/to/TestRunner")
```

## Usage

### Basic Usage

```julia
using TestRunner

# Run tests matching a specific testset name
runtest("demo.jl", ["basic tests"])

# Run multiple testsets
runtest("demo.jl", ["basic tests", "struct tests"])
```

### Pattern Types

#### String Patterns
Match testsets by exact name:
```julia
# Match a testset by name
runtest("demo.jl", ["struct tests"])
```

#### Regex Patterns
Match testsets using regular expressions:
```julia
runtest("demo.jl", [r"foo"])  # Matches any testset containing "foo"
```

#### Expression Patterns
Match arbitrary Julia expressions using MacroTools patterns:
```julia
# Match tests of the form: @test f(x) == y
runtest("demo.jl", [:(@test helper_func(x_, y_) == z_)])

# Match tests with specific operators
runtest("demo.jl", [:(@test a_ > b_)])

# Match tests calling specific functions
runtest("demo.jl", [:(@test startswith(s_, prefix_))])
```

#### Line Number Patterns
Directly specify line numbers or ranges to execute:
```julia
# Run code on specific lines
runtest("demo.jl", [10, 20, 30])

# Run code in a line range
runtest("demo.jl", [10:15])

# Combine with other patterns
runtest("demo.jl", ["basic tests", 42, 50:55])
```

### Examples

Given [this test file](./demo.jl):

> demo.jl
```julia
using Test

struct MyStruct
    value::Int
end

function process(s::MyStruct)
    return s.value * 2
end

@testset "basic tests" begin
    @test 1 + 1 == 2
    @test 2 * 2 == 4
    @test_broken 1 + 1 == 3  # This is expected to fail
end

@testset "struct tests" begin
    s = MyStruct(5)
    @test process(s) == 10
    @test s.value == 5
end

# Standalone test
@test process(MyStruct(3)) == 6

@testset "nested tests" begin
    outer_func() = "outer"
    @test outer_func() == "outer"

    @testset "inner tests 1" begin
        inner_func1() = "inner1"
        @test inner_func1() == "inner1"
        @test length(inner_func1()) == 6
    end

    @testset "inner tests 2" begin
        inner_func2() = "inner2"
        @test inner_func2() == "inner2"
        @test startswith(inner_func2(), "inner")
    end
end

@testset "calculator tests" begin
    add(a, b) = a + b
    mul(a, b) = a * b

    @test add(2, 3) == 5    # line 55
    @test mul(3, 4) == 12   # line 56
    @test add(10, 20) == 30 # line 57
end

# More standalone tests
@test 100 - 50 == 50  # line 61
@test sqrt(16) == 4    # line 62
```

You can run specific tests:
```julia-repl
julia> using TestRunner

julia> @testset "Basic tests runner" verbose=true runtest("demo.jl", ["basic tests"]); # Run "basic tests" including @test_broken
Test Summary:      | Pass  Broken  Total  Time
Basic tests runner |    2       1      3  0.0s
  basic tests      |    2       1      3  0.0s

julia> @testset "Standalone runner" verbose=true runtest("demo.jl", [:(@test process(s_) == n_)]); # Run tests that call the process function
Test Summary:     | Pass  Total  Time
Standalone runner |    2      2  0.0s

julia> @testset "Regex runner" verbose=true runtest("demo.jl", [r".*tests"]);
Test Summary:      | Pass  Broken  Total  Time
Regex runner       |   12       1     13  0.0s
  basic tests      |    2       1      3  0.0s
  struct tests     |    2              2  0.0s
  nested tests     |    5              5  0.0s
  calculator tests |    3              3  0.0s

julia> @testset "Nested runner" verbose=true runtest("demo.jl", ["inner tests 1"]); # Run a specific nested testset
Test Summary:   | Pass  Total  Time
Nested runner   |    2      2  0.0s
  inner tests 1 |    2      2  0.0s

julia> @testset "Pattern in nested" verbose=true runtest("demo.jl", [:(@test startswith(s_, prefix_))]); # Match expression patterns within nested testsets
Test Summary:     | Pass  Total  Time
Pattern in nested |    1      1  0.0s
```

### Line Number Patterns

You can run tests by directly specifying line numbers, which is particularly useful for IDE integration:

```julia-repl
julia> @testset "Single line" verbose=true runtest("demo.jl", [56]); # Run only the test on line 56
Test Summary: | Pass  Total  Time
Single line   |    1      1  0.0s

julia> @testset "Line range" verbose=true runtest("demo.jl", [55:57]); # Run tests in lines 55-57
Test Summary: | Pass  Total  Time
Line range    |    3      3  0.0s

julia> @testset "Mixed patterns" verbose=true runtest("demo.jl", ["calculator tests", 61]); # Combine named testsets with line numbers
Test Summary:       | Pass  Total  Time
Mixed patterns      |    4      4  0.0s
  calculator tests  |    3      3  0.0s
```

> [!note]
> Note that the `@testset "xxx runner" verbose=true` part is used only to show
> the test results in an organized way and is not required for TestRunner
> functionality itself.

## How It Works

TestRunner leverages JuliaInterpreter and LoweredCodeUtils to selectively
execute test code:

1. **Pattern Matching on AST**: Uses JuliaSyntax to parse code and MacroTools
   to match patterns against the syntax tree
2. **Line-based Selection**: Maps matched AST nodes to source line numbers,
   which serve as the bridge to lowered code
3. **Selective Interpretation**: Only interprets top-level code; function calls
   within tests are compiled and run at full speed
4. **Conservative Dependencies**: Executes all top-level code except `@test` and
   `@testset` expressions to ensure tests don't fail due to missing dependencies

The key insight is that in reasonably-organized test code, the conservative
dependency execution would only run the function and type definitions necessary
for tests, without actual test code executed. Since test execution bottlenecks
are often in the test cases themselves (not in defining functions), TestRunner
allows efficient execution of test cases in interest by skipping execution of
unrelated tests while still ensuring all code dependencies are available.

## Current Limitations

1. **Source Provenance**: Pattern matching occurs at the surface AST level and
   results are converted to line numbers. However, lowered code representation
   lacks proper source provenance (especially for macro expansions), causing
   surface-level pattern match information to be incorrectly mapped to lowered
   code.

   Example (from `demo.jl`):
   ```julia
   @testset "limitation1" begin
       limitation1() = nothing
       @test isnothing(limitation1()) #=want to run only this=#; @test isnothing(identity(limitation1())) #=but this runs too=#
   end
   ```

   When trying to run only the first test:
   ```julia-repl
   julia> @testset "Limitation1 runner" verbose=true runtest("demo.jl", [:(@test isnothing(limitation1()))]);
   Test Summary:      | Pass  Total  Time
   Limitation1 runner |    2      2  0.0s
   ```

   Both tests are executed (2 tests pass) because they are on the same line. The
   line-based selection mechanism cannot distinguish between multiple expressions
   on the same line.

   **Workaround**: Place each `@test` on a separate line:
   ```julia
   @testset "workaround1" begin
       workaround1() = nothing
       @test isnothing(workaround1())             # want to run only this
       @test isnothing(identity(workaround1()))   # now this test is skipped
   end
   ```

   With this workaround:
   ```julia-repl
   julia> @testset "Workaround1 runner" verbose=true runtest("demo.jl", [:(@test isnothing(workaround1()))]);
   Test Summary:      | Pass  Total  Time
   Workaround1 runner |    1      1  0.0s
   ```

   Now only the matched test is executed (1 test passes).

   This limitation will be resolved with JuliaLowering.jl integration, which will
   eliminate the need for crude line number conversion from surface AST pattern
   matches.

## API

### `runtest(filename, patterns; filter_lines=nothing, topmodule=Main)`

Run tests from a file that match the given patterns and/or are on the
specified lines.

**Arguments:**
- `filename::AbstractString`: Path to the test file
- `patterns`: Patterns to match. Can be strings, regexes, expressions, integers (line numbers),
  or ranges (line ranges)
- `filter_lines=nothing`: Optional line numbers to filter pattern matches. When provided, only
  pattern matches that overlap with these lines will be executed. This is particularly useful for
  IDE integration where clicking on a specific test should run only that test, even when multiple
  tests may match the same pattern
- `topmodule::Module=Main`: Module context for execution (default: `Main`)

**Returns:**
- Test results from the selectively executed tests

## Development

TestRunner is built on top of:
- [JuliaInterpreter.jl](https://github.com/JuliaDebug/JuliaInterpreter.jl)
  and [LoweredCodeUtils.jl](https://github.com/JuliaDebug/LoweredCodeUtils.jl)
  for selective code execution
- [JuliaSyntax.jl](https://github.com/JuliaLang/JuliaSyntax.jl) for parsing
- [MacroTools.jl](https://github.com/FluxML/MacroTools.jl) for pattern
  matching
