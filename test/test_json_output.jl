module test_json_output

using Test
using JSON: JSON
using TestRunner
using TestRunner.TestRunnerApp: TestRunnerResult, TestRunnerStats

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

function run_testrunner_process(args)
    project = dirname(dirname(@__DIR__))  # Get TestRunner project directory
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e "using TestRunner; exit(TestRunner.main(ARGS))" -- $args`

    mktemp() do out_path, _
        mktemp() do err_path, _
            # Run the command with output redirected to files
            proc = run(pipeline(cmd, stdout=out_path, stderr=err_path), wait=false)
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

end # module test_json_output
