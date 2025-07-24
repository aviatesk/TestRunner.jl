# TestRunner.jl

A Julia package for selective test execution using pattern matching.
TestRunner allows you to run specific tests from a test file based on testset
names, test expressions, or line numbers, while ensuring all necessary
dependencies are executed.

## Features

- **Pattern-based test selection**: Run only the tests that match your
  specified patterns
- **Multiple pattern types**: String matching, regex patterns, expression,
   and line number patterns.
- **Fast execution**: Test code is interpreted only at top-level; function
  calls within tests are compiled normally while avoiding execution of unrelated
  test code
- **JSON output**: Machine-readable test results with diagnostics for integration
  with editors and CI systems

## Requirements

- Julia 1.12 or higher

## Installation

```julia-repl
pkg> add https://github.com/aviatesk/TestRunner.jl
```

TestRunner can also be installed as a standalone Julia application:

```julia-repl
pkg> app add https://github.com/aviatesk/TestRunner.jl
```

This will install the `testrunner` executable.
Note that you need to manually make `~/.julia/bin` available on the `PATH`
environment for the executable to be accessible.
See <https://pkgdocs.julialang.org/dev/apps/> for the details.

### Quick Start
```julia-repl
julia> using TestRunner

julia> runtest("demo.jl", ["basic tests"]) # Run tests matching a specific testset name

julia> runtest("demo.jl", ["basic tests", "struct tests"]) # Run multiple testsets

julia> runtest("demo.jl", [:(@test startswith(inner_func2(), "inner"))]) # Run standalone test case
```

Or quivalently via the command line app:
```bash
$ testrunner demo.jl "basic tests"

$ testrunner demo.jl "basic tests" "struct tests"

$ testrunner demo.jl '(:(@test startswith(inner_func2(), "inner")))'
```

## Programmatic Usage

### API

#### `runtest`

```julia
runtest(filename::AbstractString, patterns, lines=(); topmodule::Module=Main)
```

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

#### `runtests`

The package also provides a `runtests` function for advanced use cases like
selectively running package test cases from `test/runtests.jl`, where
you need to specify different patterns for different files in a test suite
that includes multiple files via `include` statements.
See its docstring for detailed usage.

### Pattern Types

#### String Patterns
Match testsets by exact name:
```julia
# Match a testset by name
runtest("demo.jl", ["struct tests"])  # matches any testset whose name is "struct tests"
```

#### Regex Patterns
Match testsets using regular expressions:
```julia
runtest("demo.jl", [r"foo"])  # matches any testset containing "foo"
```

#### Expression Patterns
Match arbitrary Julia expressions using MacroTools patterns:
```julia
runtest("demo.jl", [:(@test startswith(s_, prefix_))])  # matches e.g. `@test startswith(s, "Julia")`
runtest("demo.jl", [:(@test a_ > b_)])                  # matches e.g. `@test x > 0`
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

## App Usage

TestRunner can be installed as a CLI executable (see the [installation](#installation) section):

```bash
# Run specific testsets by name
testrunner mypkg/runtests.jl.jl "basic tests" "advanced tests"

# Run tests on specific lines
testrunner mypkg/runtests.jl.jl L10
testrunner mypkg/runtests.jl.jl L10:20

# Run tests matching expression patterns
testrunner mypkg/runtests.jl.jl ':(@test foo(x_) == y_)'

# Run tests matching regex patterns
testrunner mypkg/runtests.jl.jl r"^test.*basic"

# Run all tests in a file
testrunner mypkg/runtests.jl.jl

# Combine patterns with filter lines
testrunner mypkg/runtests.jl.jl "my tests" --filter-lines=10,15,20:25

# Use verbose output
testrunner -v mypkg/runtests.jl.jl L55:57

# Use a specific project environment
testrunner --project=/path/to/project mypkg/runtests.jl.jl "my tests"

# Show help
testrunner --help

