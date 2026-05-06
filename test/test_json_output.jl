module test_json_output

using Test
using JSON: JSON
using TestRunner
using TestRunner.TestRunnerApp: TestRunnerResult

function with_simple_passing_test_file(tester)
    content = """
    using Test

    @testset "simple test" begin
        @test 1 + 1 == 2
    end
    """

    mktemp() do path, io
        write(path, content)
        close(io)
        tester(path)
    end
end

function with_failing_test_file(tester)
    content = """
    using Test

    @testset "failing" begin
        @test 1 == 2
    end
    """

    mktemp() do path, io
        write(path, content)
        close(io)
        tester(path)
    end
end

function run_testrunner_process(args; stdin_input::Union{Nothing,AbstractString}=nothing)
    project = dirname(dirname(@__DIR__))  # Get TestRunner project directory
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e "using TestRunner; exit(TestRunner.main(ARGS))" -- $args`

    mktemp() do out_path, _
        mktemp() do err_path, _
            pipe = if stdin_input === nothing
                pipeline(cmd, stdout=out_path, stderr=err_path)
            else
                pipeline(cmd, stdin=IOBuffer(stdin_input), stdout=out_path, stderr=err_path)
            end
            proc = run(pipe, wait=false)
            wait(proc)

            return (
                stdout = read(out_path, String),
                stderr = read(err_path, String),
                exitcode = proc.exitcode
            )
        end
    end
end

with_simple_passing_test_file() do testfile
    result = run_testrunner_process(["--json", testfile])
    @test result.exitcode == 0
    @test isempty(result.stderr)
    json_result = JSON.parse(result.stdout, TestRunnerResult)
    stats = json_result.stats
    @test stats.n_passed == 1
    @test stats.n_failed == stats.n_errored == stats.n_broken == 0
    @test stats.duration > 0
    @test isempty(json_result.diagnostics)
end

let
    result = run_testrunner_process(["--json", "/nonexistent/file.jl"])
    @test result.exitcode == 1
    @test !isempty(result.stderr)
    @test occursin("File not found", result.stderr)
    @test isempty(result.stdout)
end

with_simple_passing_test_file() do testfile
    result = run_testrunner_process(["--json", "--invalid-option", testfile])
    @test result.exitcode == 1
    @test !isempty(result.stderr)
    @test occursin("Unknown option", result.stderr)
    @test isempty(result.stdout)
end

with_simple_passing_test_file() do testfile
    result = run_testrunner_process(["--json", testfile, "simple test"])
    @test result.exitcode == 0
    @test isempty(result.stderr)
    json_result = JSON.parse(result.stdout, TestRunnerResult)
    @test json_result.patterns == ["simple test"]
    stats = json_result.stats
    @test stats.n_passed == 1
    @test stats.n_failed == stats.n_errored == stats.n_broken == 0
    @test stats.duration > 0
    @test isempty(json_result.diagnostics)
end

with_simple_passing_test_file() do testfile
    result = run_testrunner_process(["--json", "--verbose", testfile])
    json_result = JSON.parse(result.stdout, TestRunnerResult)
    @test occursin("Test Setup", json_result.logs)
    @test occursin("Julia version", json_result.logs)
    @test occursin("Test Configuration", json_result.logs)
    @test occursin("Running Tests", json_result.logs)
end

with_failing_test_file() do testfile
    result = run_testrunner_process(["--json", testfile])
    @test result.exitcode == 1
    @test isempty(result.stderr)
    json_result = JSON.parse(result.stdout, TestRunnerResult)
    stats = json_result.stats
    @test stats.n_failed == 1
    @test stats.n_passed == stats.n_errored == stats.n_broken == 0
    @test stats.duration > 0
    @test !isempty(json_result.diagnostics)
end

@testset "--read-stdin" begin
    # Pass source via stdin; file path is still required for `@__FILE__` etc.
    let source = """
        using Test
        @testset "stdin test" begin
            @test 1 + 1 == 2
        end
        """
        with_simple_passing_test_file() do testfile
            result = run_testrunner_process(["--json", "--read-stdin", testfile];
                                            stdin_input=source)
            @test result.exitcode == 0
            @test isempty(result.stderr)
            json_result = JSON.parse(result.stdout, TestRunnerResult)
            stats = json_result.stats
            @test stats.n_passed == 1
            @test stats.n_failed == stats.n_errored == stats.n_broken == 0
        end
    end

    # Stdin source overrides on-disk content: testset name only exists in stdin
    with_simple_passing_test_file() do testfile
        source = """
        using Test
        @testset "stdin only" begin
            @test true
        end
        """
        result = run_testrunner_process(["--json", "--read-stdin", testfile, "stdin only"];
                                        stdin_input=source)
        @test result.exitcode == 0
        json_result = JSON.parse(result.stdout, TestRunnerResult)
        @test json_result.stats.n_passed == 1
    end

    # `--read-stdin` works even when the file does not exist on disk
    let source = """
        using Test
        @testset "no file" begin
            @test 1 == 1
        end
        """
        nonexistent = joinpath(mktempdir(), "ghost.jl")
        result = run_testrunner_process(["--json", "--read-stdin", nonexistent];
                                        stdin_input=source)
        @test result.exitcode == 0
        json_result = JSON.parse(result.stdout, TestRunnerResult)
        @test json_result.stats.n_passed == 1
    end

    # `--read-stdin` plus `--filter-lines` matches a testset on a stdin-defined line
    with_simple_passing_test_file() do testfile
        source = """
        using Test
        @testset "first" begin
            @test 1 == 1
        end
        @testset "second" begin
            @test 2 == 2
        end
        """
        result = run_testrunner_process(
            ["--json", "--read-stdin", testfile, "second", "--filter-lines=5"];
            stdin_input=source)
        @test result.exitcode == 0
        json_result = JSON.parse(result.stdout, TestRunnerResult)
        @test json_result.stats.n_passed == 1
    end

    # When source comes from stdin, the file path is treated as a virtual
    # identifier and not `abspath`'d, so editor integrations can pass an
    # untitled-buffer name and have it round-trip through diagnostics
    # unchanged.
    let source = """
        using Test
        @testset "virtual" begin
            @test 1 == 2
        end
        """
        virtual_name = "Untitled-1"
        result = run_testrunner_process(
            ["--json", "--read-stdin", virtual_name];
            stdin_input=source)
        @test result.exitcode == 1
        json_result = JSON.parse(result.stdout, TestRunnerResult)
        @test json_result.filename == virtual_name
        @test !isempty(json_result.diagnostics)
        @test all(diag -> diag.filename == virtual_name, json_result.diagnostics)
    end
end

@testset "--root-path" begin
    # `--root-path` lets a virtual stdin filename resolve relative `include`
    # calls from a real workspace directory, both for the selective-execution
    # path (with patterns, via `runtest`) and the plain include path (no
    # patterns, via `Base.include_string`).
    mktempdir() do dir
        helper_path = joinpath(dir, "helpers.jl")
        write(helper_path, "helper_value() = 42\n")
        source = """
        using Test
        include("helpers.jl")
        @testset "rooted" begin
            @test helper_value() == 42
        end
        """
        for extra_args in (String[], ["rooted"])
            result = run_testrunner_process(
                ["--json", "--read-stdin", "--root-path=$dir", "Untitled-1", extra_args...];
                stdin_input=source)
            @test result.exitcode == 0
            @test isempty(result.stderr)
            json_result = JSON.parse(result.stdout, TestRunnerResult)
            @test json_result.stats.n_passed == 1
            @test isempty(json_result.diagnostics)
        end
    end

    # Without `--root-path`, the same virtual filename can't find the helper
    # because `dirname("Untitled-1")` is empty and resolution falls back to
    # cwd, which is unlikely to contain the helper.
    mktempdir() do dir
        helper_path = joinpath(dir, "helpers.jl")
        write(helper_path, "helper_value() = 42\n")
        source = """
        using Test
        include("helpers.jl")
        @testset "rooted" begin
            @test helper_value() == 42
        end
        """
        result = run_testrunner_process(
            ["--json", "--read-stdin", "Untitled-1", "rooted"];
            stdin_input=source)
        @test result.exitcode != 0
    end

    # When `filename` carries its own directory, `--root-path` is ignored —
    # nested includes resolve via that file's `dirname` as usual.
    mktempdir() do dir
        helper_path = joinpath(dir, "helpers.jl")
        write(helper_path, "helper_value() = 42\n")
        # An unrelated decoy in `--root-path` would mask the real helper if
        # `--root-path` were preferred over `dirname`.
        decoy_dir = mktempdir()
        decoy_helper = joinpath(decoy_dir, "helpers.jl")
        write(decoy_helper, "helper_value() = 0\n")
        entry_path = joinpath(dir, "entry.jl")
        write(entry_path, """
        using Test
        include("helpers.jl")
        @testset "real dir" begin
            @test helper_value() == 42
        end
        """)
        result = run_testrunner_process(
            ["--json", "--root-path=$decoy_dir", entry_path, "real dir"])
        @test result.exitcode == 0
        json_result = JSON.parse(result.stdout, TestRunnerResult)
        @test json_result.stats.n_passed == 1
    end
end

end # module test_json_output
