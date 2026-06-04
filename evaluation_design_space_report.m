function report = evaluation_design_space_report(cfg, evalCfg, DB_in)
% EVALUATION_DESIGN_SPACE_REPORT
%
% Design-space evaluation report for AC- and DC-coupled PV+BESS systems.
%
% This function does not run a simulation. It only uses:
%   - saved candidateTable values,
%   - cfg values,
%   - evalCfg values.
%
% The current implementation is matched to the energy-flow based
% candidateTable, where the saved metrics include:
%   loadEnergy_kWh
%   pvEnergyAvailable_kWh
%   pvToLoad_kWh
%   pvToBess_kWh
%   bessToLoad_kWh
%   gridImport_kWh
%   gridExport_kWh
%   curtailment_kWh
%
% It does not require:
%   energyCost_HUF
%   energyCostNoBess_HUF
%   contractCost_HUF
%   overrunCost_HUF
%   objectiveCost_HUF
%
% Economic values are calculated from saved energy flows and configured
% import/export prices.
%
% No hidden economic default values are used.

    if nargin < 2 || isempty(evalCfg)
        error('Missing input: evalCfg. The report must not create default evaluation settings.');
    end

    if nargin < 3
        DB_in = [];
    end

    local_validate_cfg(cfg);
    local_validate_evalcfg(evalCfg);

    outputRoot = fullfile(evalCfg.output.baseFolder, 'design_space_heatmaps');
    figureFolder = fullfile(outputRoot, 'figures');
    tableFolder = fullfile(outputRoot, 'tables');

    local_ensure_folder(outputRoot);
    local_ensure_folder(figureFolder);
    local_ensure_folder(tableFolder);

    datasets = local_collect_datasets(cfg, evalCfg, DB_in);

    if isempty(datasets)
        error('No AC/DC result file found and DB_in is empty.');
    end

    prepared = struct('coupling', {}, 'T', {});
    allCandidateTable = table();

    for k = 1:numel(datasets)

        couplingLabel = string(datasets(k).coupling);

        fprintf('\n============================================================\n');
        fprintf('Preparing design-space evaluation: %s\n', upper(couplingLabel));
        fprintf('============================================================\n');

        T = local_prepare_candidate_table( ...
            datasets(k).DB, ...
            cfg, ...
            evalCfg, ...
            couplingLabel);

        if isempty(T) || height(T) == 0
            warning('No valid candidate found for coupling: %s', couplingLabel);
            continue;
        end

        prepared(end+1).coupling = couplingLabel; %#ok<AGROW>
        prepared(end).T = T;

        allCandidateTable = local_append_table_union(allCandidateTable, T);

        candidateExportPath = fullfile( ...
            tableFolder, ...
            sprintf('%s_design_space_candidates.csv', lower(couplingLabel)));

        writetable(T, candidateExportPath);
    end

    if isempty(allCandidateTable) || height(allCandidateTable) == 0
        error('No valid candidate table could be prepared.');
    end

    metricSpecs = local_metric_specs();

    % Fixed color limits for every economic heatmap.
    % Values outside this interval are clipped only visually by the colormap.
    % The written cell labels keep the original values.
    colorRanges = local_fixed_color_ranges(metricSpecs);

    bestCandidateTable = table();

    for k = 1:numel(prepared)

        couplingLabel = prepared(k).coupling;
        T = prepared(k).T;

        fprintf('\n============================================================\n');
        fprintf('Creating heatmaps: %s\n', upper(couplingLabel));
        fprintf('============================================================\n');

        bestMarkerInfo = local_get_best_marker_info(T, metricSpecs);

        bestForCoupling = local_make_heatmaps_for_coupling( ...
            T, ...
            couplingLabel, ...
            figureFolder, ...
            metricSpecs, ...
            colorRanges, ...
            bestMarkerInfo);

        bestCandidateTable = local_append_table_union(bestCandidateTable, bestForCoupling);

        if ~isempty(bestForCoupling) && height(bestForCoupling) > 0

            bestExportPath = fullfile( ...
                tableFolder, ...
                sprintf('%s_design_space_best_candidates.csv', lower(couplingLabel)));

            writetable(bestForCoupling, bestExportPath);
        end
    end

    writetable(allCandidateTable, fullfile(tableFolder, 'all_design_space_candidates.csv'));

    if ~isempty(bestCandidateTable) && height(bestCandidateTable) > 0
        writetable(bestCandidateTable, fullfile(tableFolder, 'all_design_space_best_candidates.csv'));
    end

    save(fullfile(outputRoot, 'evaluation_design_space_report.mat'), ...
        'allCandidateTable', ...
        'bestCandidateTable', ...
        'metricSpecs', ...
        'colorRanges', ...
        '-v7.3');

    report = struct();
    report.createdAt = datetime('now');
    report.outputRoot = outputRoot;
    report.figureFolder = figureFolder;
    report.tableFolder = tableFolder;
    report.allCandidateTable = allCandidateTable;
    report.bestCandidateTable = bestCandidateTable;
    report.metricSpecs = metricSpecs;
    report.colorRanges = colorRanges;

    fprintf('\n============================================================\n');
    fprintf('Design-space heatmap report finished.\n');
    fprintf('Output folder: %s\n', outputRoot);
    fprintf('============================================================\n');
end


% =========================================================================
% DATASET LOADING
% =========================================================================

function datasets = local_collect_datasets(cfg, evalCfg, DB_in)

    datasets = struct('coupling', {}, 'filePath', {}, 'DB', {});

    resultFiles = local_get_default_result_files(cfg, evalCfg);

    for i = 1:numel(resultFiles)

        filePath = resultFiles(i).path;

        if isfile(filePath)

            DB = local_load_candidate_database(filePath);

            datasets(end+1) = struct( ... %#ok<AGROW>
                'coupling', resultFiles(i).coupling, ...
                'filePath', filePath, ...
                'DB', DB);

            fprintf('Loaded %s result file: %s\n', upper(resultFiles(i).coupling), filePath);
        end
    end

    if isempty(datasets) && ~isempty(DB_in)

        if istable(DB_in)

            DB = struct();
            DB.candidateTable = DB_in;

        elseif isstruct(DB_in) && isfield(DB_in, 'DB')

            DB = DB_in.DB;

        else

            DB = DB_in;
        end

        couplingLabel = local_infer_coupling_from_db_or_cfg(DB, cfg);

        datasets(end+1) = struct( ...
            'coupling', char(couplingLabel), ...
            'filePath', '', ...
            'DB', DB);

        fprintf('Using DB_in dataset. Coupling label: %s\n', couplingLabel);
    end
end


function resultFiles = local_get_default_result_files(cfg, evalCfg)

    resultFolder = "";

    if isfield(cfg, 'paths') && isfield(cfg.paths, 'results')
        resultFolder = string(cfg.paths.results);
    elseif isfield(evalCfg, 'input') && isfield(evalCfg.input, 'resultFilePath')
        resultFolder = string(fileparts(evalCfg.input.resultFilePath));
    end

    if strlength(resultFolder) == 0
        error('Cannot determine result folder from cfg.paths.results or evalCfg.input.resultFilePath.');
    end

    resultFiles = struct('coupling', {}, 'path', {});

    resultFiles(1).coupling = 'dc';
    resultFiles(1).path = fullfile(resultFolder, 'results_dccoupled.mat');

    resultFiles(2).coupling = 'ac';
    resultFiles(2).path = fullfile(resultFolder, 'results_accoupled.mat');
