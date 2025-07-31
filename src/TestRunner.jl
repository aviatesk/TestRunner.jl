module TestRunner

export runtest, runtests, TestRunnerTestSet

using Core.IR
using Compiler: Compiler as CC
using JuliaInterpreter: JuliaInterpreter as JI
using LoweredCodeUtils: LoweredCodeUtils as LCU
using JuliaSyntax: JuliaSyntax as JS
using MacroTools: MacroTools
using Test: Test

const BacktraceElm = Union{Ptr{Nothing},Base.InterpreterIP}
const ExceptionFrame = @NamedTuple{exception::Any,backtrace::Vector{BacktraceElm}}

struct TRInterpreter <: JI.Interpreter
    # constant across execution
    patterns::Dict{String,Vector{Any}}   # absolute path => patterns
    filter_lines::Dict{String,Set{Int}}  # absolute path => filter lines
    # constant across per-file execution
    filename::String # absolute path
    context::Module
    current_exceptions::Vector{ExceptionFrame}
end
function TRInterpreter(interp::TRInterpreter;
                       patterns::Dict{String,Vector{Any}} = interp.patterns,
                       filter_lines::Dict{String,Set{Int}} = interp.filter_lines,
                       filename::String = interp.filename,
                       context::Module = interp.context,
                       current_exceptions::Vector{ExceptionFrame} = interp.current_exceptions)
    return TRInterpreter(patterns, filter_lines, filename, context, current_exceptions)
end

global current_interpreter::TRInterpreter

const errors_and_fails = Dict{Union{Test.Error,Test.Fail},Vector{Any}}()

include("TestRunnerTestSet.jl")

"""
    runtest(filename::AbstractString, patterns, lines=(); topmodule::Module=Main)

Run tests from a file that match the given patterns and/or are on the specified lines.

This function selectively executes test code based on pattern matching and line numbers.
Only the tests that match the criteria are run, along with necessary dependencies like
function definitions, imports, and struct definitions.

# Arguments
- `filename::AbstractString`: Path to the test file to run
- `patterns`: Collection of patterns to match against. Can include:
  - Strings: Match `@testset` names exactly (e.g., `"my test"`)
  - Regex: Match `@testset` names by pattern (e.g., `r"test.*"`)
  - Expressions: Match arbitrary Julia code using MacroTools patterns (e.g., `:(@test f_(x_) == y_)`)
  - Integers: Execute code on specific line numbers (e.g., `42`)
  - Ranges: Execute code on line ranges (e.g., `10:15`)
- `filter_lines=nothing`: Optional collection of line numbers to filter pattern matches.
  When provided, only pattern matches that overlap with these lines will be executed
- `topmodule::Module=Main`: Module context for execution (default: `Main`)

# Returns
Test results from the selectively executed tests, compatible with Julia's Test.jl framework.

# Examples
```julia
# Run a specific testset by name
runtest("testfile.jl", ["my tests"])

# Run tests matching a regex pattern
runtest("testfile.jl", [r"integration.*"])

# Run tests that match an expression pattern
runtest("testfile.jl", [:(@test startswith(s_, "prefix"))])

# Run tests on specific lines
runtest("testfile.jl", [10, 20, 30])

# Run tests in a line range
runtest("testfile.jl", [10:15])

# Combine different pattern types
runtest("testfile.jl", ["unit tests", r"helper.*", 42])
```

# Notes
- All top-level code (except @test and @testset) is automatically executed
- Only top-level code is interpreted; function calls within tests are compiled for performance
- When a pattern matches within a testset, currently all tests in that testset are executed
  due to limitations in source provenance tracking
- If an empty patterns collection is provided, only non-test top-level code will be executed
  (no `@test` or `@testset` expressions will run). This includes all function definitions,
  imports, and other setup code, including any `include` statements
"""
function runtest(filename::AbstractString, patterns;
                 filter_lines=nothing,
                 topmodule::Module=Main)
    filepath = abspath(filename)
    patterns = Dict{String,Vector{Any}}(filepath => Any[pat for pat in patterns])
    if isnothing(filter_lines)
        filter_lines = Dict{String,Set{Int}}()
    else
        filter_lines = Dict{String,Set{Int}}(filepath => Set{Int}(filter_lines))
    end
    interp = TRInterpreter(patterns, filter_lines, filepath, topmodule, ExceptionFrame[])
    global current_interpreter = interp
    empty!(errors_and_fails)
    _selective_run(interp)
