# Formatting
- When writing Julia code, use `4 whitespaces` for indentation and try to keep
  the maximum line length under `92` characters.
- When writing Markdown text, use `2 whitespaces` for indentation and try to
  keep the maximum line length under `80` characters.
- When writing commit messages, follow the format `component: brief summary` for
  the title. In the body of the commit message, provide a brief prose summary of
  the purpose of the changes made.
  Also, ensure that the maximum line length never exceeds 72 characters.
  When referencing external GitHub PRs or issues, use proper GitHub interlinking
  format (e.g., `owner/repo#123` for PRs/issues).

# Coding Rules
- When writing functions, use the most restrictive signature type possible.
  This allows JET to easily catch unintended errors.
  Of course, when prototyping, it's perfectly fine to start with loose type
  declarations, but for the functions you ultimately commit, it's desirable to
  use type declarations as much as possible.
  Especially when AI agents suggest code, please make sure to clearly
  specify the argument types that functions expect.
  In situations where there's no particular need to make a function generic, or
  if you're unsure what to do, submit the function with the most restrictive
  signature type you can think of.

- Only include comments where truly necessary.
  When the function name or implementation clearly indicates its purpose or
  behavior, redundant comments are unnecessary.

- On the other hand, for general utilities that expected to be used in multiple
  places in the language server, it's fine to use docstrings to clarify their
  behavior. However, even in these cases, if the function name and behavior are
  self-explanatory, no special docstring is needed.

- Prefer qualified module access over importing symbols directly into the current namespace.
  This means using `ModuleName.name` instead of `using ModuleName: name`.
  Also, when introducing the name of `ModuleName`, use the pattern
  `using ModuleName: ModuleName` (note that `using` instead of `import`).
  For commonly used modules, shortened names may be used instead of `ModuleName`,
  e.g. `MN` instead of `ModuleName`.

# Running Test Code
Please make sure to test new code when you wrote.

If explicit test file or code is provided, prioritize running that.
Otherwise, you can run the entire test suite for the JETLS project by executing
`using Pkg; Pkg.test()` from the root directory of this repository.

For example, if you receive a prompt like this:
> Improve the error message of diagnostics.
> Use test/test_pattern_matching for the test cases.

The command you should run is:
```
$ julia --startup-file=no -e 'using Test; @testset "pattern_matching" include("test/test_pattern_matching")'
```
Note that the usage of the `--startup-file=no` flag, which avoids loading
unnecessary startup utilities.

# About Test Code

Test code for this package should be written in files that define independent
module spaces with a `test_` prefix.
Then include these files from [`test/runtests.jl`](./test/runtests.jl).
This ensures that these files can be run independently from the REPL.
For example, test code for the "pattern_matching" feature would be in a file like
this:
> test/pattern_matching.jl
```julia
module pattern_matching
using Test # Each module space needs to explicitly declare the code needed for execution
...
end # module pattern_matching
```
And `test/test_pattern_matching.jl` is included from `test/runtests.jl` like this:
> test/runtests.jl
```julia
@testset "TestRunner.jl" begin
   ...
   @testset "pattern_matching" include("test_pattern_matching.jl")
   ...
end
```

Also, in each test file, you are encouraged to use `let`-blocks to ensure that
names aren't unintentionally reused between multiple test cases:
> test/test_completions.jl
```julia
module test_pattern_matching
using Test # Each module space needs to explicitly declare the code needed for execution
function test_something(s::AbstractString)
    ...
end
let s = "..."
    @test test_something(s)
end
let s = "..."
    @test test_something(s)
end
end # module test_pattern_matching
```
Here, `test_something` is defined at the top level of the `test_pattern_matching`
module because it's a common routine used by multiple test cases, but variables
like `s` that are created for each test case are localized using `let`.

# About Modifications to Code You've Written
If you, as an AI agent, add or modify code, and the user appears to have made
further manual changes to that code after your response, please respect those
modifications as much as possible.
For example, if the user has deleted a function you wrote, do not reintroduce
that function in subsequent code generation.
If you believe that changes made by the user are potentially problematic,
please clearly explain your concerns and ask the user for clarification.
