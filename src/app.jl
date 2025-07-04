module TestRunnerApp

# Import necessary modules
using Test: Test
using MacroTools: MacroTools
using ..TestRunner: runtest
using JSON3: JSON3

# to support precompilation
const app_runner_module = Ref{Union{Module,Nothing}}(nothing)

# Helper functions for colored output
function error_print(msg::AbstractString)
    printstyled(stderr, "Error:", bold=true, color=:red)
    println(stderr, " $msg")
end

function error_print(msg::AbstractString, highlight::AbstractString)
    printstyled(stderr, "Error:", bold=true, color=:red)
    print(stderr, " $msg ")
    printstyled(stderr, highlight, bold=true)
    println(stderr)
end

function info_print(msg::AbstractString)
    printstyled("Info:", bold=true, color=:blue)
    println(" $msg")
end

function info_print(msg::AbstractString, highlight::AbstractString)
    printstyled("Info:", bold=true, color=:blue)
    print(" $msg ")
    printstyled(highlight, bold=true)
    println()
end

function header_print(msg::AbstractString)
    println()
    printstyled("═══ $msg ═══", bold=true, color=:cyan)
    println()
end

function detail_print(msg::AbstractString)
    printstyled("  $msg", color=:light_black)
    println()
end

function error_detail_print(msg::AbstractString)
    printstyled(stderr, "  $msg", color=:light_black)
    println(stderr)
end

function show_error_trace(@nospecialize e)
    error_detail_print("")
    Base.showerror(stderr, e)
    println(stderr)
end

"""
    TestRunnerDiagnostic

Represents a single test diagnostic (failure or error) with minimal information
needed for language server integration.

# Fields
- `filename::String`: Full path to the test file
- `line::Int`: Line number where the test failed/errored (1-based)
- `message::String`: Descriptive message including the original expression and error details
"""
struct TestRunnerDiagnostic
    filename::String
    line::Int
    message::String
end

"""
    TestRunnerStats

Represents the statistical summary of a test run, including counts of different
test outcomes and execution timing information.
"""
@kwdef struct TestRunnerStats
    "Number of tests that passed"
    n_passed::Int = 0
    "Number of tests that failed"
    n_failed::Int = 0
    "Number of tests that errored"
    n_errored::Int = 0
    "Number of tests marked as broken"
    n_broken::Int = 0
    "Test execution time in seconds"
    duration::Float64 = 0.0
end

"""
    TestRunnerResult

Represents the complete result of a test run in JSON format.
"""
@kwdef struct TestRunnerResult
    filename::String
    patterns::Union{Vector{Any}, Nothing} = nothing
    stats::TestRunnerStats
    logs::String = ""
    diagnostics::Vector{TestRunnerDiagnostic} = TestRunnerDiagnostic[]
end

function (@main)(args::Vector{String})
    if isempty(args)
        print_usage()
        return 1
    end

    # Handle help at any position
    if any(arg -> arg == "--help" || arg == "-h", args)
        print_usage()
        return 0
    end

    patterns = String[]
    filename = filter_lines = project = nothing
    verbose = json_output = false

    i = 1
    while i <= length(args)
        arg = args[i]

        if startswith(arg, "--filter-lines=")
            filter_str = arg[16:end]
            parsed_lines = parse_filter_lines(filter_str)
            if parsed_lines === nothing
                return 1
            end
            filter_lines = parsed_lines
        elseif startswith(arg, "-f=")
            filter_str = arg[4:end]
            parsed_lines = parse_filter_lines(filter_str)
            if parsed_lines === nothing
                return 1
            end
            filter_lines = parsed_lines
        elseif startswith(arg, "--project=")
            project = arg[11:end]
        elseif arg == "--project"
            # Handle --project without equals sign (use current directory)
            project = "."
        elseif arg == "--verbose" || arg == "-v"
            verbose = true
        elseif arg == "--json"
            json_output = true
        elseif startswith(arg, "-") && arg != "-"
            error_print("Unknown option:", arg)
            error_detail_print("Run with --help to see available options")
            return 1
        else
            # Not an option, it's either filename or pattern
            if filename === nothing
                filename = arg
            else
                push!(patterns, arg)
            end
        end
        i += 1
    end

    # Check if filename was provided
    if filename === nothing
        error_print("No file path provided")
        println()
        print_usage()
        return 1
    end

    # Parse patterns
    parsed_patterns = parse_patterns(patterns)

    # Check if any pattern was invalid
    if parsed_patterns === nothing
        return 1
    end

    # Run tests
    return runtest_app(filename, parsed_patterns, filter_lines, verbose, project, json_output)