# Output results in JSON format
testrunner --json mypkg/runtests.jl "my tests"
```

Pattern formats:
- `L10` - Run tests on line 10
- `L10:20` - Run tests on lines 10-20
- `:(expr)` - Match expression pattern
- `r"^test.*"` - Match testset names with regex
- `"my tests"` - Match testset by exact name (default)

Options:
- `--project[=<dir>]` - Set project/environment (same format and meaning as Julia's `--project` flag)
- `--filter-lines=1,5,10:20` or `-f=1,5,10:20` - Filter to specific lines
- `--verbose` or `-v` - Show verbose output
- `--json` - Output results in JSON format for machine-readable test results

## Examples

Given this [demo.jl](./demo.jl) file:

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

```julia-repl
julia> using TestRunner
```

Run `@testset "basic tests"`:
```julia-repl
julia> @testset "Basic tests runner" verbose=true runtest("demo.jl", ["basic tests"]);
Test Summary:      | Pass  Broken  Total  Time
Basic tests runner |    2       1      3  0.0s
  basic tests      |    2       1      3  0.0s
```

`@testset` can be selected with regex:
```julia-repl
julia> @testset "Regex runner" verbose=true runtest("demo.jl", [r".*tests"]);
Test Summary:      | Pass  Broken  Total  Time
Regex runner       |   12       1     13  0.0s
  basic tests      |    2       1      3  0.0s
  struct tests     |    2              2  0.0s
  nested tests     |    5              5  0.0s
  calculator tests |    3              3  0.0s
```

Run individual `@test` cases that use the `process` function:
```julia-repl
julia> @testset "Standalone runner" verbose=true runtest("demo.jl", [:(@test process(s_) == n_)]);
Test Summary:     | Pass  Total  Time
Standalone runner |    2      2  0.0s
```

Nested `@testset` can be selected:
```julia-repl
julia> @testset "Nested runner" verbose=true runtest("demo.jl", ["inner tests 1"]);
Test Summary:   | Pass  Total  Time
Nested runner   |    2      2  0.0s
  inner tests 1 |    2      2  0.0s