end


function couplingLabel = local_infer_coupling_from_db_or_cfg(DB, cfg)

    if isfield(DB, 'cfgSnapshot') && ...
            isfield(DB.cfgSnapshot, 'system') && ...
            isfield(DB.cfgSnapshot.system, 'bessCoupling')

        couplingLabel = string(DB.cfgSnapshot.system.bessCoupling);
        return;
    end

    if isfield(cfg, 'system') && isfield(cfg.system, 'bessCoupling')
        couplingLabel = string(cfg.system.bessCoupling);
        return;
    end

    error('Cannot infer coupling label from DB.cfgSnapshot.system.bessCoupling or cfg.system.bessCoupling.');
end


function DB = local_load_candidate_database(resultFilePath)

    S = load(resultFilePath);

    if isfield(S, 'DB')
        DB = S.DB;
        return;
    end

    if isfield(S, 'configurationDatabase')
        DB = S.configurationDatabase;
        return;
    end

    if isfield(S, 'evaluationResult') && isfield(S.evaluationResult, 'candidateTable')
        DB = struct();
        DB.candidateTable = S.evaluationResult.candidateTable;
        return;
    end

    error('The MAT file does not contain DB, configurationDatabase, or evaluationResult.candidateTable: %s', resultFilePath);
end


% =========================================================================
% CANDIDATE TABLE PREPARATION
% =========================================================================

function T = local_prepare_candidate_table(DB, cfg, evalCfg, couplingLabel)

    if istable(DB)

        T = DB;

    elseif isstruct(DB) && isfield(DB, 'candidateTable')

        T = DB.candidateTable;

    else

        error('DB does not contain candidateTable. Coupling: %s', couplingLabel);
    end

    if isempty(T) || height(T) == 0
        return;
    end

    if ismember('wasSimulated', T.Properties.VariableNames) && ...
            ismember('hasError', T.Properties.VariableNames)

        validMask = logical(T.wasSimulated) & ~logical(T.hasError);
        T = T(validMask, :);

    else

        error('candidateTable must contain wasSimulated and hasError columns.');
    end

    if isempty(T) || height(T) == 0
        return;
    end

    T = local_apply_candidate_aliases(T);

    requiredColumns = { ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'loadEnergy_kWh', ...
        'pvEnergyAvailable_kWh', ...
        'pvToLoad_kWh', ...
        'pvToBess_kWh', ...
        'bessToLoad_kWh', ...
        'gridImport_kWh', ...
        'gridExport_kWh', ...
        'curtailment_kWh', ...
        'maxLoadPeak_kW', ...
        'maxPVPeak_kW', ...
        'maxGridImportPeak_kW', ...
        'maxBessChargePeak_kW', ...
        'maxBessDischargePeak_kW'};

    local_require_columns(T, requiredColumns, 'valid candidateTable');

    if ~ismember('finalSoH', T.Properties.VariableNames)
        error(['The candidateTable does not contain finalSoH. ', ...
               'The requested SoH-based BESS degradation CAPEX cannot be calculated.']);
    end

    finiteColumns = { ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'loadEnergy_kWh', ...
        'pvEnergyAvailable_kWh', ...
        'pvToLoad_kWh', ...
        'pvToBess_kWh', ...
        'bessToLoad_kWh', ...
        'gridImport_kWh', ...
        'gridExport_kWh', ...
        'curtailment_kWh', ...
        'maxLoadPeak_kW', ...
        'maxPVPeak_kW', ...
        'maxGridImportPeak_kW', ...
        'maxBessChargePeak_kW', ...
        'maxBessDischargePeak_kW'};

    local_assert_finite_columns(T, finiteColumns, 'valid candidateTable');

    hasBess = T.E_BESS_kWh > 0;

    if any(hasBess & ~isfinite(T.finalSoH))
        error('finalSoH contains non-finite values for BESS candidates.');
    end

    T = local_add_optional_numeric_column(T, 'inverterLoss_kWh', NaN);
    T = local_add_optional_numeric_column(T, 'internalNetworkLoss_kWh', NaN);
    T = local_add_optional_numeric_column(T, 'gridImportReduction_kWh', NaN);
    T = local_add_optional_numeric_column(T, 'bestContract_kW', NaN);

    T.coupling = repmat(string(couplingLabel), height(T), 1);

    T = local_add_design_ratios(T);
    T = local_add_capex_columns(T, cfg);
    T = local_add_baseline_relative_columns(T);
    T = local_add_energy_indicators(T, evalCfg);
    T = local_add_sim_period_economics(T, cfg, evalCfg);
    T = local_add_lifetime_economics(T, evalCfg);
    T = local_add_payback_columns(T, evalCfg);

    T = sortrows(T, {'P_inv_kW', 'dcac_ratio', 'BESS_PV_ratio'});
end


function T = local_apply_candidate_aliases(T)

    aliasMap = { ...
        'P_PV_kW',               {'P_PV_dc_kW', 'P_PV_dc_kWp', 'PV_kWp', 'pvSize_kWp', 'PV_scale'}; ...
        'P_inv_kW',              {'P_inverter_kW', 'Pinv_kW', 'inverter_kW'}; ...
        'BESS_PV_ratio',         {'bessPvRatio', 'S2P_ratio', 'E_BESS_per_PV'}; ...
        'E_BESS_kWh',            {'BESS_kWh', 'batteryEnergy_kWh', 'E_batt_kWh'}; ...
        'P_BESS_kW',             {'BESS_power_kW', 'batteryPower_kW', 'P_batt_kW'}; ...
        'loadEnergy_kWh',        {'totalLoadEnergy_kWh', 'servedLoadEnergy_kWh', 'load_kWh'}; ...
        'pvEnergyAvailable_kWh', {'pvProduction_kWh', 'pvAvailableEnergy_kWh', 'totalPVProduction_kWh'}; ...
        'pvToLoad_kWh',          {'PVToLoad_kWh', 'pv_to_load_kWh'}; ...
        'pvToBess_kWh',          {'PVToBess_kWh', 'pv_to_bess_kWh'}; ...
        'bessToLoad_kWh',        {'BESSToLoad_kWh', 'bess_to_load_kWh', 'batteryToLoad_kWh'}; ...
        'gridImport_kWh',        {'totalGridImport_kWh', 'importEnergy_kWh'}; ...
        'gridExport_kWh',        {'totalGridExport_kWh', 'exportEnergy_kWh'}; ...
        'curtailment_kWh',       {'pvCurtailment_kWh', 'curtailedEnergy_kWh'}; ...
        'finalSoH',              {'finalSOH', 'SoH_final', 'batteryFinalSoH'}; ...
        'bestContract_kW',       {'optimalContract_kW', 'contractCapacity_kW'} ...
    };

    for i = 1:size(aliasMap, 1)

        targetName = aliasMap{i, 1};
        aliases = aliasMap{i, 2};

        T = local_copy_first_existing_alias(T, targetName, aliases);
    end
end


