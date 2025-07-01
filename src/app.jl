module TestRunnerApp

# Import necessary modules
using Test: Test
using MacroTools: MacroTools
using ..TestRunner: runtest

# ANSI color codes
const RESET = "\033[0m"
const BOLD = "\033[1m"
const RED = "\033[31m"
const GREEN = "\033[32m"
const YELLOW = "\033[33m"
const BLUE = "\033[34m"
const CYAN = "\033[36m"
const GRAY = "\033[90m"

# Helper functions for colored output
error_print(msg) = println(stderr, "$(RED)$(BOLD)Error:$(RESET) $msg")
info_print(msg) = println("$(BLUE)$(BOLD)Info:$(RESET) $msg")
header_print(msg) = println("\n$(CYAN)$(BOLD)═══ $msg ═══$(RESET)")
detail_print(msg) = println("$(GRAY)  $msg$(RESET)")

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

    # Separate filepath, patterns, and options
    filepath = nothing
    patterns = String[]
    filter_lines = nothing
    verbose = false
    project = nothing

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
        elseif startswith(arg, "-") && arg != "-"
            error_print("Unknown option: $(BOLD)$arg$(RESET)")
            detail_print("Run with --help to see available options")
            return 1
        else
            # Not an option, it's either filepath or pattern
            if filepath === nothing
                filepath = arg
            else
                push!(patterns, arg)
            end
        end
        i += 1
    end

    # Check if filepath was provided
    if filepath === nothing
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
    return runtest_app(filepath, parsed_patterns, filter_lines, verbose, project)
end

function print_usage()
    println("""
    $(BOLD)TestRunner$(RESET) - Julia test runner with selective execution

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
      -h, --help                Show this help message

    Examples:
      testrunner test/runtests.jl
      testrunner test/runtests.jl "basic tests"
      testrunner test/runtests.jl L15:25
      testrunner test/runtests.jl ':(@test length(xs) == 1)'
      testrunner test/runtests.jl r"^test.*" --filter-lines=10:50
      testrunner test/runtests.jl --project=@. "my tests"
      testrunner test/runtests.jl --project=/path/to/project L10:20
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
                error_print("Invalid line range pattern: $(BOLD)$pattern$(RESET)")
                detail_print("Expected format: L<start>:<end> where start and end are integers")
                return nothing
            end
            if start_line > end_line
                error_print("Invalid line range (start > end): $(BOLD)$pattern$(RESET)")
                detail_print("Start line ($start_line) must be less than or equal to end line ($end_line)")
                return nothing
            end
            return start_line:end_line
        else
            line_num = tryparse(Int, line_spec)
            if line_num === nothing
                error_print("Invalid line number pattern: $(BOLD)$pattern$(RESET)")
                detail_print("Expected format: L<number> where number is an integer")
                return nothing
            end
            return line_num
        end
    # Expression pattern: :(expr)
    elseif startswith(pattern, ":")
        # Parse the expression - require parentheses
        expr_str = pattern[2:end]
        if !startswith(expr_str, "(") || !endswith(expr_str, ")")
            error_print("Expression pattern must be surrounded by parentheses: $(BOLD)$pattern$(RESET)")
            detail_print("Expected format: :(expression)")
            detail_print("Example: :(@test foo(x) == y)")
            return nothing
        end

        # Parse the content inside parentheses
        inner_expr = expr_str[2:end-1]
        try
            parsed = Meta.parse(inner_expr; filename="pattern")
            if isa(parsed, Expr) && parsed.head == :incomplete
                error_print("Incomplete expression pattern: $(BOLD)$pattern$(RESET)")
                detail_print("The expression appears to be incomplete (missing closing parenthesis, etc.)")
                return nothing
            end
            return parsed
        catch e
            error_print("Invalid expression pattern: $(BOLD)$pattern$(RESET)")
            detail_print("Failed to parse Julia expression:")
            print(stderr, "$(GRAY)  ")
            Base.showerror(stderr, e)
            println(stderr, "$(RESET)")
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
            error_print("Invalid regex pattern: $(BOLD)$pattern$(RESET)")
            detail_print("Failed to compile regular expression:")
            print(stderr, "$(GRAY)  ")
            Base.showerror(stderr, e)
            println(stderr, "$(RESET)")
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
                error_print("Invalid line range in filter: $(BOLD)$part$(RESET)")
                detail_print("Expected format: <start>:<end> where start and end are integers")
                return nothing
            end
            if start_line > end_line
                error_print("Invalid line range (start > end) in filter: $(BOLD)$part$(RESET)")
                detail_print("Start line ($start_line) must be less than or equal to end line ($end_line)")
                return nothing
            end
            for line in start_line:end_line
                push!(lines, line)
            end
        else
            # Single line: 10
            line_num = tryparse(Int, part)
            if line_num === nothing
                error_print("Invalid line number in filter: $(BOLD)$part$(RESET)")
                detail_print("Expected an integer value")
                return nothing
            end
            push!(lines, line_num)
        end
    end
    return lines
end

function parse_project_path(project::String, filepath::String)
    if project == "@temp"
        # Create temporary environment
        return mktempdir()
    elseif project == "@." || project == "."
        # Search for Project.toml in parent directories
        dir = dirname(abspath(filepath))
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
        scriptdir = dirname(abspath(filepath))
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

function runtest_app(filepath::String, patterns::Vector{Any}, filter_lines, verbose::Bool, project)
    if !isfile(filepath)
        error_print("File not found: $(BOLD)$filepath$(RESET)")
        return 1
    end

    # Handle project activation
    if project !== nothing
        try
            project_path = parse_project_path(project, filepath)
            if verbose
                info_print("Activating project: $(BOLD)$project$(RESET)")
                detail_print("Project path: $project_path")
            end
            pushfirst!(LOAD_PATH, project_path)
        catch e
            error_print("Failed to activate project: $(BOLD)$project$(RESET)")
            print(stderr, "$(GRAY)  ")
            Base.showerror(stderr, e)
            println(stderr, "$(RESET)")
            return 1
        end
    end

    filename = basename(filepath)

    if verbose
        header_print("Test Configuration")
        info_print("File: $(BOLD)$filepath$(RESET)")

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

        header_print("Running Tests")
    end

    try
        result = if verbose
            Test.@testset "$filename" verbose=true runtest(filepath, patterns; filter_lines)
        else
            Test.@testset "$filename" runtest(filepath, patterns; filter_lines)
        end
        return 0
    catch e
        Base.display_error(e, catch_backtrace())
        return 1
    end
end

end # module TestRunnerApp