end

"""
    runtests(entryfilename::AbstractString, patterns;
             filter_lines=nothing,
             topmodule::Module=Main)

Run tests from multiple files with file-specific pattern matching configurations.

This function allows you to specify different patterns for different files, enabling
fine-grained control over which tests run in each file. This is particularly useful
for test suites that include multiple test files via `include` statements.

# Arguments
- `entryfilename::AbstractString`: Path to the entry point test file (e.g., "test/runtests.jl")
- `patterns`: A collection of `filename => patterns_collection` pairs that specify which
  patterns to match in each file. For example:
  ```julia
  patterns = [
      "test/runtests.jl" => ["integration tests"],
      "test/unit_tests.jl" => [r"fast.*", :(@test foo(x_) == y_)],
      "test/perf_tests.jl" => [50:100]  # run tests on lines 50-100
  ]
  ```
  Files not listed in this dictionary will have all their top-level code executed
  (excluding `@test` and `@testset` expressions)
- `filter_lines=nothing`: Optional collection of `filename => line_numbers` pairs that
  specify line-based filtering for each file. When provided for a file, only pattern matches
  that overlap with the specified lines will be executed in that file
- `topmodule::Module=Main`: Module context for execution (default: `Main`)

# Returns
Test results from the selectively executed tests across all files.

# Examples
```julia
# Run specific tests in different included files
runtests("test/runtests.jl", [
    "test/runtests.jl" => ["basic tests"],
    "test/integration.jl" => [r"api.*"],
    "test/utils.jl" => [:(@test validate(x_))]
])

# Run tests on specific lines in different files
runtests("test/runtests.jl", [
    "test/runtests.jl" => [],  # no tests in entry file
    "test/core.jl" => [10:50, 100:150],
    "test/edge_cases.jl" => [25, 30, 35]
])

# Combine with line filtering for precise control
runtests("test/runtests.jl",
    ["test/core.jl" => ["important tests"]],
    filter_lines=["test/core.jl" => [45, 46, 47]]
)
```

# Notes
- The entry file is always executed starting from `entryfilename`
- Files included via `include()` statements will be discovered and processed automatically
- For files not specified in `patterns`, all non-test top-level code is executed
  (no @test or @testset expressions will run)
- Pattern types for each file follow the same rules as `runtest`:
  strings, regexes, expressions, integers, and ranges
"""
function runtests(entryfilename::AbstractString, patterns_for_files;
                  filter_lines_for_files=nothing,
                  topmodule::Module=Main)
    patterns = Dict{String,Vector{Any}}()
    for (filepath, pats) in patterns_for_files
        patterns[abspath(filepath)] = Any[pat for pat in pats]
    end
    filter_lines = Dict{String,Set{Int}}()
    if !isnothing(filter_lines_for_files)
        for (filepath, lines) in filter_lines_for_files
            filter_lines[abspath(filepath)] = Set{Int}(lines)
        end
    end
    filepath = abspath(entryfilename)
    interp = TRInterpreter(patterns, filter_lines, filepath, topmodule, ExceptionFrame[])
    global current_interpreter = interp
    empty!(errors_and_fails)
    _selective_run(interp)
end

function _selective_run(interp::TRInterpreter)
    filename = interp.filename
    isfile(filename) || throw(SystemError(lazy"opening file \"$filename\"", 2, nothing))
    toptext = read(filename, String)
    stream = JS.ParseStream(toptext)
    JS.parse!(stream; rule=:all)
    isempty(stream.diagnostics) || throw(JS.ParseError(stream))
    sntop = JS.build_tree(JS.SyntaxNode, stream; filename)
    _selective_run(interp, sntop)
end