function T = local_copy_first_existing_alias(T, targetName, aliases)

    if ismember(targetName, T.Properties.VariableNames)
        return;
    end

    for i = 1:numel(aliases)

        aliasName = aliases{i};

        if ismember(aliasName, T.Properties.VariableNames)
            T.(targetName) = T.(aliasName);
            return;
        end
    end
end


function T = local_add_design_ratios(T)

    T.dcac_ratio = T.P_PV_kW ./ T.P_inv_kW;
    T.bess_power_to_pv_ratio = T.P_BESS_kW ./ T.P_PV_kW;
end


function T = local_add_capex_columns(T, cfg)

    pvCapex = local_get_required_cost_value(cfg, 'pv_huf_per_kWp');
    bessEnergyCapex = local_get_required_cost_value(cfg, 'bess_huf_per_kWh');
    bessPowerCapex = local_get_required_cost_value(cfg, 'bess_power_huf_per_kW');
    inverterCapex = local_get_required_cost_value(cfg, 'inverter_huf_per_kW');

    T.capexPV_HUF = T.P_PV_kW .* pvCapex;

    T.capexBESS_HUF = ...
        T.E_BESS_kWh .* bessEnergyCapex + ...
        T.P_BESS_kW .* bessPowerCapex;

    T.capexInverter_HUF = T.P_inv_kW .* inverterCapex;

    T.initialCapex_HUF = ...
        T.capexPV_HUF + ...
        T.capexBESS_HUF + ...
        T.capexInverter_HUF;
end


function T = local_add_baseline_relative_columns(T)

    baselineMask = abs(T.BESS_PV_ratio) < 1e-12;

    if ~any(baselineMask)
        error('No BESS_PV_ratio = 0 baseline candidate found.');
    end

    B = T(baselineMask, :);

    n = height(T);

    baselineGridImport = NaN(n, 1);
    baselineGridExport = NaN(n, 1);
    baselineCurtailment = NaN(n, 1);
    baselinePvToLoad = NaN(n, 1);
    baselinePvToBess = NaN(n, 1);
    baselineBessToLoad = NaN(n, 1);
    baselineInitialCapex = NaN(n, 1);

    for i = 1:n

        idx = local_find_matching_baseline_strict(B, T.P_PV_kW(i), T.P_inv_kW(i));

        baselineGridImport(i) = B.gridImport_kWh(idx);
        baselineGridExport(i) = B.gridExport_kWh(idx);
        baselineCurtailment(i) = B.curtailment_kWh(idx);

        baselinePvToLoad(i) = B.pvToLoad_kWh(idx);
        baselinePvToBess(i) = B.pvToBess_kWh(idx);
        baselineBessToLoad(i) = B.bessToLoad_kWh(idx);

        baselineInitialCapex(i) = B.initialCapex_HUF(idx);
    end

    T.baselineGridImport_kWh = baselineGridImport;
    T.baselineGridExport_kWh = baselineGridExport;
    T.baselineCurtailment_kWh = baselineCurtailment;

    T.baselinePvToLoad_kWh = baselinePvToLoad;
    T.baselinePvToBess_kWh = baselinePvToBess;
    T.baselineBessToLoad_kWh = baselineBessToLoad;

    T.baselineInitialCapex_HUF = baselineInitialCapex;

    T.gridImportReduction_kWh = ...
        T.baselineGridImport_kWh - T.gridImport_kWh;

    T.gridExportIncrease_kWh = ...
        T.gridExport_kWh - T.baselineGridExport_kWh;

    T.curtailmentReduction_kWh = ...
        T.baselineCurtailment_kWh - T.curtailment_kWh;

    T.pvToLoadIncrease_kWh = ...
        T.pvToLoad_kWh - T.baselinePvToLoad_kWh;

    T.pvToBessIncrease_kWh = ...
        T.pvToBess_kWh - T.baselinePvToBess_kWh;

    T.bessToLoadIncrease_kWh = ...
        T.bessToLoad_kWh - T.baselineBessToLoad_kWh;

    % Közvetlen PV-alapú sajátfogyasztás.
    % Ez a gazdasági haszon számításának stabilabb alapja, mint önmagában
    % a gridImportReduction, mert közvetlenül megmutatja, mennyi PV energia
    % szolgálta ki a fogyasztást.
    T.selfConsumedPvForLoad_kWh = ...
        T.pvToLoad_kWh + T.bessToLoad_kWh;

    T.baselineSelfConsumedPvForLoad_kWh = ...
        T.baselinePvToLoad_kWh + T.baselineBessToLoad_kWh;

    T.additionalSelfConsumption_kWh = ...
        T.selfConsumedPvForLoad_kWh - T.baselineSelfConsumedPvForLoad_kWh;

    if any(~isfinite(T.additionalSelfConsumption_kWh)) || ...
       any(~isfinite(T.gridExportIncrease_kWh)) || ...
       any(~isfinite(T.baselineInitialCapex_HUF))

        error('Non-finite baseline-relative energy or CAPEX values were calculated.');
    end
end


function idx = local_find_matching_baseline_strict(B, pPv, pInv)

    tol = 1e-6;

    mask = ...
        abs(B.P_PV_kW - pPv) <= tol & ...
        abs(B.P_inv_kW - pInv) <= tol & ...
        abs(B.BESS_PV_ratio) <= tol;

    idxAll = find(mask);

    if isempty(idxAll)
        error('Missing no-BESS baseline for P_PV_kW = %.6g, P_inv_kW = %.6g.', pPv, pInv);
    end

    if numel(idxAll) > 1
        error('Multiple no-BESS baselines found for P_PV_kW = %.6g, P_inv_kW = %.6g.', pPv, pInv);
    end

    idx = idxAll(1);
end


function T = local_add_energy_indicators(T, evalCfg)

    simYears = local_get_required_economics_value(evalCfg, 'simYears');

    T.bessCharge_kWh = T.pvToBess_kWh;
    T.bessDischarge_kWh = T.bessToLoad_kWh;

    T.bessThroughput_kWh = ...
        T.bessCharge_kWh + T.bessDischarge_kWh;

    T.totalEquivalentCycles = zeros(height(T), 1);
    T.annualEquivalentCycles = zeros(height(T), 1);

    hasBess = T.E_BESS_kWh > 0;

    T.totalEquivalentCycles(hasBess) = ...
        T.bessThroughput_kWh(hasBess) ./ ...
        (2 .* T.E_BESS_kWh(hasBess));

    T.annualEquivalentCycles(hasBess) = ...
        T.totalEquivalentCycles(hasBess) ./ simYears;

    T.annualBessDischarge_kWh = ...
        T.bessDischarge_kWh ./ simYears;

    T.selfSufficiency_pct = NaN(height(T), 1);

    validLoad = T.loadEnergy_kWh > 0;

    T.selfSufficiency_pct(validLoad) = ...
        100 .* (T.pvToLoad_kWh(validLoad) + T.bessToLoad_kWh(validLoad)) ./ ...
        T.loadEnergy_kWh(validLoad);

    T.selfConsumption_pct = NaN(height(T), 1);

    validPV = T.pvEnergyAvailable_kWh > 0;

    T.selfConsumption_pct(validPV) = ...
        100 .* (T.pvToLoad_kWh(validPV) + T.pvToBess_kWh(validPV)) ./ ...
        T.pvEnergyAvailable_kWh(validPV);

    T.pvUsedEnergy_kWh = ...
        T.pvToLoad_kWh + T.pvToBess_kWh;

    T.pvUtilization_pct = T.selfConsumption_pct;

    T.annualGridImportReduction_kWh = ...
        T.gridImportReduction_kWh ./ simYears;

    T.annualPvUsedEnergy_kWh = ...
        T.pvUsedEnergy_kWh ./ simYears;
