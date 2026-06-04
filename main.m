function results = main(runMode)
% MAIN
%
% Fo futtato fuggveny a grid-connected PV+BESS self-consumption
% esettanulmanyhoz.
%
% Alap mukodes:
%   results = main()
%
% Ez lefuttatja:
%   1) fogyasztasi/PV elozetes elemzes es inverter candidate meghatarozas,
%   2) DC-csatolt candidate sweep,
%   3) AC-csatolt candidate sweep,
%   4) AC/DC osszesito evaluation,
%   5) vegleges AC/DC riportgeneralas: periodus NPV, helyes feliratok,
%      osszehasonlithato heatmapek,
%   6) LCOE javitas: periodus koltseg / hasznositott AC energia.
%
% Gyorsabb hasznalatok:
%   results = main("evaluateOnly")
%       Csak a mar letezo results_dccoupled.mat es results_accoupled.mat
%       alapjan keszit AC/DC osszesito kiertekelest.
%
%   results = main("dcOnly")
%       Csak DC szimulaciot futtat es kulon DC evaluation-t keszit.
%
%   results = main("acOnly")
%       Csak AC szimulaciot futtat es kulon AC evaluation-t keszit.
%
%   results = main("diagnostic")
%       Egyetlen kivalasztott candidate-et futtat diagnosztikai modban.
%       A candidate-et es coupling-ot a cfg.diagnostics mezok adjak meg:
%
%           cfg.diagnostics.candidateIndex
%           cfg.diagnostics.coupling
%
%       A futas ugyanazt a simulate_candidates_database() utvonalat hasznalja,
%       mint a teljes szimulacio, csak cfg.diagnostics.testMode = true mellett.

    if nargin < 1 || isempty(runMode)
        runMode = "full";
    end

    runMode = lower(string(runMode));

    clc;
    close all;

    basePath = fileparts(mfilename('fullpath'));
    cfg = create_configurations(basePath);

    results = struct();
    results.cfgInitial = cfg;

    switch runMode

        case "full"
            [analysisResult, cfg] = analyze_load_profiles(cfg);
            data = build_data(cfg);

            results.analysisResult = analysisResult;
            results.dcDB = local_run_coupled_simulation(data, cfg, "dc");
            results.acDB = local_run_coupled_simulation(data, cfg, "ac");
            results.acdcEvaluation = local_run_acdc_evaluation(cfg);

        case "evaluateonly"
            results.acdcEvaluation = local_run_acdc_evaluation(cfg);

        case "dconly"
            [analysisResult, cfg] = analyze_load_profiles(cfg);
            data = build_data(cfg);

            results.analysisResult = analysisResult;
            results.dcDB = local_run_coupled_simulation(data, cfg, "dc");
            results.dcEvaluation = local_run_single_evaluation(cfg, "dc");

        case "aconly"
            [analysisResult, cfg] = analyze_load_profiles(cfg);
            data = build_data(cfg);

            results.analysisResult = analysisResult;
            results.acDB = local_run_coupled_simulation(data, cfg, "ac");
            results.acEvaluation = local_run_single_evaluation(cfg, "ac");

        case "diagnostic"
            [analysisResult, cfg] = analyze_load_profiles(cfg);
            data = build_data(cfg);

            results.analysisResult = analysisResult;
            results.diagnosticDB = local_run_diagnostic_simulation(data, cfg);

        otherwise
            error(['Unknown runMode: %s. ', ...
                   'Use "full", "evaluateOnly", "dcOnly", "acOnly" or "diagnostic".'], runMode);
    end

    results.cfgFinal = cfg;
end


% =========================================================================
% SIMULATION HELPERS
% =========================================================================
function DB = local_run_coupled_simulation(data, cfg, coupling)

    cfgRun = cfg;
    cfgRun.system.bessCoupling = coupling;

    if isfield(cfgRun, 'diagnostics') && isfield(cfgRun.diagnostics, 'testMode')
        cfgRun.diagnostics.testMode = false;
    end

    fprintf('\n============================================================\n');
    fprintf('Running %s-coupled candidate simulation.\n', upper(char(coupling)));
    fprintf('============================================================\n\n');

    DB = init_candidate_database_structures(data, cfgRun);
    DB = simulate_candidates_database(data, DB, cfgRun);
    save_candidates_database(DB, cfgRun);

    fprintf('\n%s-coupled candidate database simulation finished.\n', upper(char(coupling)));
    fprintf('Candidates: %d\n', height(DB.candidateTable));
end


