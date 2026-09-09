function results = run_tests(which)
%RUN_TESTS  Run the NETRA test suites.
%   run_tests()         everything
%   run_tests("data")   data integrity + helpers (no trained model needed)
%   run_tests("model")  trained-model behaviour
%   run_tests("pipeline") quality gate, ICDR rules, dual evidence, district model
if nargin < 1, which = "all"; end
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'tests'), ...
        fullfile(here,'m1_quality'), fullfile(here,'m2_enhance'), ...
        fullfile(here,'m4_grade'), fullfile(here,'m5_simulink'));

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.TestRunProgressPlugin

suite = [];
if which == "all" || which == "data"
    suite = [suite, TestSuite.fromClass(?NetraDataTests)];
end
if which == "all" || which == "model"
    suite = [suite, TestSuite.fromClass(?NetraModelTests)];
end
if which == "all" || which == "pipeline"
    suite = [suite, TestSuite.fromClass(?NetraPipelineTests)];
end

runner = TestRunner.withNoPlugins;
runner.addPlugin(TestRunProgressPlugin.withVerbosity(2));
results = runner.run(suite);

fprintf('\n================ TEST SUMMARY ================\n');
fprintf('passed   %d\n', nnz([results.Passed]));
fprintf('failed   %d\n', nnz([results.Failed]));
fprintf('skipped  %d\n', nnz([results.Incomplete]));
fprintf('duration %.1f s\n', sum([results.Duration]));

if any([results.Failed])
    fprintf('\n--- FAILURES ---\n');
    for r = results([results.Failed])
        fprintf('  %s\n', r.Name);
    end
end
if any([results.Incomplete])
    fprintf('\n--- SKIPPED ---\n');
    for r = results([results.Incomplete])
        fprintf('  %s\n', r.Name);
    end
end
end