end

function print_usage()
    printstyled("TestRunner", bold=true)
    println(" - Julia test runner with selective execution")
    println("""

    Usage:
      testrunner [options] <path> [patterns...]

    Pattern formats:
      L10         - Run tests on line 10
      L10:20      - Run tests on lines 10-20
      :(expr)     - Match expression pattern (e.g., ':(@test foo(x_) == y_)')
      r"^test.*"  - Match testset names with regex
      "my tests"  - Match testset by exact name (default)

    Options:
      --project[=<dir>]         Set project/environment (same as Julia's --project)
      --filter-lines=1,5,10:20  Filter to specific lines
      -f=1,5,10:20              Short form of --filter-lines
      --verbose, -v             Show verbose output
      --json                    Output results in JSON format
      -h, --help                Show this help message

    Examples:
      testrunner test/runtests.jl
      testrunner test/runtests.jl "basic tests"
      testrunner test/runtests.jl L15:25
      testrunner test/runtests.jl ':(@test length(xs) == 1)'
      testrunner test/runtests.jl r"^test.*" --filter-lines=10:50
      testrunner test/runtests.jl --project=@. "my tests"
      testrunner test/runtests.jl --project=/path/to/project L10:20
      testrunner test/runtests.jl --json
    """)
end

function parse_patterns(patterns::Vector{String})
    parsed = Any[]
    for pattern in patterns
        result = parse_pattern(pattern)
        if result === nothing
            # Invalid pattern, return nothing to indicate failure
            return nothing
        end
        push!(parsed, result)
    end
    return parsed
end

function parse_pattern(pattern::String)
    # Line number pattern: L10 or L10:20
    if startswith(pattern, "L")
        line_spec = pattern[2:end]
        if contains(line_spec, ":")
            parts = split(line_spec, ":", limit=2)
            start_line = tryparse(Int, parts[1])
            end_line = tryparse(Int, parts[2])
            if start_line === nothing || end_line === nothing
                error_print("Invalid line range pattern:", pattern)
                error_detail_print("Expected format: L<start>:<end> where start and end are integers")
                return nothing
            end
            if start_line > end_line
                error_print("Invalid line range (start > end):", pattern)
                error_detail_print("Start line ($start_line) must be less than or equal to end line ($end_line)")
                return nothing
            end
            return start_line:end_line
        else
            line_num = tryparse(Int, line_spec)
            if line_num === nothing
                error_print("Invalid line number pattern:", pattern)
                error_detail_print("Expected format: L<number> where number is an integer")
                return nothing
            end
            return line_num
        end
    # Expression pattern: :(expr)
    elseif startswith(pattern, ":")
        # Parse the expression - require parentheses
        expr_str = pattern[2:end]
        if !startswith(expr_str, "(") || !endswith(expr_str, ")")
            error_print("Expression pattern must be surrounded by parentheses:", pattern)
            error_detail_print("Expected format: :(expression)")
            error_detail_print("Example: :(@test foo(x) == y)")
            return nothing
        end

        # Parse the content inside parentheses
        inner_expr = expr_str[2:end-1]
        try
            parsed = Meta.parse(inner_expr; filename="pattern")
            if isa(parsed, Expr) && parsed.head == :incomplete
                error_print("Incomplete expression pattern:", pattern)
                error_detail_print("The expression appears to be incomplete (missing closing parenthesis, etc.)")
                return nothing
            end
            return parsed
        catch e
            error_print("Invalid expression pattern:", pattern)
            error_detail_print("Failed to parse Julia expression:")
            show_error_trace(e)
            return nothing
        end
    # Regex pattern: r"pattern"
    elseif startswith(pattern, "r\"") && endswith(pattern, "\"")
        # Extract content between quotes (skip 'r"' at start and '"' at end)
        regex_content = pattern[3:end-1]

        # Unescape escaped quotes
        regex_content = replace(regex_content, "\\\"" => "\"")

        try
            return Regex(regex_content)
        catch e
            error_print("Invalid regex pattern:", pattern)
            error_detail_print("Failed to compile regular expression:")
            show_error_trace(e)
            return nothing
        end
    # String pattern (default)
    else
        return pattern
    end