function DB = local_run_diagnostic_simulation(data, cfg)

    cfgDiag = cfg;

    % ---------------------------------------------------------------------
    % Diagnostic coupling
    % ---------------------------------------------------------------------
    coupling = local_get_diagnostic_coupling(cfgDiag);

    cfgDiag.system.bessCoupling = coupling;

    % ---------------------------------------------------------------------
    % Diagnostic settings
    % ---------------------------------------------------------------------
    if ~isfield(cfgDiag, 'diagnostics') || isempty(cfgDiag.diagnostics)
        cfgDiag.diagnostics = struct();
    end

    cfgDiag.diagnostics.testMode = true;
    cfgDiag.diagnostics.candidateIndex = local_get_diagnostic_candidate_index(cfgDiag);

    if ~isfield(cfgDiag.diagnostics, 'enabled')
        cfgDiag.diagnostics.enabled = true;
    end

    if ~isfield(cfgDiag.diagnostics, 'outputFolder') || isempty(cfgDiag.diagnostics.outputFolder)
        cfgDiag.diagnostics.outputFolder = fullfile(cfgDiag.paths.results, 'diagnostics');
    end

    if ~isfield(cfgDiag.diagnostics, 'saveFullTimeSeries')
        cfgDiag.diagnostics.saveFullTimeSeries = true;
    end

    if ~isfield(cfgDiag.diagnostics, 'makeDcCoupledSummaryPlots')
        cfgDiag.diagnostics.makeDcCoupledSummaryPlots = true;
    end

    if ~isfield(cfgDiag.diagnostics, 'saveFigFiles')
        cfgDiag.diagnostics.saveFigFiles = true;
    end

    if ~isfield(cfgDiag.diagnostics, 'plotDayIndices')
        cfgDiag.diagnostics.plotDayIndices = [];
    end

    if ~isfield(cfgDiag.diagnostics, 'plotWeekStartDays')
        cfgDiag.diagnostics.plotWeekStartDays = [];
    end

    if ~isfield(cfgDiag.diagnostics, 'socTolerance')
        cfgDiag.diagnostics.socTolerance = 0.02;
    end

    if ~isfield(cfgDiag.diagnostics, 'expectedCycleWarningRatio')
        cfgDiag.diagnostics.expectedCycleWarningRatio = 0.30;
    end

    % Diagnosztikai futasnal nem erdemes minden candidate utan menteni,
    % mert csak egy candidate fut. A vegen ugyis mentunk.
    if ~isfield(cfgDiag, 'sim') || isempty(cfgDiag.sim)
        cfgDiag.sim = struct();
    end

    cfgDiag.sim.saveAfterEachCandidate = false;

    fprintf('\n============================================================\n');
    fprintf('Running %s-coupled diagnostic candidate simulation.\n', upper(char(coupling)));
    fprintf('============================================================\n');
    fprintf('Diagnostic candidate index: %d\n', cfgDiag.diagnostics.candidateIndex);
    fprintf('Diagnostic output folder: %s\n', cfgDiag.diagnostics.outputFolder);
    fprintf('============================================================\n\n');

    DB = init_candidate_database_structures(data, cfgDiag);

    if cfgDiag.diagnostics.candidateIndex < 1 || ...
       cfgDiag.diagnostics.candidateIndex > height(DB.candidateTable)

        error(['Invalid cfg.diagnostics.candidateIndex = %d. ', ...
               'Valid range is 1...%d.'], ...
               cfgDiag.diagnostics.candidateIndex, ...
               height(DB.candidateTable));
    end

    DB = simulate_candidates_database(data, DB, cfgDiag);

    save_candidates_database(DB, cfgDiag);

    fprintf('\nDiagnostic simulation finished.\n');
    fprintf('Coupling: %s\n', upper(char(coupling)));
    fprintf('Candidate index: %d\n', cfgDiag.diagnostics.candidateIndex);

    if isfield(DB, 'diagnostics')
        fprintf('Diagnostics were stored in DB.diagnostics.\n');
    end
end


function coupling = local_get_diagnostic_coupling(cfg)

    coupling = "dc";

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'coupling') && ...
       ~isempty(cfg.diagnostics.coupling)

        coupling = lower(string(cfg.diagnostics.coupling));
    end

    if coupling == "dc-coupled"
        coupling = "dc";
    elseif coupling == "ac-coupled"
        coupling = "ac";
    end

    if coupling ~= "dc" && coupling ~= "ac"
        error('Invalid cfg.diagnostics.coupling: %s. Use "dc" or "ac".', coupling);
    end
end


function candidateIndex = local_get_diagnostic_candidate_index(cfg)

    candidateIndex = 1;

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'candidateIndex') && ...
       ~isempty(cfg.diagnostics.candidateIndex)

        candidateIndex = cfg.diagnostics.candidateIndex;
    end

    if ~isnumeric(candidateIndex) || ~isscalar(candidateIndex) || ...
            ~isfinite(candidateIndex) || candidateIndex < 1

        error('cfg.diagnostics.candidateIndex must be a positive scalar integer.');
    end

    candidateIndex = round(candidateIndex);
end


function acdcEvaluation = local_run_acdc_evaluation(cfg)

    acdcEvaluation = evaluation_acdc_summary(cfg);

    % A postprocess megtartja/frissiti a tablazatos eredmenyeket, a finalizer
    % pedig bezarja a regi nyitott abrakat es csak a vegleges riportfigurakat
    % generalja ujra: jo x tengely feliratok, szimulalt idoszakra vett NPV,
    % kozos DC/AC heatmap tartomanyok. A legvegen az LCOE-t is ugyanarra a
    % perioduskoltseg-alapra hozzuk, mint az NPV-t.
    acdcEvaluation = postprocess_acdc_summary_outputs(acdcEvaluation, cfg);
    acdcEvaluation = finalize_acdc_summary_outputs(acdcEvaluation, cfg);
    acdcEvaluation = fix_acdc_lcoe_outputs(acdcEvaluation);
end


function evaluationResult = local_run_single_evaluation(cfg, coupling)

    cfgEval = cfg;
    cfgEval.system.bessCoupling = coupling;

    evalCfg = create_evaluation_config(cfgEval);

    switch string(coupling)
        case "dc"
            evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_dccoupled.mat');
        case "ac"
            evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_accoupled.mat');
        otherwise
            error('Unknown coupling: %s', string(coupling));
    end

    evalCfg.output.baseFolder = fullfile(cfg.paths.figures, 'evaluation', char(coupling));
    evaluationResult = evaluation(cfgEval, evalCfg);
end