```

Individual `@test` cases can be selectively matched using pattern expressions:
```julia-repl
julia> @testset "Pattern in nested" verbose=true runtest("demo.jl", [:(@test startswith(s_, prefix_))]);
Test Summary:     | Pass  Total  Time
Pattern in nested |    1      1  0.0s
```

We can run tests by directly specifying line numbers:
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

1. Pattern Matching on AST: Uses JuliaSyntax to parse code and MacroTools
   to match patterns against the syntax tree
2. Line-based Selection: Maps matched AST nodes to source line numbers,
   which serve as the bridge to lowered code
3. Selective Interpretation: Only top-level code is interpreted;
   function calls within tests are compiled and run at normal speed
4. Conservative Dependency Execution: Executes _all_ top-level code except
   `@test` and `@testset` expressions to ensure tests don't fail due to
   missing dependencies

The key insight is that in reasonably-organized test code, the conservative
dependency execution would only run the function and type definitions necessary
for tests, without actual test code executed. Since test execution bottlenecks
are often in the test cases themselves (not in defining functions), TestRunner
allows efficient execution of test cases in interest by skipping execution of
unrelated tests while still ensuring all code dependencies are available.

## Limitations

1. **Source Provenance**: Pattern matching occurs at the surface AST level and
   results are converted to line numbers. However, lowered code representation
   lacks proper source provenance (especially for macro expansions), causing
   surface-level pattern match information to be incorrectly mapped to lowered
   code.

   Example (from [limitation1.jl](./limitations/limitation1.jl)):
   ```julia
   @testset "limitation1" begin
       limitation1() = nothing
       @test isnothing(limitation1()) #=want to run only this=#; @test isnothing(identity(limitation1())) #=but this runs too=#
   end
   ```

   When trying to run only the first test:
   ```julia-repl
   julia> @testset "Limitation1 runner" verbose=true runtest("limitations/limitation1.jl", [:(@test isnothing(limitation1()))]);
   Test Summary:      | Pass  Total  Time
   Limitation1 runner |    2      2  0.0s
   ```

   Both tests are executed (2 tests pass) because they are on the same line. The
   line-based selection mechanism cannot distinguish between multiple expressions
   on the same line.

   **Workaround** (see [workaround1.jl](./limitations/workaround1.jl)): Place
   each `@test` on a separate line:
   ```julia
   @testset "workaround1" begin
       workaround1() = nothing
       @test isnothing(workaround1())             # want to run only this
       @test isnothing(identity(workaround1()))   # now this test is skipped
   end
   ```

   With this workaround:
   ```julia-repl
   julia> @testset "Workaround1 runner" verbose=true runtest("limitations/workaround1.jl", [:(@test isnothing(workaround1()))]);
   Test Summary:      | Pass  Total  Time
   Workaround1 runner |    1      1  0.0s
   ```

   Now only the matched test is executed (1 test passes).

   This limitation will be resolved with JuliaLowering.jl integration, which will
   eliminate the need for crude line number conversion from surface AST pattern
   matches.

2. **Conservative Dependency Execution**: Due to the conservative approach,
   ALL top-level code except `@test` and `@testset` expressions is executed.
   This means individual `@test` cases within function calls cannot be
   selectively executed.

   Example (from [limitation2.jl](./limitations/limitation2.jl)):
   ```julia
   using Test

   function limitation2()
       @test String(nameof(Test)) == "Test"
   end

   limitation2()  # This executes during dependency execution

   @testset "selected test" limitation2()  # This also executes when selected
   ```

   When trying to match the `@testset` pattern, both the direct function call
   and the testset run:
   ```julia-repl
   julia> @testset "limitation2 demo" verbose=true runtest("limitations/limitation2.jl", ["selected test"]);
   Test Summary:     | Pass  Total  Time
   limitation2 demo  |    2      2  0.3s
     selected test   |    1      1  0.0s
   ```

   The test inside `limitation2()` executes twice: once from the top-level
   `limitation2()` call (which executes as part of conservative dependency
   execution) and once from the matched `@testset "selected test"`.

   **Workaround** (see [workaround2.jl](./limitations/workaround2.jl)): Wrap test
   execution code in `@testset` blocks instead of functions, or avoid top-level
   function calls that contain tests.

3. **Tests Within Function Bodies**: Individual `@test` cases within function
   bodies cannot be selectively executed using expression patterns.

   Example (from [limitation3.jl](./limitations/limitation3.jl)):
   ```julia
   function test_arithmetic()
       @test 1 + 1 == 2   # line 10: Can't match this with :(@test 1 + 1 == 2)
       @test 2 * 2 == 4   # line 11: Can't match this with :(@test 2 * 2 == 4)
   end
   ```

   When trying to match a specific `@test` pattern:
   ```julia-repl
   julia> @testset "limitation3 demo" verbose=true runtest("limitations/limitation3.jl", [:(@test 1 + 1 == 2)]);
   Test Summary:    | Total  Time
   limitation3 demo |     0  0.0s
   ```

   No tests execute because the pattern matching doesn't look inside function
   bodies. This happens because:
   - Pattern matching occurs at the AST level where the `@test` is inside
     a function definition
   - Function bodies are not executed during pattern matching
   - Only top-level `@test` expressions or those within `@testset` blocks can
     be matched

   **Workarounds** (see [workaround3.jl](./limitations/workaround3.jl)):

   1. Move tests into `@testset` blocks:
   ```julia
   @testset "arithmetic tests" begin
       @test 1 + 1 == 2   # This CAN be matched with :(@test 1 + 1 == 2)
       @test 2 * 2 == 4
   end
   ```

   2. Call test functions inside `@testset` blocks to make them selectable:
   ```julia
   @testset "function calls" begin
       test_arithmetic()  # Now these tests execute when this testset is selected
   end
   ```

## Development

TestRunner is built on top of:
- [JuliaInterpreter.jl](https://github.com/JuliaDebug/JuliaInterpreter.jl)
  and [LoweredCodeUtils.jl](https://github.com/JuliaDebug/LoweredCodeUtils.jl)
  for selective code execution
- [JuliaSyntax.jl](https://github.com/JuliaLang/JuliaSyntax.jl) for parsing
- [MacroTools.jl](https://github.com/FluxML/MacroTools.jl) for pattern
  matching