end


% =========================================================================
% SIMULATION-PERIOD ECONOMICS
% =========================================================================

function T = local_add_sim_period_economics(T, cfg, evalCfg)

    simYears = local_get_required_economics_value(evalCfg, 'simYears');
    eolSohLoss = local_get_required_economics_value(evalCfg, 'bessEolSohLoss');

    gridImportPrice = local_get_required_cost_value(cfg, 'grid_import_huf_per_kWh');
    gridExportPrice = local_get_required_cost_value(cfg, 'grid_export_huf_per_kWh');

    bessOpexFrac = local_get_required_economics_value(evalCfg, 'bess_opex_frac_per_year');

    soh = T.finalSoH;

    percentMask = soh > 1.5;
    soh(percentMask) = soh(percentMask) ./ 100;

    hasBess = T.E_BESS_kWh > 0;

    T.bessDegradationCapex_HUF = zeros(height(T), 1);

    T.bessDegradationCapex_HUF(hasBess) = ...
        max(0, (1 - soh(hasBess)) ./ eolSohLoss) .* T.capexBESS_HUF(hasBess);

    % ---------------------------------------------------------------------
    % Gazdasagi haszon a sajatfogyasztas-novekedesbol
    % ---------------------------------------------------------------------
    % Ha a BESS tobblet PV energiat juttat a fogyasztasra, akkor ennek
    % erteke az import aron jelenik meg.
    T.periodSelfConsumptionValue_HUF = ...
        T.additionalSelfConsumption_kWh .* gridImportPrice;

    % Ha az export valtozik, az exportarbevetel-változást is figyelembe vesszuk.
    % Ha export nem engedelyezett vagy ara 0, ez a tag 0.
    T.periodExportRevenueChange_HUF = ...
        T.gridExportIncrease_kWh .* gridExportPrice;

    T.periodGrossOperationalSaving_HUF = ...
        T.periodSelfConsumptionValue_HUF + ...
        T.periodExportRevenueChange_HUF;

    % Diagnosztikai osszehasonlitas: importcsokkenes alapu becsles.
    T.periodImportReductionValue_HUF = ...
        T.gridImportReduction_kWh .* gridImportPrice;

    % ---------------------------------------------------------------------
    % Koltsegek
    % ---------------------------------------------------------------------
    T.simPeriodBESS_OPEX_HUF = ...
        T.capexBESS_HUF .* bessOpexFrac .* simYears;

    T.incrementalCapexVsBaseline_HUF = ...
        T.initialCapex_HUF - T.baselineInitialCapex_HUF;

    % ---------------------------------------------------------------------
    % 1) Szimulacios idoszak netto megtakaritas
    % ---------------------------------------------------------------------
    % Ez a forma a kerdesed szerinti SoH-alapu degradacios BESS CAPEX-et
    % hasznalja, nem a teljes BESS beruhazast.
    T.simPeriodNetSaving_HUF = ...
        T.periodGrossOperationalSaving_HUF - ...
        T.bessDegradationCapex_HUF - ...
        T.simPeriodBESS_OPEX_HUF;

    % ---------------------------------------------------------------------
    % 2) Szimulacios idoszak beruhazasi NPV
    % ---------------------------------------------------------------------
    % Ez mar teljes incremental CAPEX-et von le, ezert BESS CAPEX valtoztatasra
    % egyertelmuen valtoznia kell.
    T.simPeriodInvestmentNPV_HUF = ...
        T.periodGrossOperationalSaving_HUF - ...
        T.incrementalCapexVsBaseline_HUF - ...
        T.simPeriodBESS_OPEX_HUF;

    T.simPeriodNetSaving_millionHUF = ...
        T.simPeriodNetSaving_HUF ./ 1e6;

    T.simPeriodInvestmentNPV_millionHUF = ...
        T.simPeriodInvestmentNPV_HUF ./ 1e6;
end


% =========================================================================
% LIFETIME ECONOMICS
% =========================================================================

function T = local_add_lifetime_economics(T, evalCfg)

    simYears = local_get_required_economics_value(evalCfg, 'simYears');
    horizonYears = local_get_required_economics_value(evalCfg, 'projectLifetime_years');
    r = local_get_required_economics_value(evalCfg, 'discountRate');
    bessLife = local_get_required_economics_value(evalCfg, 'bessLifetime_years');

    bessOpexFrac = local_get_required_economics_value(evalCfg, 'bess_opex_frac_per_year');

    annualGrossBenefit_HUF = ...
        T.periodGrossOperationalSaving_HUF ./ simYears;

    annualBESS_OPEX_HUF = ...
        T.capexBESS_HUF .* bessOpexFrac;

    annualBessNetCashflow_HUF = ...
        annualGrossBenefit_HUF - annualBESS_OPEX_HUF;

    replacementBESS_HUF = local_replacement_present_value( ...
        T.capexBESS_HUF, ...
        bessLife, ...
        horizonYears, ...
        r);

    T.annualGrossBenefit_HUF = annualGrossBenefit_HUF;
    T.annualBessNetCashflow_HUF = annualBessNetCashflow_HUF;
    T.replacementBESS_PV_HUF = replacementBESS_HUF;

    T.lifetimeSystemNPV_HUF = ...
        -T.incrementalCapexVsBaseline_HUF + ...
        local_present_value_annuity(annualBessNetCashflow_HUF, r, horizonYears) - ...
        replacementBESS_HUF;

    T.lifetimeBessAddedValueNPV_HUF = ...
        -T.capexBESS_HUF + ...
        local_present_value_annuity(annualBessNetCashflow_HUF, r, horizonYears) - ...
        replacementBESS_HUF;

    T.lifetimeSystemNPV_millionHUF = ...
        T.lifetimeSystemNPV_HUF ./ 1e6;

    T.lifetimeBessAddedValueNPV_millionHUF = ...
        T.lifetimeBessAddedValueNPV_HUF ./ 1e6;

    T.lifetimeHorizon_years = ...
        repmat(horizonYears, height(T), 1);
end


function T = local_add_payback_columns(T, evalCfg)

    simYears = local_get_required_economics_value(evalCfg, 'simYears');
    bessOpexFrac = local_get_required_economics_value(evalCfg, 'bess_opex_frac_per_year');

    annualGrossBenefit_HUF = ...
        T.periodGrossOperationalSaving_HUF ./ simYears;

    annualBessNetBenefit_HUF = ...
        annualGrossBenefit_HUF - ...
        T.capexBESS_HUF .* bessOpexFrac;

    T.systemPayback_years = ...
        local_simple_payback(T.incrementalCapexVsBaseline_HUF, annualBessNetBenefit_HUF);

    T.bessPayback_years = ...
        local_simple_payback(T.capexBESS_HUF, annualBessNetBenefit_HUF);
end


% =========================================================================
% HEATMAP CREATION
% =========================================================================