end

function parse_filter_lines(filter_str::String)
    lines = Set{Int}()
    for part in split(filter_str, ",")
        part = strip(part)
        if isempty(part)
            continue
        end

        if contains(part, ":")
            # Range: 10:20
            range_parts = split(part, ":", limit=2)
            start_line = tryparse(Int, strip(range_parts[1]))
            end_line = tryparse(Int, strip(range_parts[2]))
            if start_line === nothing || end_line === nothing
                error_print("Invalid line range in filter:", part)
                error_detail_print("Expected format: <start>:<end> where start and end are integers")
                return nothing
            end
            if start_line > end_line
                error_print("Invalid line range (start > end) in filter:", part)
                error_detail_print("Start line ($start_line) must be less than or equal to end line ($end_line)")
                return nothing
            end
            for line in start_line:end_line
                push!(lines, line)
            end
        else
            # Single line: 10
            line_num = tryparse(Int, part)
            if line_num === nothing
                error_print("Invalid line number in filter:", part)
                error_detail_print("Expected an integer value")
                return nothing
            end
            push!(lines, line_num)
        end
    end
    return lines
end

function parse_project_path(project::String, filename::String)
    if project == "@temp"
        return mktempdir()
    elseif project == "@." || project == "."
        # Search for Project.toml in parent directories
        dir = dirname(abspath(filename))
        while true
            if isfile(joinpath(dir, "Project.toml")) || isfile(joinpath(dir, "JuliaProject.toml"))
                return dir
            end
            parent = dirname(dir)
            if parent == dir  # Reached root
                error("No Project.toml or JuliaProject.toml found in parent directories")
            end
            dir = parent
        end
    elseif startswith(project, "@script")
        # Handle @script or @script<rel> format
        scriptdir = dirname(abspath(filename))
        if project == "@script"
            search_dir = scriptdir
        else
            # Extract relative path from @script<rel>
            rel_path = project[8:end]  # Remove "@script" prefix
            search_dir = normpath(joinpath(scriptdir, rel_path))
        end

        # Search up from script directory
        dir = search_dir
        while true
            if isfile(joinpath(dir, "Project.toml")) || isfile(joinpath(dir, "JuliaProject.toml"))
                return dir
            end
            parent = dirname(dir)
            if parent == dir  # Reached root
                error("No Project.toml or JuliaProject.toml found searching from $search_dir")
            end
            dir = parent
        end
    else
        # Regular directory path
        return project
    end
end

function extract_test_stats_from_exception(ex::Test.TestSetException, duration::Float64)
    return TestRunnerStats(;
        n_passed = ex.pass,
        n_failed = ex.fail,
        n_errored = ex.error,
        n_broken = ex.broken,
        duration)
end

function extract_diagnostics_from_exception(ex::Test.TestSetException)
    diagnostics = TestRunnerDiagnostic[]

    for result in ex.errors_and_fails
        source = result.source
        filename = string(source.file)
        line = source.line

        io = IOBuffer()
        show(io, result)
        message = String(take!(io))

        diagnostic = TestRunnerDiagnostic(filename, line, message)
        push!(diagnostics, diagnostic)
    end

    return diagnostics
end