function _selective_run(interp::TRInterpreter, sntop::JS.SyntaxNode)
    vnodes = JS.SyntaxNode[]
    if JS.kind(sntop) == JS.K"toplevel"
        for i = JS.numchildren(sntop):-1:1
            push!(vnodes, sntop[i])
        end
    else
        push!(vnodes, sntop)
    end

    context = interp.context
    while !isempty(vnodes)
        node = pop!(vnodes)
        lnn = LineNumberNode(JS.source_line(node), interp.filename)

        if JS.kind(node) == JS.K"module"
            @assert JS.numchildren(node) == 2 "malformed `module` AST"
            ModuleName, newsntop = JS.children(node)
            isbare = JS.has_flags(node, JS.BARE_MODULE_FLAG)
            newcontext = Core.eval(context, Expr(:module, !isbare, Expr(ModuleName), Expr(:block, lnn)))
            newinterp = TRInterpreter(interp; context=newcontext)
            for newsn in JS.children(newsntop)
                _selective_run(newinterp, newsn)
            end
            continue
        end

        # Check if this is a top-level @testset or @test
        expr = Expr(node)
        is_test_expr = is_testset_or_test(expr)

        # TODO Handle expanded module expression once JL is integrated
        # For the meanwhile, we should also raise an error to indicate that
        # TestRunner fails to selectively execute such code.

        patterns = get(interp.patterns, interp.filename, nothing)

        if !isnothing(patterns) && is_test_expr
            # For @testset and @test, use pattern matching
            lines = Set{Int}()
            matched_lines!(lines, node, patterns, get(interp.filter_lines, interp.filename, nothing))

            expr = Expr(:block, expr, lnn)
            lwr = Meta.lower(context, expr)

            if !Meta.isexpr(lwr, :thunk)
                Core.eval(context, lwr)
                continue
            end
            src = only(lwr.args)::CodeInfo

            concretized = falses(length(src.code))
            select_statements!(interp, concretized, src, context, lines)

            frame = JI.Frame(interp.context, src)
            LCU.selective_eval_fromstart!(interp, frame, concretized, #=istoplevel=#true)
        else
            # Unconditionally execute non-test top-level code,
            # or no patterns are specified for this file.
            # Note: We use `JI.finish!` here instead of `Core.eval`
            # to ensure proper handling of `include` statements through our
            # custom `evaluate_call!` implementation
            lwr = Meta.lower(context, expr)

            if !Meta.isexpr(lwr, :thunk)
                Core.eval(context, lwr)
                continue
            end
            src = only(lwr.args)::CodeInfo

            frame = JI.Frame(context, src)
            JI.finish!(interp, frame, #=istoplevel=#true)
        end
    end
end

function traverse(f, node::JS.SyntaxNode)
    stack = JS.SyntaxNode[node]
    while !isempty(stack)
        current = pop!(stack)
        f(current)
        for i = JS.numchildren(current):-1:1
            push!(stack, current[i])
        end
    end
end

function matched_lines!(lines::Set{Int}, sn::JS.SyntaxNode, patterns::Vector{Any},
                        filter_lines::Union{Nothing,Set{Int}}=nothing)
    # First, handle line number patterns (Int and UnitRange{Int})
    for pattern in patterns
        if pattern isa Integer
            push!(lines, pattern)
        elseif pattern isa UnitRange{<:Integer}
            for line in pattern
                push!(lines, line)
            end
        end
    end

    # Then, handle other patterns
    traverse(sn) do node::JS.SyntaxNode
        expr = Expr(node)
        if matches_pattern(expr, patterns)
            sourcefile = JS.sourcefile(node)
            first_line = JS.source_line(sourcefile, JS.first_byte(node))
            last_line = JS.source_line(sourcefile, JS.last_byte(node))

            # If filter_lines is provided, only include matches that overlap with specified lines
            if filter_lines === nothing
                push!(lines, (first_line:last_line)...)
            else
                for line in first_line:last_line
                    if line in filter_lines
                        push!(lines, (first_line:last_line)...)
                        break
                    end
                end
            end
        end
    end
    return lines
end

function matches_pattern(@nospecialize(expr), patterns::Vector{Any})
    for pattern in patterns
        if pattern isa Integer || pattern isa UnitRange{<:Integer}
            # Skip line number patterns - they are handled separately
            continue
        elseif pattern isa AbstractString || pattern isa Regex
            # Match @testset names
            if matches_named_testset_call(pattern, expr)
                # @info "Matched" pattern expr
                return true
            end
        elseif MacroTools.@capture(expr, $pattern)
            # @info "Matched" pattern expr
            return true
        end
    end
    return false
end

function matches_named_testset_call(pat::Union{AbstractString,Regex}, @nospecialize ex)
    MacroTools.@capture(ex, @testset String_ xs__) || return false
    return pat isa Regex ? occursin(pat, String) : pat == String
end

function is_testset_or_test(@nospecialize expr)
    # Check if expression is a test-related macro call
    return MacroTools.@capture(expr, @inferred(xs__)) ||
           MacroTools.@capture(expr, @test(xs__)) ||
           MacroTools.@capture(expr, @test_broken(xs__)) ||
           MacroTools.@capture(expr, @test_deprecated(xs__)) ||
           MacroTools.@capture(expr, @test_logs(xs__)) ||
           MacroTools.@capture(expr, @test_warn(xs__)) ||
           MacroTools.@capture(expr, @test_skip(xs__)) ||
           MacroTools.@capture(expr, @test_throws(xs__)) ||
           MacroTools.@capture(expr, @testset(xs__))
end

function select_statements!(interp::TRInterpreter, concretized::BitVector, src::CodeInfo, mod::Module, lines::Set{Int})
    cl = LCU.CodeLinks(mod, src)
    edges = LCU.CodeEdges(src, cl)

    for (idx, stmt) in enumerate(src.code)
        # If the line containing this statement is requested by pattern match,
        # this statement needs to be executed.
        lins = Base.IRShow.buildLineInfoNode(src.debuginfo, nothing, idx)
        for lin in lins
            if String(lin.file) == interp.filename && lin.line in lines
                concretized[idx] = true
            end
        end
    end

    select_dependencies!(concretized, src, edges, cl)

    # Debug: uncomment to see which statements are selected
    # LCU.print_with_code(stdout, src, concretized)

    nothing
end

function select_dependencies!(concretized::BitVector, src::CodeInfo, edges, cl)
    typedefs = LCU.find_typedefs(src)
    cfg = CC.compute_basic_blocks(src.code)
    postdomtree = CC.construct_postdomtree(cfg.blocks)
    ssavalue_uses = CC.find_ssavalue_uses(src.code, length(src.code))

    changed = true
    while changed
        changed = false
        changed |= LCU.add_ssa_preds!(concretized, src, edges, ())
        changed |= add_ssas_uses!(concretized, ssavalue_uses)
        changed |= add_slot_deps!(concretized, cl)
        changed |= LCU.add_typedefs!(concretized, src, edges, typedefs, ())
        changed |= LCU.add_control_flow!(concretized, src, cfg, postdomtree)
    end

    LCU.add_active_gotos!(concretized, src, cfg, postdomtree)
end

# Add statements that use SSA values produced by already selected statements
function add_ssas_uses!(concretized::BitVector, ssavalue_uses)
    changed = false
    for idx = 1:length(concretized)
        if concretized[idx]
            for use_idx in ssavalue_uses[idx]
                if !concretized[use_idx]
                    concretized[use_idx] = true
                    changed = true
                end
            end
        end
    end
    return changed
end

function add_slot_deps!(concretized::BitVector, cl::LCU.CodeLinks)
    changed = false

    # For each slot, check if any selected statement uses it
    for slot_id = 1:length(cl.slotsuccs)
        slot_succs = cl.slotsuccs[slot_id]
        slot_preds = cl.slotpreds[slot_id]
        slot_assigns = cl.slotassigns[slot_id]

        # Check if any successor (user) of this slot is selected
        is_selected = false
        for succ_idx in slot_succs.ssas
            if concretized[succ_idx]
                is_selected = true
                break
            end
        end

        is_selected || continue

        # If this slot is selected, we need to select:
        # 1. All predecessors (statements that the slot depends on)
        # 2. All assignments to the slot
        # 3. All prior uses of the slot (to ensure their dependencies are tracked)

        # Select predecessors
        for pred_idx in slot_preds.ssas
            if !concretized[pred_idx]
                concretized[pred_idx] = true
                changed = true
            end
        end

        for assign_idx in slot_assigns
            if !concretized[assign_idx]
                concretized[assign_idx] = true
                changed = true
            end
        end

        # Select all prior uses of the slot (to ensure their effects are included)
        for succ_idx in slot_succs.ssas
            if !concretized[succ_idx]
                # Only select uses that come before the latest selected use
                # This helps avoid selecting unrelated later uses
                latest_selected = 0
                for idx in slot_succs.ssas
                    if concretized[idx]
                        latest_selected = max(latest_selected, idx)
                    end
                end
                if succ_idx < latest_selected
                    concretized[succ_idx] = true
                    changed = true
                end
            end
        end
    end

    return changed
end

# This overload has exactly the same implementation as `JI.evaluate_call!(::JI.NonRecursiveInterpreter, ...)`,
# but since the default `JI.evaluate_call!(::Interpreter, ...)` is for the recursive interpretation,
# we need to provide this implementation for `TRInterpreter`.
function JI.evaluate_call!(interp::TRInterpreter, frame::JI.Frame, call_expr::Expr, enter_generated::Bool=false)
    # @assert !enter_generated
    pc = frame.pc
    ret = JI.bypass_builtins(interp, frame, call_expr, pc)
    isa(ret, Some{Any}) && return ret.value
    # NOTE `JI.maybe_evaluate_builtin` may call `Core._apply_iterate`, which may result in world age error otherwise
    ret = @invokelatest JI.maybe_evaluate_builtin(interp, frame, call_expr, false)
    isa(ret, Some{Any}) && return ret.value
    fargs = JI.collect_args(interp, frame, call_expr)
    return JI.evaluate_call!(interp, frame, fargs, enter_generated)
end

# This overload performs almost the same work as
# `JI.evaluate_call!(::JI.NonRecursiveInterpreter, ...)`
# but includes a few important adjustments specific to TestRunner's virtual process:
# - Special handling for `include` calls: recursively apply the virtual process to included files.
function JI.evaluate_call!(interp::TRInterpreter, frame::JI.Frame, fargs::Vector{Any}, ::Bool)
    args = fargs
    f = popfirst!(fargs)
    args = fargs # now it's really args
    isinclude(f) && return handle_include(interp, f, args)
    return @invokelatest f(args...)
end

isinclude(@nospecialize f) = f isa Base.IncludeInto || (isa(f, Function) && nameof(f) === :include)

function handle_include(interp::TRInterpreter, @nospecialize(include_func), args::Vector{Any})
    nargs = length(args)
    include_context = interp.context
    if nargs == 1
        fname = only(args)
    elseif nargs == 2
        x, fname = args
        if isa(x, Module)
            include_context = x
        elseif isa(x, Function)
            @warn "TestRunner is unable to execute `include(mapexpr::Function, filename::String)` call currently."
        else
            @invokelatest include_func(args...) # make it throw throw
            @assert false "unreachable"
        end
    else
        @invokelatest include_func(args...) # make it throw throw
        @assert false "unreachable"
    end
    if !isa(fname, String)
        @invokelatest include_func(args...) # make it throw throw
        @assert false "unreachable"
    end
    included_file = normpath(dirname(interp.filename), fname)
    newinterp = TRInterpreter(interp; filename=included_file, context=include_context)
    _selective_run(newinterp)
end

function JI.handle_err(interp::TRInterpreter, frame::JI.Frame, @nospecialize(err))
    excs = map(current_exceptions()) do exc
        ExceptionFrame((exc.exception, exc.backtrace))
    end
    append!(interp.current_exceptions, scrub_exc_stack(excs))
    return @invoke JI.handle_err(interp::JI.Interpreter, frame::JI.Frame, err::Any)
end

const JULIAINTERPRETER_INTERPRET_FILE = let
    jlfile = pathof(JI)::String
    Symbol(normpath(jlfile, "..", "interpret.jl"))
end

function scrub_backtrace(bt::Vector{BacktraceElm})
    runtest_idx = @something let
            findfirst(ip::BacktraceElm ->
                Test.ip_has_file_and_func(ip, @__FILE__, (:runtest, :runtests)), bt)
        end return bt
    internal_idx = @something let
            findfirst(ip::BacktraceElm ->
                Test.ip_has_file_and_func(ip, @__FILE__, (:evaluate_call!,)), bt)
        end let
            findfirst(ip::BacktraceElm ->
                Test.ip_has_file_and_func(ip, JULIAINTERPRETER_INTERPRET_FILE, (:step_expr!,:eval_rhs,)), bt)
        end return bt
    internal_idx < runtest_idx || return bt
    return append!(bt[1:internal_idx-1], bt[runtest_idx:end])
end

function scrub_exc_stack(excs::Vector{ExceptionFrame})
    return ExceptionFrame[ ExceptionFrame((exc, scrub_backtrace(bt))) for (exc, bt) in excs ]
end

include("app.jl")
using .TestRunnerApp: main, app_runner_module

include("precompile.jl")

end # module TestRunner