function metricSpecs = local_metric_specs()
% LOCAL_METRIC_SPECS
%
% Csak gazdasagi, riportba valo abrakat keszitunk.
% Az operativ megtakaritas kulon hoterkepkent nem jelenik meg.
%
% showBestMarker:
%   true  -> csak ezen a heatmapen jelenik meg az AC/DC global best csillag.
%   false -> nincs csillag.

    metricSpecs = struct( ...
        'field', { ...
            'simPeriodNetSaving_millionHUF', ...
            'simPeriodInvestmentNPV_millionHUF', ...
            'lifetimeSystemNPV_millionHUF', ...
            'lifetimeBessAddedValueNPV_millionHUF'}, ...
        'label', { ...
            'Szimulacios idoszak netto megtakaritas', ...
            'Szimulacios idoszak beruhazasi NPV', ...
            'Elettartam-alapu NPV baseline-hoz kepest', ...
            'Elettartam-alapu BESS-only NPV'}, ...
        'unit', { ...
            'millio HUF', ...
            'millio HUF', ...
            'millio HUF', ...
            'millio HUF'}, ...
        'tag', { ...
            'sim_period_net_saving', ...
            'sim_period_investment_npv', ...
            'lifetime_system_npv', ...
            'lifetime_bess_npv'}, ...
        'rangeGroup', { ...
            'fixed_0_400', ...
            'fixed_0_400', ...
            'fixed_0_400', ...
            'fixed_0_400'}, ...
        'showBestMarker', { ...
            false, ...
            false, ...
            false, ...
            true});
end


function colorRanges = local_fixed_color_ranges(metricSpecs)

    colorRanges = struct();

    for i = 1:numel(metricSpecs)

        groupName = char(metricSpecs(i).rangeGroup);

        if ~isfield(colorRanges, groupName)
            colorRanges.(groupName) = [0, 400];
        end
    end
end


function bestMarkerInfo = local_get_best_marker_info(T, metricSpecs)

    bestMarkerInfo = struct();
    bestMarkerInfo.enabled = false;
    bestMarkerInfo.metricField = "";
    bestMarkerInfo.P_inv_kW = NaN;
    bestMarkerInfo.dcac_ratio = NaN;
    bestMarkerInfo.BESS_PV_ratio = NaN;
    bestMarkerInfo.value = NaN;

    markerFields = strings(0, 1);

    for i = 1:numel(metricSpecs)
        if isfield(metricSpecs(i), 'showBestMarker') && metricSpecs(i).showBestMarker
            markerFields(end+1, 1) = string(metricSpecs(i).field); %#ok<AGROW>
        end
    end

    if isempty(markerFields)
        return;
    end

    if numel(markerFields) > 1
        error('Only one heatmap metric can have showBestMarker = true.');
    end

    markerField = char(markerFields(1));

    if ~ismember(markerField, T.Properties.VariableNames)
        error('Best-marker metric is missing from candidate table: %s', markerField);
    end

    validMask = isfinite(T.(markerField)) & ...
                isfinite(T.P_inv_kW) & ...
                isfinite(T.dcac_ratio) & ...
                isfinite(T.BESS_PV_ratio);

    if ~any(validMask)
        return;
    end

    Tv = T(validMask, :);

    [bestValue, bestLocalIdx] = max(Tv.(markerField));

    bestMarkerInfo.enabled = true;
    bestMarkerInfo.metricField = string(markerField);
    bestMarkerInfo.P_inv_kW = Tv.P_inv_kW(bestLocalIdx);
    bestMarkerInfo.dcac_ratio = Tv.dcac_ratio(bestLocalIdx);
    bestMarkerInfo.BESS_PV_ratio = Tv.BESS_PV_ratio(bestLocalIdx);
    bestMarkerInfo.value = bestValue;
end