function runtest_internal(filename::String, patterns::Vector{Any}, filter_lines, verbose::Bool, project)
    # Set `LOAD_PATH` manually: app shim sets limits it by default
    if Base.should_use_main_entrypoint()
        empty!(LOAD_PATH)
        push!(LOAD_PATH, "@", "@v$(VERSION.major).$(VERSION.minor)", "@stdlib")
    else
        # for precompilation
    end

    if verbose
        header_print("Test Setup")
        info_print("Julia version:", string(VERSION))
        info_print("Julia executable:", Sys.BINDIR)
    end

    if project !== nothing
        project_path = parse_project_path(project, filename)
        if verbose
            info_print("Active environment:", project)
            detail_print("Project path: $project_path")
        end
        pushfirst!(LOAD_PATH, project_path)
    end

    bname = basename(filename)

    if verbose
        header_print("Test Configuration")
        info_print("File:", filename)

        if !isempty(patterns)
            info_print("Patterns:")
            for (i, pattern) in enumerate(patterns)
                pattern_str = if isa(pattern, Regex)
                    "Regex: $(pattern.pattern)"
                elseif isa(pattern, AbstractRange)
                    "Lines: $(first(pattern))-$(last(pattern))"
                elseif isa(pattern, Integer)
                    "Line: $pattern"
                elseif isa(pattern, Expr)
                    "Expression: $(pattern)"
                else
                    "String: \"$pattern\""
                end
                detail_print("[$i] $pattern_str")
            end
        end

        if filter_lines !== nothing
            sorted_lines = sort(collect(filter_lines))
            info_print("Filter lines: $(join(sorted_lines, ", "))")
        end

        if isempty(patterns)
            info_print("No patterns specified, running all tests with `include`")
        end

        header_print("Running Tests")
    end

    topmodule = @something(app_runner_module[], Main)
    if isempty(patterns)
        return Test.@testset "$bname" verbose=verbose Base.IncludeInto(topmodule)(filename)
    else
        return Test.@testset "$bname" verbose=verbose runtest(filename, patterns; filter_lines, topmodule)
    end
end

function runtest_json(filename::String, patterns::Vector{Any}, filter_lines, verbose::Bool, project)
    # Redirect stdout to capture ALL output (including info_print, header_print, etc.)
    original_stdout = stdout
    (rd, wr) = redirect_stdout()

    local stats::TestRunnerStats, diagnostics::Vector{TestRunnerDiagnostic}
    start_time = time()
    try
        result = runtest_internal(filename, patterns, filter_lines, verbose, project)
        counts = Test.get_test_counts(result)
        n_passed = counts.passes + counts.cumulative_passes
        n_failed = counts.fails + counts.cumulative_fails
        n_errored = counts.errors + counts.cumulative_errors
        n_broken = counts.broken + counts.cumulative_broken
        duration = result.time_end - result.time_start
        stats = TestRunnerStats(; n_passed, n_failed, n_errored, n_broken, duration)
        diagnostics = TestRunnerDiagnostic[]  # No diagnostics since all tests passed
        return 0
    catch e # Any test failures/errors cause TestSetException to be thrown
        e isa Test.TestSetException || rethrow(e)
        duration = time() - start_time
        stats = extract_test_stats_from_exception(e, duration)
        diagnostics = extract_diagnostics_from_exception(e)
        return 1
    finally
        redirect_stdout(original_stdout)
        close(wr)
        logs = read(rd, String)
        close(rd)
        patterns = isempty(patterns) ? nothing : patterns
        result = TestRunnerResult(;
            filename,
            patterns,
            stats,
            logs,
            diagnostics)
        JSON3.write(stdout, result)
    end
end

function runtest_app(filename::String, patterns::Vector{Any}, filter_lines, verbose::Bool, project, json_output::Bool)
    if !isfile(filename)
        error_print("File not found:", filename)
        return 1
    end
    if json_output
        return runtest_json(filename, patterns, filter_lines, verbose, project)
    else
        runtest_internal(filename, patterns, filter_lines, verbose, project)
        return 0
    end
end

end # module TestRunnerApp