function bestCandidateTable = local_make_heatmaps_for_coupling( ...
    T, couplingLabel, figureFolder, metricSpecs, colorRanges, bestMarkerInfo)

    invValues = unique(T.P_inv_kW(isfinite(T.P_inv_kW)));
    invValues = sort(invValues(:).');

    bestCandidateTable = table();

    for iInv = 1:numel(invValues)

        invValue = invValues(iInv);

        Ti = T(abs(T.P_inv_kW - invValue) <= 1e-6, :);

        if isempty(Ti) || height(Ti) == 0
            continue;
        end

        for m = 1:numel(metricSpecs)

            [~, bestRow] = local_plot_metric_heatmap( ...
                Ti, ...
                couplingLabel, ...
                invValue, ...
                metricSpecs(m), ...
                colorRanges, ...
                figureFolder, ...
                bestMarkerInfo);

            if ~isempty(bestRow) && height(bestRow) > 0

                summaryRow = local_build_best_candidate_summary( ...
                    bestRow, ...
                    couplingLabel, ...
                    invValue, ...
                    metricSpecs(m));

                bestCandidateTable = local_append_table_union(bestCandidateTable, summaryRow);
            end
        end
    end
end


function [fig, bestRow] = local_plot_metric_heatmap( ...
    T, couplingLabel, invValue, metricSpec, colorRanges, figureFolder, bestMarkerInfo)

    fieldName = metricSpec.field;
    rangeGroup = char(metricSpec.rangeGroup);

    if ~ismember(fieldName, T.Properties.VariableNames)
        error('Missing heatmap field: %s', fieldName);
    end

    if ~isfield(colorRanges, rangeGroup)
        error('Missing color range group: %s', rangeGroup);
    end

    validMask = ...
        isfinite(T.(fieldName)) & ...
        isfinite(T.dcac_ratio) & ...
        isfinite(T.BESS_PV_ratio);

    Tv = T(validMask, :);

    if isempty(Tv) || height(Tv) == 0
        fig = [];
        bestRow = table();
        return;
    end

    xVals = unique(Tv.dcac_ratio);
    yVals = unique(Tv.BESS_PV_ratio);

    xVals = sort(xVals(:).');
    yVals = sort(yVals(:));

    Z = NaN(numel(yVals), numel(xVals));
    idxMap = NaN(numel(yVals), numel(xVals));

    for i = 1:height(Tv)

        ix = find(abs(xVals - Tv.dcac_ratio(i)) <= 1e-9, 1, 'first');
        iy = find(abs(yVals - Tv.BESS_PV_ratio(i)) <= 1e-9, 1, 'first');

        if isempty(ix) || isempty(iy)
            continue;
        end

        thisValue = Tv.(fieldName)(i);

        if ~isfinite(Z(iy, ix)) || thisValue > Z(iy, ix)
            Z(iy, ix) = thisValue;
            idxMap(iy, ix) = i;
        end
    end

    if all(~isfinite(Z(:)))
        fig = [];
        bestRow = table();
        return;
    end

    [bestValue, bestLinearIdx] = local_max_finite(Z);
    [bestIy, bestIx] = ind2sub(size(Z), bestLinearIdx);

    bestSourceIdx = idxMap(bestIy, bestIx);
    bestRow = Tv(bestSourceIdx, :);

    colorLimits = colorRanges.(rangeGroup);

    figName = sprintf( ...
        '%s | %s | P_inv %.0f kW', ...
        upper(char(couplingLabel)), ...
        metricSpec.label, ...
        invValue);

    fig = figure( ...
        'Name', figName, ...
        'Color', 'w', ...
        'Position', [80, 80, 1500, 900]);

    ax = axes(fig);
    hold(ax, 'on');

    set(ax, 'Color', [0.94, 0.94, 0.94]);

    h = imagesc(ax, xVals, yVals, Z);
    set(h, 'AlphaData', isfinite(Z));

    set(ax, 'YDir', 'normal');

    colormap(ax, local_red_yellow_green_colormap(256));

    % Fixed 0...400 million HUF visual range.
    % Values below 0 and above 400 are clipped only in color, not in labels.
    caxis(ax, colorLimits);

    cb = colorbar(ax);
    cb.Label.String = metricSpec.unit;
    cb.Label.FontSize = 13;
    cb.Label.FontWeight = 'bold';
    cb.FontSize = 12;
    cb.LineWidth = 1.1;

    local_draw_cell_grid(ax, xVals, yVals);
    local_add_cell_value_labels(ax, xVals, yVals, Z, colorLimits);

    if local_should_draw_best_marker(metricSpec, invValue, bestMarkerInfo)
        local_draw_best_marker_next_to_value(ax, xVals, yVals, bestMarkerInfo, colorLimits);
    end

    xlabel(ax, 'PV/inverter ratio P_{PV}/P_{inv} [-]', ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    ylabel(ax, 'BESS/PV ratio E_{BESS}/P_{PV} [kWh/kWp]', ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    title(ax, { ...
        sprintf('%s - %s, P_{inv}=%.0f kW', ...
        upper(char(couplingLabel)), metricSpec.label, invValue), ...
        sprintf('Fixed color range: %.0f ... %.0f %s', ...
        colorLimits(1), colorLimits(2), metricSpec.unit)}, ...
        'FontSize', 15, ...
        'FontWeight', 'bold');

    set(ax, ...
        'FontSize', 12, ...
        'LineWidth', 1.20, ...
        'TickDir', 'out', ...
        'Layer', 'top', ...
        'Box', 'on');

    local_apply_sparse_ticks(ax, xVals, yVals);

    xlim(ax, local_axis_limits_from_values(xVals));
    ylim(ax, local_axis_limits_from_values(yVals));

    fileName = sprintf('%s_%s_pinv_%s', ...
        lower(char(couplingLabel)), ...
        metricSpec.tag, ...
        local_number_to_tag(invValue));

    local_save_figure(fig, figureFolder, fileName);
end


function tf = local_should_draw_best_marker(metricSpec, invValue, bestMarkerInfo)

    tf = false;

    if ~isfield(metricSpec, 'showBestMarker') || ~metricSpec.showBestMarker
        return;
    end

    if ~isfield(bestMarkerInfo, 'enabled') || ~bestMarkerInfo.enabled
        return;
    end

    if string(metricSpec.field) ~= string(bestMarkerInfo.metricField)
        return;
    end

    if abs(invValue - bestMarkerInfo.P_inv_kW) > 1e-6
        return;
    end

    tf = true;
end


function local_draw_best_marker_next_to_value(ax, xVals, yVals, bestMarkerInfo, colorLimits)

    ix = find(abs(xVals - bestMarkerInfo.dcac_ratio) <= 1e-9, 1, 'first');
    iy = find(abs(yVals - bestMarkerInfo.BESS_PV_ratio) <= 1e-9, 1, 'first');

    if isempty(ix) || isempty(iy)
        return;
    end

    x = xVals(ix);
    y = yVals(iy);

    xOffset = local_marker_x_offset(xVals);
    yOffset = local_marker_y_offset(yVals);

    markerColor = local_choose_marker_color(bestMarkerInfo.value, colorLimits);

    text(ax, x + xOffset, y + yOffset, '*', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 22, ...
        'FontWeight', 'bold', ...
        'Color', markerColor, ...
        'Clipping', 'on');
end


function offset = local_marker_x_offset(xVals)

    if numel(xVals) <= 1
        offset = 0.08;
        return;
    end

    dx = min(diff(sort(xVals)));
    offset = 0.22 * dx;
end


function offset = local_marker_y_offset(yVals)

    if numel(yVals) <= 1
        offset = 0.00;
        return;
    end

    dy = min(diff(sort(yVals)));
    offset = 0.00 * dy;
end


function color = local_choose_marker_color(value, colorLimits)

    t = (value - colorLimits(1)) ./ max(colorLimits(2) - colorLimits(1), eps);
    t = max(0, min(1, t));

    if t > 0.35 && t < 0.72
        color = [0.05, 0.05, 0.05];
    else
        color = [1, 1, 1];
    end
end


function cmap = local_red_yellow_green_colormap(n)

    if nargin < 1
        n = 256;
    end

    red = [178, 24, 43] ./ 255;
    orange = [244, 109, 67] ./ 255;
    yellow = [255, 221, 84] ./ 255;
    lightGreen = [166, 217, 106] ./ 255;
    green = [26, 150, 65] ./ 255;

    anchors = [ ...
        red; ...
        orange; ...
        yellow; ...
        lightGreen; ...
        green];

    xAnchor = linspace(0, 1, size(anchors, 1));
    x = linspace(0, 1, n);

    cmap = zeros(n, 3);

    for c = 1:3
        cmap(:, c) = interp1(xAnchor, anchors(:, c), x, 'pchip');
    end

    cmap = max(0, min(1, cmap));
end


function local_add_cell_value_labels(ax, xVals, yVals, Z, colorLimits)

    nX = numel(xVals);
    nY = numel(yVals);
    nCells = nX * nY;

    if nCells <= 60
        fontSize = 10;
    elseif nCells <= 120
        fontSize = 8;
    else
        fontSize = 6;
    end

    for iy = 1:nY
        for ix = 1:nX

            value = Z(iy, ix);

            if ~isfinite(value)
                continue;
            end

            labelText = local_format_heatmap_value(value);
            textColor = local_choose_text_color(value, colorLimits);

            text(ax, xVals(ix), yVals(iy), labelText, ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', fontSize, ...
                'FontWeight', 'bold', ...
                'Color', textColor, ...
                'Clipping', 'on');
        end
    end
end


function labelText = local_format_heatmap_value(value)

    absValue = abs(value);

    if absValue >= 100
        labelText = sprintf('%.0f', value);
    elseif absValue >= 10
        labelText = sprintf('%.1f', value);
    else
        labelText = sprintf('%.2f', value);
    end
end


function color = local_choose_text_color(value, colorLimits)

    t = (value - colorLimits(1)) ./ max(colorLimits(2) - colorLimits(1), eps);
    t = max(0, min(1, t));

    if t > 0.35 && t < 0.72
        color = [0.05, 0.05, 0.05];
    else
        color = [1, 1, 1];
    end
end


function local_draw_cell_grid(ax, xVals, yVals)

    if numel(xVals) > 40 || numel(yVals) > 40
        return;
    end

    xEdges = local_cell_edges(xVals);
    yEdges = local_cell_edges(yVals);

    for i = 1:numel(xEdges)
        line(ax, [xEdges(i), xEdges(i)], [yEdges(1), yEdges(end)], ...
            'Color', [1, 1, 1], ...
            'LineWidth', 0.5, ...
            'HandleVisibility', 'off');
    end

    for i = 1:numel(yEdges)
        line(ax, [xEdges(1), xEdges(end)], [yEdges(i), yEdges(i)], ...
            'Color', [1, 1, 1], ...
            'LineWidth', 0.5, ...
            'HandleVisibility', 'off');
    end
end


function edges = local_cell_edges(vals)

    vals = vals(:).';

    if numel(vals) == 1
        step = max(abs(vals(1)) * 0.05, 0.5);
        edges = [vals(1) - step, vals(1) + step];
        return;
    end

    mid = (vals(1:end-1) + vals(2:end)) ./ 2;

    firstStep = mid(1) - vals(1);
    lastStep = vals(end) - mid(end);

    edges = [vals(1) - firstStep, mid, vals(end) + lastStep];
end


function lim = local_axis_limits_from_values(vals)

    edges = local_cell_edges(vals);
    lim = [edges(1), edges(end)];
end


function local_apply_sparse_ticks(ax, xVals, yVals)

    maxTicks = 8;

    if numel(xVals) > maxTicks
        ix = unique(round(linspace(1, numel(xVals), maxTicks)));
        ax.XTick = xVals(ix);
    else
        ax.XTick = xVals;
    end

    if numel(yVals) > maxTicks
        iy = unique(round(linspace(1, numel(yVals), maxTicks)));
        ax.YTick = yVals(iy);
    else
        ax.YTick = yVals;
    end

    ax.XTickLabel = compose('%.2f', ax.XTick);
    ax.YTickLabel = compose('%.2f', ax.YTick);

    ax.XTickLabelRotation = 0;
    ax.YTickLabelRotation = 0;
end


function [bestValue, bestLinearIdx] = local_max_finite(Z)

    finiteMask = isfinite(Z);

    if ~any(finiteMask(:))
        bestValue = NaN;
        bestLinearIdx = 1;
        return;
    end

    values = Z;
    values(~finiteMask) = -inf;

    [bestValue, bestLinearIdx] = max(values(:));
end


function local_save_figure(fig, figureFolder, fileName)

    local_ensure_folder(figureFolder);

    savefig(fig, fullfile(figureFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(figureFolder, [fileName, '.png']), 'Resolution', 300);
    catch
        saveas(fig, fullfile(figureFolder, [fileName, '.png']));
    end

    try
        exportgraphics(fig, fullfile(figureFolder, [fileName, '.pdf']), 'ContentType', 'vector');
    catch
        % PDF export is optional.
    end
end


% =========================================================================
% BEST CANDIDATE EXPORT
% =========================================================================

function row = local_build_best_candidate_summary(bestRow, couplingLabel, invValue, metricSpec)

    row = table();

    row.coupling = string(couplingLabel);
    row.inverter_kW = invValue;
    row.heatmapMetric = string(metricSpec.label);
    row.heatmapField = string(metricSpec.field);
    row.heatmapValue_millionHUF = local_get_scalar(bestRow, metricSpec.field);

    row.candidateID = local_get_string(bestRow, 'candidateID');

    row.P_inv_kW = local_get_scalar(bestRow, 'P_inv_kW');
    row.P_PV_kW = local_get_scalar(bestRow, 'P_PV_kW');
    row.dcac_ratio = local_get_scalar(bestRow, 'dcac_ratio');

    row.BESS_PV_ratio = local_get_scalar(bestRow, 'BESS_PV_ratio');
    row.E_BESS_kWh = local_get_scalar(bestRow, 'E_BESS_kWh');
    row.P_BESS_kW = local_get_scalar(bestRow, 'P_BESS_kW');
    row.bestContract_kW = local_get_scalar(bestRow, 'bestContract_kW');

    row.simPeriodNetSaving_millionHUF = local_get_scalar(bestRow, 'simPeriodNetSaving_millionHUF');
    row.simPeriodInvestmentNPV_millionHUF = local_get_scalar(bestRow, 'simPeriodInvestmentNPV_millionHUF');
    row.lifetimeSystemNPV_millionHUF = local_get_scalar(bestRow, 'lifetimeSystemNPV_millionHUF');
    row.lifetimeBessAddedValueNPV_millionHUF = local_get_scalar(bestRow, 'lifetimeBessAddedValueNPV_millionHUF');

    row.periodGrossOperationalSaving_HUF = local_get_scalar(bestRow, 'periodGrossOperationalSaving_HUF');
    row.periodSelfConsumptionValue_HUF = local_get_scalar(bestRow, 'periodSelfConsumptionValue_HUF');
    row.periodImportReductionValue_HUF = local_get_scalar(bestRow, 'periodImportReductionValue_HUF');
    row.periodExportRevenueChange_HUF = local_get_scalar(bestRow, 'periodExportRevenueChange_HUF');

    row.additionalSelfConsumption_kWh = local_get_scalar(bestRow, 'additionalSelfConsumption_kWh');
    row.selfConsumedPvForLoad_kWh = local_get_scalar(bestRow, 'selfConsumedPvForLoad_kWh');
    row.baselineSelfConsumedPvForLoad_kWh = local_get_scalar(bestRow, 'baselineSelfConsumedPvForLoad_kWh');

    row.annualEquivalentCycles = local_get_scalar(bestRow, 'annualEquivalentCycles');
    row.totalEquivalentCycles = local_get_scalar(bestRow, 'totalEquivalentCycles');
    row.finalSoH = local_get_scalar(bestRow, 'finalSoH');

    row.selfSufficiency_pct = local_get_scalar(bestRow, 'selfSufficiency_pct');
    row.selfConsumption_pct = local_get_scalar(bestRow, 'selfConsumption_pct');

    row.loadEnergy_kWh = local_get_scalar(bestRow, 'loadEnergy_kWh');
    row.pvEnergyAvailable_kWh = local_get_scalar(bestRow, 'pvEnergyAvailable_kWh');
    row.pvUsedEnergy_kWh = local_get_scalar(bestRow, 'pvUsedEnergy_kWh');
    row.pvUtilization_pct = local_get_scalar(bestRow, 'pvUtilization_pct');

    row.pvToLoad_kWh = local_get_scalar(bestRow, 'pvToLoad_kWh');
    row.pvToBess_kWh = local_get_scalar(bestRow, 'pvToBess_kWh');
    row.bessToLoad_kWh = local_get_scalar(bestRow, 'bessToLoad_kWh');

    row.bessDischarge_kWh = local_get_scalar(bestRow, 'bessDischarge_kWh');
    row.annualBessDischarge_kWh = local_get_scalar(bestRow, 'annualBessDischarge_kWh');

    row.gridImport_kWh = local_get_scalar(bestRow, 'gridImport_kWh');
    row.gridExport_kWh = local_get_scalar(bestRow, 'gridExport_kWh');
    row.gridImportReduction_kWh = local_get_scalar(bestRow, 'gridImportReduction_kWh');
    row.gridExportIncrease_kWh = local_get_scalar(bestRow, 'gridExportIncrease_kWh');

    row.curtailment_kWh = local_get_scalar(bestRow, 'curtailment_kWh');
    row.curtailmentReduction_kWh = local_get_scalar(bestRow, 'curtailmentReduction_kWh');

    row.systemPayback_years = local_get_scalar(bestRow, 'systemPayback_years');
    row.bessPayback_years = local_get_scalar(bestRow, 'bessPayback_years');

    row.bessDegradationCapex_HUF = local_get_scalar(bestRow, 'bessDegradationCapex_HUF');
    row.capexPV_HUF = local_get_scalar(bestRow, 'capexPV_HUF');
    row.capexBESS_HUF = local_get_scalar(bestRow, 'capexBESS_HUF');
    row.capexInverter_HUF = local_get_scalar(bestRow, 'capexInverter_HUF');
    row.incrementalCapexVsBaseline_HUF = local_get_scalar(bestRow, 'incrementalCapexVsBaseline_HUF');
end


function value = local_get_scalar(T, fieldName)

    if ismember(fieldName, T.Properties.VariableNames)
        value = T.(fieldName)(1);
    else
        value = NaN;
    end
end


function value = local_get_string(T, fieldName)

    if ismember(fieldName, T.Properties.VariableNames)
        value = string(T.(fieldName)(1));
    else
        value = "";
    end
end


% =========================================================================
% ECONOMIC HELPERS
% =========================================================================

function value = local_get_required_economics_value(evalCfg, fieldName)

    if ~isfield(evalCfg, 'economics')
        error('evalCfg.economics is missing.');
    end

    if ~isfield(evalCfg.economics, fieldName)
        error('evalCfg.economics.%s is missing. The evaluation must not use hidden default values.', fieldName);
    end

    value = evalCfg.economics.(fieldName);

    if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value)
        error('evalCfg.economics.%s must be a finite numeric scalar.', fieldName);
    end
end


function value = local_get_required_cost_value(cfg, fieldName)

    if ~isfield(cfg, 'cost')
        error('cfg.cost is missing.');
    end

    if ~isfield(cfg.cost, fieldName)
        error('cfg.cost.%s is missing. The evaluation must not use hidden default values.', fieldName);
    end

    value = cfg.cost.(fieldName);

    if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value)
        error('cfg.cost.%s must be a finite numeric scalar.', fieldName);
    end
end


function pv = local_present_value_annuity(annualValue, r, n)

    if r == 0
        pv = annualValue .* n;
    else
        pv = annualValue .* ((1 - (1 + r)^(-n)) / r);
    end
end


function replacementPV = local_replacement_present_value(capex, componentLife, horizonYears, r)

    replacementPV = zeros(size(capex));

    if componentLife <= 0
        error('Component lifetime must be positive.');
    end

    replacementYears = componentLife:componentLife:(horizonYears - 1e-9);

    for i = 1:numel(replacementYears)

        y = replacementYears(i);

        replacementPV = replacementPV + capex ./ ((1 + r) .^ y);
    end
end


function payback = local_simple_payback(capex, annualNetBenefit)

    payback = inf(size(capex));

    mask = annualNetBenefit > 0;

    payback(mask) = capex(mask) ./ annualNetBenefit(mask);

    payback(capex <= 0 & annualNetBenefit >= 0) = 0;
end


% =========================================================================
% VALIDATION
% =========================================================================

function local_validate_cfg(cfg)

    if nargin < 1 || isempty(cfg)
        error('Missing input: cfg.');
    end

    local_require_struct_fields(cfg, {'cost'}, 'cfg');

    requiredCostFields = { ...
        'pv_huf_per_kWp', ...
        'bess_huf_per_kWh', ...
        'bess_power_huf_per_kW', ...
        'inverter_huf_per_kW', ...
        'grid_import_huf_per_kWh', ...
        'grid_export_huf_per_kWh'};

    local_require_struct_fields(cfg.cost, requiredCostFields, 'cfg.cost');

    for i = 1:numel(requiredCostFields)
        local_get_required_cost_value(cfg, requiredCostFields{i});
    end
end


function local_validate_evalcfg(evalCfg)

    if nargin < 1 || isempty(evalCfg)
        error('Missing input: evalCfg.');
    end

    local_require_struct_fields(evalCfg, {'output', 'economics'}, 'evalCfg');
    local_require_struct_fields(evalCfg.output, {'baseFolder'}, 'evalCfg.output');

    requiredEconomicsFields = { ...
        'simYears', ...
        'projectLifetime_years', ...
        'pvLifetime_years', ...
        'inverterLifetime_years', ...
        'bessLifetime_years', ...
        'bessEolSohLoss', ...
        'discountRate', ...
        'pv_opex_frac_per_year', ...
        'bess_opex_frac_per_year', ...
        'inverter_opex_frac_per_year'};

    local_require_struct_fields(evalCfg.economics, requiredEconomicsFields, 'evalCfg.economics');

    for i = 1:numel(requiredEconomicsFields)
        local_get_required_economics_value(evalCfg, requiredEconomicsFields{i});
    end
end


function local_require_struct_fields(S, fieldNames, structName)

    for i = 1:numel(fieldNames)

        f = fieldNames{i};

        if ~isfield(S, f)
            error('Missing field: %s.%s', structName, f);
        end
    end
end


function local_require_columns(T, requiredColumns, tableName)

    varNames = T.Properties.VariableNames;

    for i = 1:numel(requiredColumns)

        col = requiredColumns{i};

        if ~ismember(col, varNames)
            error('The %s does not contain the required column: %s', tableName, col);
        end
    end
end


function local_assert_finite_columns(T, columns, tableName)

    for i = 1:numel(columns)

        col = columns{i};

        if any(~isfinite(T.(col)))
            error('The %s column contains non-finite values: %s', tableName, col);
        end
    end
end


% =========================================================================
% GENERIC HELPERS
% =========================================================================

function T = local_add_optional_numeric_column(T, colName, value)

    if ~ismember(colName, T.Properties.VariableNames)
        T.(colName) = value .* ones(height(T), 1);
    end
end


function local_ensure_folder(folderPath)

    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end
end


function out = local_append_table_union(A, B)

    if isempty(B) || height(B) == 0
        out = A;
        return;
    end

    if isempty(A) || height(A) == 0
        out = B;
        return;
    end

    varsA = string(A.Properties.VariableNames);
    varsB = string(B.Properties.VariableNames);

    allVars = unique([varsA, varsB], 'stable');

    A = local_add_missing_table_vars(A, allVars, B);
    B = local_add_missing_table_vars(B, allVars, A);

    A = A(:, cellstr(allVars));
    B = B(:, cellstr(allVars));

    out = [A; B];
end


function T = local_add_missing_table_vars(T, allVars, referenceTable)

    currentVars = string(T.Properties.VariableNames);

    for i = 1:numel(allVars)

        varName = char(allVars(i));

        if ismember(varName, currentVars)
            continue;
        end

        if ismember(varName, referenceTable.Properties.VariableNames)

            refValue = referenceTable.(varName);

            if isnumeric(refValue) || islogical(refValue)
                T.(varName) = NaN(height(T), 1);
            elseif isstring(refValue)
                T.(varName) = strings(height(T), 1);
            elseif iscellstr(refValue)
                T.(varName) = repmat({''}, height(T), 1);
            elseif isdatetime(refValue)
                T.(varName) = NaT(height(T), 1);
            else
                T.(varName) = strings(height(T), 1);
            end

        else
            T.(varName) = NaN(height(T), 1);
        end
    end
end


function tag = local_number_to_tag(value)

    tag = sprintf('%.4f', value);

    tag = strrep(tag, '-', 'm');
    tag = strrep(tag, '.', 'p');
end