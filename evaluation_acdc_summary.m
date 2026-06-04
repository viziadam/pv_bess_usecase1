% function acdcResult = evaluation_acdc_summary(cfg, options)
% % EVALUATION_ACDC_SUMMARY
% %
% % AC/DC osszesito kiertekeles a grid-connected PV+BESS self-consumption
% % esettanulmanyhoz.
% %
% % A fuggveny a ket mar lefutott eredmenyfajlt hasonlitja ossze:
% %   results/results_dccoupled.mat
% %   results/results_accoupled.mat
% %
% % A regi single-topology evaluation abrakat alapertelmezetten nem generalja,
% % mert az AC/DC riportban csak az 5 kivalasztott jelolt szerepeljen:
% %   1) legjobb csak PV
% %   2) legjobb DC LCSE szerint
% %   3) legjobb DC NPV szerint
% %   4) legjobb AC LCSE szerint
% %   5) legjobb AC NPV szerint
% 
%     if nargin < 2 || isempty(options)
%         options = struct();
%     end
% 
%     options = local_default_options(cfg, options);
% 
%     if ~exist(options.outputFolder, 'dir')
%         mkdir(options.outputFolder);
%     end
% 
%     tableFolder = fullfile(options.outputFolder, 'tables');
%     figureFolder = fullfile(options.outputFolder, 'figures');
% 
%     if ~exist(tableFolder, 'dir')
%         mkdir(tableFolder);
%     end
% 
%     if ~exist(figureFolder, 'dir')
%         mkdir(figureFolder);
%     end
% 
%     fprintf('\n============================================================\n');
%     fprintf('AC/DC combined evaluation started.\n');
%     fprintf('Output folder: %s\n', options.outputFolder);
%     fprintf('============================================================\n\n');
% 
%     [dcEval, dcTable] = local_run_single_coupling_evaluation(cfg, "dc", options);
%     [acEval, acTable] = local_run_single_coupling_evaluation(cfg, "ac", options);
% 
%     dcTable = local_add_report_columns(dcTable, dcEval.evalCfg, cfg);
%     acTable = local_add_report_columns(acTable, acEval.evalCfg, cfg);
% 
%     combinedTable = [dcTable; acTable];
% 
%     selected = local_select_report_candidates(combinedTable);
%     selectedTable = selected.table;
%     selectedLabels = selected.labels;
%     selectedShortLabels = selected.shortLabels;
% 
%     selectedSummaryTable = local_build_selected_summary_table(selectedTable, selectedLabels);
%     bessOnlyTable = local_build_bess_only_table(selectedTable, selectedLabels);
% 
%     % ---------------------------------------------------------------------
%     % 3D LCSE / NPV abrak kulon DC es AC esetre
%     % ---------------------------------------------------------------------
%     local_plot_3d_metric(dcTable, 'LCSE_HUF_per_kWh_saved', ...
%         'LCSE - megtakaritott energia fajlagos koltsege', 'Ft/kWh', 'min', figureFolder, 'dc');
% 
%     local_plot_3d_metric(dcTable, 'NPV_millionHUF', ...
%         'Netto jelenertek', 'millio Ft', 'max', figureFolder, 'dc');
% 
%     local_plot_3d_metric(acTable, 'LCSE_HUF_per_kWh_saved', ...
%         'LCSE - megtakaritott energia fajlagos koltsege', 'Ft/kWh', 'min', figureFolder, 'ac');
% 
%     local_plot_3d_metric(acTable, 'NPV_millionHUF', ...
%         'Netto jelenertek', 'millio Ft', 'max', figureFolder, 'ac');
% 
%     % ---------------------------------------------------------------------
%     % 5 jelolt osszesito abrak
%     % ---------------------------------------------------------------------
%     local_plot_value_cost_payback_summary(selectedTable, selectedShortLabels, figureFolder);
%     local_plot_self_consumption_summary(selectedTable, selectedShortLabels, figureFolder);
%     local_plot_useful_energy_and_losses(selectedTable, selectedShortLabels, figureFolder);
% 
%     % ---------------------------------------------------------------------
%     % Mentesek
%     % ---------------------------------------------------------------------
%     writetable(combinedTable, fullfile(tableFolder, 'acdc_combined_candidate_table.csv'));
%     writetable(selectedSummaryTable, fullfile(tableFolder, 'acdc_selected_candidates_summary.csv'));
%     writetable(bessOnlyTable, fullfile(tableFolder, 'acdc_selected_bess_only_period_value_table.csv'));
% 
%     acdcResult = struct();
%     acdcResult.createdAt = datetime('now');
%     acdcResult.options = options;
%     acdcResult.dcEvaluation = dcEval;
%     acdcResult.acEvaluation = acEval;
%     acdcResult.combinedTable = combinedTable;
%     acdcResult.selectedTable = selectedTable;
%     acdcResult.selectedSummaryTable = selectedSummaryTable;
%     acdcResult.selectedBessOnlyValueTable = bessOnlyTable;
%     acdcResult.outputFolder = options.outputFolder;
% 
%     save(fullfile(options.outputFolder, 'evaluation_acdc_summary_result.mat'), ...
%         'acdcResult', '-v7.3');
% 
%     fprintf('\nAC/DC combined evaluation finished.\n');
%     fprintf('Selected candidate summary saved: %s\n', ...
%         fullfile(tableFolder, 'acdc_selected_candidates_summary.csv'));
% end
% 
% 
% % =========================================================================
% % DEFAULTS
% % =========================================================================
% function options = local_default_options(cfg, options)
% 
%     if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'figures')
%         error('cfg.paths.figures is required.');
%     end
% 
%     if ~isfield(cfg.paths, 'results')
%         error('cfg.paths.results is required.');
%     end
% 
%     if ~isfield(options, 'outputFolder')
%         options.outputFolder = fullfile(cfg.paths.figures, 'evaluation_acdc');
%     end
% 
%     if ~isfield(options, 'singleEvaluationFolderName')
%         options.singleEvaluationFolderName = 'single_topology_evaluation';
%     end
% 
%     if ~isfield(options, 'saveSingleTopologyEvaluationCsv')
%         options.saveSingleTopologyEvaluationCsv = false;
%     end
% 
%     % Fontos: AC/DC osszesiteskor a regi 3 jeloltes single-topology abrakat
%     % nem kerjuk, mert zavaro x tengelyt es mas logikat adnak.
%     if ~isfield(options, 'makeSingleTopologyPlots')
%         options.makeSingleTopologyPlots = false;
%     end
% end
% 
% 
% % =========================================================================
% % SINGLE TOPOLOGY EVALUATION
% % =========================================================================
% function [evaluationResult, T] = local_run_single_coupling_evaluation(cfg, coupling, options)
% 
%     cfgEval = cfg;
%     cfgEval.system.bessCoupling = coupling;
% 
%     evalCfg = create_evaluation_config(cfgEval);
% 
%     switch string(coupling)
%         case "dc"
%             evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_dccoupled.mat');
%         case "ac"
%             evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_accoupled.mat');
%         otherwise
%             error('Unknown coupling: %s', string(coupling));
%     end
% 
%     evalCfg.output.baseFolder = fullfile( ...
%         options.outputFolder, ...
%         options.singleEvaluationFolderName, ...
%         char(coupling));
% 
%     evalCfg.output.saveEvaluationCsv = options.saveSingleTopologyEvaluationCsv;
%     evalCfg.plots.makePlots = options.makeSingleTopologyPlots;
%     evalCfg.plots.make3DScatter = false;
% 
%     if ~isfile(evalCfg.input.resultFilePath)
%         error(['Missing %s result file: %s\n', ...
%                'Run the %s-coupled simulation before AC/DC summary evaluation.'], ...
%                upper(char(coupling)), evalCfg.input.resultFilePath, upper(char(coupling)));
%     end
% 
%     evaluationResult = evaluation(cfgEval, evalCfg);
%     T = evaluationResult.resultTable;
% 
%     T.Coupling = repmat(string(coupling), height(T), 1);
%     T = movevars(T, 'Coupling', 'Before', 1);
% end
% 
% 
% % =========================================================================
% % REPORT COLUMNS
% % =========================================================================
% function T = local_add_report_columns(T, evalCfg, cfg)
% 
%     simYears = evalCfg.economics.simYears;
%     pvLifetime = evalCfg.economics.pvLifetime_years;
%     inverterLifetime = evalCfg.economics.inverterLifetime_years;
% 
%     if simYears <= 0
%         error('evalCfg.economics.simYears must be positive.');
%     end
% 
%     n = height(T);
% 
%     finalSoH = local_col(T, 'finalSoH', ones(n, 1));
%     finalSoH(~isfinite(finalSoH)) = 1;
% 
%     capexPV = local_col(T, 'capexPV_HUF', zeros(n, 1));
%     capexInv = local_col(T, 'capexInverter_HUF', zeros(n, 1));
%     capexBess = local_col(T, 'capexBESS_HUF', zeros(n, 1));
% 
%     hasBess = local_col(T, 'E_BESS_kWh', zeros(n, 1)) > 1e-9;
% 
%     deltaSoH = max(0, 1 - finalSoH);
%     deltaSoH(~hasBess) = 0;
% 
%     % ---------------------------------------------------------------------
%     % Periodusra vetitett rendszerkoltsegek
%     % ---------------------------------------------------------------------
%     T.reportSimYears = repmat(simYears, n, 1);
%     T.reportDeltaSoH = deltaSoH;
% 
%     T.reportPeriodPVCapex_HUF = capexPV ./ pvLifetime .* simYears;
%     T.reportPeriodPVOpex_HUF = capexPV .* evalCfg.economics.pv_opex_frac_per_year .* simYears;
% 
%     T.reportPeriodInverterCapex_HUF = capexInv ./ inverterLifetime .* simYears;
%     T.reportPeriodInverterOpex_HUF = capexInv .* evalCfg.economics.inverter_opex_frac_per_year .* simYears;
% 
%     T.reportPeriodBessDegradation_HUF = (deltaSoH ./ 0.2) .* capexBess;
%     T.reportPeriodBessOpex_HUF = capexBess .* evalCfg.economics.bess_opex_frac_per_year .* simYears;
% 
%     T.reportPeriodInvestmentCost_HUF = ...
%         T.reportPeriodPVCapex_HUF + ...
%         T.reportPeriodPVOpex_HUF + ...
%         T.reportPeriodInverterCapex_HUF + ...
%         T.reportPeriodInverterOpex_HUF + ...
%         T.reportPeriodBessDegradation_HUF + ...
%         T.reportPeriodBessOpex_HUF;
% 
%     % A teljes szimulalt idoszak energiakoltseg-megtakaritasa.
%     T.reportPeriodCostSaving_HUF = local_col(T, 'energyCostSavings_HUF', zeros(n, 1));
% 
%     % Saját, egyszeru riportmutato: megtakaritas - periodusra allokalt koltsegek.
%     T.reportPeriodNetValue_HUF = ...
%         T.reportPeriodCostSaving_HUF - T.reportPeriodInvestmentCost_HUF;
% 
%     % ---------------------------------------------------------------------
%     % BESS-only periodusmutatok
%     % ---------------------------------------------------------------------
%     importPrice_HUF_per_kWh = local_get_import_price(T, cfg);
% 
%     T.reportPeriodBessAcSaving_HUF = ...
%         local_col(T, 'bessToLoad_kWh', zeros(n, 1)) .* importPrice_HUF_per_kWh;
% 
%     T.reportPeriodBessAcSaving_HUF(~hasBess) = 0;
% 
%     T.reportPeriodBessOnlyCost_HUF = ...
%         T.reportPeriodBessDegradation_HUF + T.reportPeriodBessOpex_HUF;
% 
%     T.reportPeriodBessOnlyNetValue_HUF = ...
%         T.reportPeriodBessAcSaving_HUF - T.reportPeriodBessOnlyCost_HUF;
% 
%     % ---------------------------------------------------------------------
%     % Energia es veszteseg bontas a teljes szimulalt idoszakra
%     % ---------------------------------------------------------------------
%     T.reportUsefulACEnergy_MWh = ...
%         (local_col(T, 'pvToLoad_kWh', zeros(n, 1)) + ...
%          local_col(T, 'bessToLoad_kWh', zeros(n, 1))) ./ 1000;
% 
%     invLoss = local_col(T, 'inverterConversionLoss_kWh', zeros(n, 1));
% 
%     if all(abs(invLoss) < 1e-12)
%         invLoss = local_col(T, 'inverterLoss_kWh', zeros(n, 1));
%     end
% 
%     T.reportInverterLoss_MWh = invLoss ./ 1000;
% 
%     T.reportDcdcLoss_MWh = ...
%         local_col(T, 'dcdcConversionLoss_kWh', zeros(n, 1)) ./ 1000;
% 
%     % Itt szandekosan nem a bessTotalInternalLoss_kWh mezot hasznaljuk,
%     % mert az SoC limit / ures-tele miatti nem hasznosult request veszteseggel
%     % nagyon nagyra tud noni. A fizikai belso akkuveszteseghez a cell loss a
%     % megfelelobb riportmező.
%     T.reportBessInternalLoss_MWh = ...
%         local_col(T, 'bessCellLoss_kWh', zeros(n, 1)) ./ 1000;
% 
%     T.reportCurtailment_MWh = ...
%         local_col(T, 'curtailment_kWh', zeros(n, 1)) ./ 1000;
% 
%     % ---------------------------------------------------------------------
%     % Technikai mutatok fallback mezokkel
%     % ---------------------------------------------------------------------
%     if ~ismember('selfConsumption_pct', T.Properties.VariableNames)
%         T.selfConsumption_pct = 100 * local_col(T, 'selfConsumptionRatio', zeros(n, 1));
%     end
% 
%     if ~ismember('selfSufficiency_pct', T.Properties.VariableNames)
%         T.selfSufficiency_pct = 100 * local_col(T, 'selfSufficiencyRatio', zeros(n, 1));
%     end
% 
%     if ~ismember('annualBessEquivalentCycles', T.Properties.VariableNames)
%         T.annualBessEquivalentCycles = local_col(T, 'bessEquivalentCycles', zeros(n, 1)) ./ simYears;
%     end
% end
% 
% 
% function importPrice = local_get_import_price(T, cfg)
% 
%     n = height(T);
% 
%     if isfield(cfg, 'cost') && isfield(cfg.cost, 'grid_import_huf_per_kWh')
%         importPrice = repmat(cfg.cost.grid_import_huf_per_kWh, n, 1);
%         return;
%     end
% 
%     if ismember('gridOnlyEnergyCost_HUF', T.Properties.VariableNames) && ...
%        ismember('loadEnergy_kWh', T.Properties.VariableNames)
%         importPrice = T.gridOnlyEnergyCost_HUF ./ max(T.loadEnergy_kWh, eps);
%         importPrice(~isfinite(importPrice)) = 0;
%         return;
%     end
% 
%     error('Cannot determine grid import price for BESS-only value calculation.');
% end
% 
% 
% function x = local_col(T, name, defaultValue)
% 
%     if ismember(name, T.Properties.VariableNames)
%         x = T.(name);
%     else
%         x = defaultValue;
%     end
% 
%     x = double(x);
% end
% 
% 
% % =========================================================================
% % CANDIDATE SELECTION
% % =========================================================================
% function selected = local_select_report_candidates(T)
% 
%     validBase = logical(T.wasSimulated) & ~logical(T.hasError);
% 
%     pvOnlyMask = validBase & T.E_BESS_kWh <= 1e-9;
% 
%     onlyPv = local_pick_best_row(T, pvOnlyMask, 'LCSE_HUF_per_kWh_saved', 'min', []);
% 
%     dcBessMask = validBase & T.Coupling == "dc" & T.E_BESS_kWh > 1e-9;
%     acBessMask = validBase & T.Coupling == "ac" & T.E_BESS_kWh > 1e-9;
% 
%     dcBestLcse = local_pick_best_row(T, dcBessMask, 'LCSE_HUF_per_kWh_saved', 'min', []);
%     dcBestNpv = local_pick_best_row(T, dcBessMask, 'NPV_millionHUF', 'max', dcBestLcse);
% 
%     acBestLcse = local_pick_best_row(T, acBessMask, 'LCSE_HUF_per_kWh_saved', 'min', []);
%     acBestNpv = local_pick_best_row(T, acBessMask, 'NPV_millionHUF', 'max', acBestLcse);
% 
%     selectedTable = [onlyPv; dcBestLcse; dcBestNpv; acBestLcse; acBestNpv];
% 
%     labels = [ ...
%         "Legjobb csak PV"; ...
%         "Legjobb DC - LCSE"; ...
%         "Legjobb DC - NPV"; ...
%         "Legjobb AC - LCSE"; ...
%         "Legjobb AC - NPV"];
% 
%     shortLabels = [ ...
%         "Csak PV"; ...
%         "DC LCSE"; ...
%         "DC NPV"; ...
%         "AC LCSE"; ...
%         "AC NPV"];
% 
%     selectedTable.SelectionLabel = labels;
%     selectedTable = movevars(selectedTable, 'SelectionLabel', 'Before', 1);
% 
%     selected = struct();
%     selected.table = selectedTable;
%     selected.labels = labels;
%     selected.shortLabels = shortLabels;
% end
% 
% 
% function row = local_pick_best_row(T, mask, metricField, direction, excludedRow)
% 
%     if ~ismember(metricField, T.Properties.VariableNames)
%         error('Missing metric field for candidate selection: %s', metricField);
%     end
% 
%     valid = mask(:) & isfinite(T.(metricField));
% 
%     if ~isempty(excludedRow) && height(excludedRow) == 1
%         sameRow = T.Coupling == excludedRow.Coupling & ...
%             T.candidateIndex == excludedRow.candidateIndex;
% 
%         validWithExclusion = valid & ~sameRow;
% 
%         if any(validWithExclusion)
%             valid = validWithExclusion;
%         end
%     end
% 
%     if ~any(valid)
%         error('No valid candidate found for metric %s.', metricField);
%     end
% 
%     values = T.(metricField);
% 
%     switch string(direction)
%         case "min"
%             values(~valid) = inf;
%             [~, idx] = min(values);
%         case "max"
%             values(~valid) = -inf;
%             [~, idx] = max(values);
%         otherwise
%             error('Unknown direction: %s', string(direction));
%     end
% 
%     row = T(idx, :);
% end
% 
% 
% % =========================================================================
% % TABLES
% % =========================================================================
% function S = local_build_selected_summary_table(T, labels)
% 
%     S = table();
%     S.Selection = labels(:);
%     S.Coupling = T.Coupling;
%     S.candidateIndex = T.candidateIndex;
% 
%     S.P_inv_kW = T.P_inv_kW;
%     S.DCAC_ratio = T.DCAC_ratio;
%     S.BESS_PV_ratio_kWh_per_kWp = T.BESS_PV_ratio;
%     S.P_PV_kWp = T.P_PV_kW;
%     S.E_BESS_kWh = T.E_BESS_kWh;
%     S.P_BESS_kW = T.P_BESS_kW;
% 
%     S.Load_MWh_total = T.loadEnergy_kWh ./ 1000;
%     S.PV_available_MWh_total = T.pvEnergyAvailable_kWh ./ 1000;
%     S.PV_to_load_MWh_total = T.pvToLoad_kWh ./ 1000;
%     S.PV_to_BESS_MWh_total = T.pvToBess_kWh ./ 1000;
%     S.BESS_to_load_MWh_total = T.bessToLoad_kWh ./ 1000;
%     S.Grid_import_MWh_total = T.gridImport_kWh ./ 1000;
%     S.Curtailment_MWh_total = T.curtailment_kWh ./ 1000;
% 
%     S.Grid_import_reduction_pct = T.gridImportReduction_pct;
%     S.Self_consumption_pct = T.selfConsumption_pct;
%     S.Self_sufficiency_pct = T.selfSufficiency_pct;
%     S.Curtailment_pct = T.curtailment_pct;
%     S.Equivalent_cycles_per_year = T.annualBessEquivalentCycles;
%     S.Final_SoH = T.finalSoH;
% 
%     S.Initial_CAPEX_millionHUF = T.initialCapex_HUF ./ 1e6;
%     S.PV_CAPEX_millionHUF = T.capexPV_HUF ./ 1e6;
%     S.Inverter_CAPEX_millionHUF = T.capexInverter_HUF ./ 1e6;
%     S.BESS_CAPEX_millionHUF = T.capexBESS_HUF ./ 1e6;
% 
%     S.Period_energy_cost_saving_millionHUF = T.reportPeriodCostSaving_HUF ./ 1e6;
%     S.Period_PV_CAPEX_millionHUF = T.reportPeriodPVCapex_HUF ./ 1e6;
%     S.Period_PV_OPEX_millionHUF = T.reportPeriodPVOpex_HUF ./ 1e6;
%     S.Period_inverter_CAPEX_millionHUF = T.reportPeriodInverterCapex_HUF ./ 1e6;
%     S.Period_inverter_OPEX_millionHUF = T.reportPeriodInverterOpex_HUF ./ 1e6;
%     S.Period_BESS_degradation_CAPEX_millionHUF = T.reportPeriodBessDegradation_HUF ./ 1e6;
%     S.Period_BESS_OPEX_millionHUF = T.reportPeriodBessOpex_HUF ./ 1e6;
%     S.Period_net_value_millionHUF = T.reportPeriodNetValue_HUF ./ 1e6;
% 
%     S.BESS_AC_energy_saving_millionHUF = T.reportPeriodBessAcSaving_HUF ./ 1e6;
%     S.BESS_only_cost_millionHUF = T.reportPeriodBessOnlyCost_HUF ./ 1e6;
%     S.BESS_only_net_value_millionHUF = T.reportPeriodBessOnlyNetValue_HUF ./ 1e6;
% 
%     S.LCSE_HUF_per_kWh_saved = T.LCSE_HUF_per_kWh_saved;
%     S.NPV_millionHUF = T.NPV_millionHUF;
%     S.NPV_BESSOnly_millionHUF = T.NPV_BESSOnly_millionHUF;
%     S.Simple_payback_year = T.simplePayback_year;
%     S.Discounted_payback_year = T.discountedPayback_year;
% end
% 
% 
% function B = local_build_bess_only_table(T, labels)
% 
%     B = table();
%     B.Selection = labels(:);
%     B.Coupling = T.Coupling;
%     B.candidateIndex = T.candidateIndex;
%     B.E_BESS_kWh = T.E_BESS_kWh;
%     B.P_BESS_kW = T.P_BESS_kW;
%     B.BESS_to_load_MWh_total = T.bessToLoad_kWh ./ 1000;
%     B.BESS_AC_energy_saving_millionHUF = T.reportPeriodBessAcSaving_HUF ./ 1e6;
%     B.BESS_degradation_CAPEX_millionHUF = T.reportPeriodBessDegradation_HUF ./ 1e6;
%     B.BESS_OPEX_millionHUF = T.reportPeriodBessOpex_HUF ./ 1e6;
%     B.BESS_only_net_value_millionHUF = T.reportPeriodBessOnlyNetValue_HUF ./ 1e6;
% end
% 
% 
% % =========================================================================
% % PLOTS - 3D METRIC MAPS
% % =========================================================================
% function local_plot_3d_metric(T, metricField, metricLabel, metricUnit, direction, figureFolder, coupling)
% 
%     if ~ismember(metricField, T.Properties.VariableNames)
%         error('Missing metric field for 3D plot: %s', metricField);
%     end
% 
%     valid = ...
%         logical(T.wasSimulated) & ...
%         ~logical(T.hasError) & ...
%         isfinite(T.P_inv_kW) & ...
%         isfinite(T.DCAC_ratio) & ...
%         isfinite(T.BESS_PV_ratio) & ...
%         isfinite(T.(metricField));
% 
%     if ~any(valid)
%         error('No valid data for 3D plot: %s %s.', string(coupling), metricField);
%     end
% 
%     bestRow = local_pick_best_row(T, valid, metricField, direction, []);
% 
%     fig = figure('Name', sprintf('%s %s 3D map', upper(char(coupling)), metricField), ...
%         'Position', [80, 80, 1250, 850]);
% 
%     ax = axes(fig);
%     hold(ax, 'on');
%     grid(ax, 'on');
%     box(ax, 'on');
% 
%     scatter3(ax, ...
%         T.P_inv_kW(valid), ...
%         T.DCAC_ratio(valid), ...
%         T.BESS_PV_ratio(valid), ...
%         55, ...
%         T.(metricField)(valid), ...
%         'filled');
% 
%     plot3(ax, ...
%         bestRow.P_inv_kW, ...
%         bestRow.DCAC_ratio, ...
%         bestRow.BESS_PV_ratio, ...
%         'kp', ...
%         'MarkerSize', 18, ...
%         'MarkerFaceColor', 'w', ...
%         'LineWidth', 2.0);
% 
%     text(ax, ...
%         bestRow.P_inv_kW, ...
%         bestRow.DCAC_ratio, ...
%         bestRow.BESS_PV_ratio, ...
%         sprintf('  legjobb: C%d', bestRow.candidateIndex), ...
%         'FontWeight', 'bold', ...
%         'Interpreter', 'none');
% 
%     xlabel(ax, 'Inverter nevleges teljesitmeny [kW]');
%     ylabel(ax, 'DC/AC arany [-]');
%     zlabel(ax, 'BESS/PV arany [kWh/kWp]');
% 
%     title(ax, sprintf('%s-csatolt: %s', upper(char(coupling)), metricLabel), ...
%         'Interpreter', 'none');
% 
%     cb = colorbar(ax);
%     cb.Label.String = sprintf('%s [%s]', metricLabel, metricUnit);
% 
%     colormap(ax, local_green_yellow_red_colormap(direction, 256));
%     view(ax, 45, 25);
% 
%     local_save_figure(fig, figureFolder, sprintf('scatter3_%s_%s', char(coupling), metricField));
% end
% 
% 
% % =========================================================================
% % PLOTS - SELECTED CANDIDATES
% % =========================================================================
% function local_plot_value_cost_payback_summary(T, xLabels, figureFolder)
% 
%     fig = figure('Name', 'AC/DC selected value cost payback summary', ...
%         'Position', [50, 40, 1550, 1250]);
% 
%     tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
% 
%     x = 1:height(T);
% 
%     % ---------------------------------------------------------------------
%     % 1) Rendszer hozzaadott erteke a teljes szimulalt idoszakra
%     % ---------------------------------------------------------------------
%     ax1 = nexttile;
%     hold(ax1, 'on');
%     grid(ax1, 'on');
%     box(ax1, 'on');
% 
%     saving_mHUF = T.reportPeriodCostSaving_HUF ./ 1e6;
%     bar(ax1, x, saving_mHUF, 'BarWidth', 0.65);
%     yline(ax1, 0, 'k-', 'LineWidth', 1.0);
% 
%     ylabel(ax1, 'millio Ft');
%     title(ax1, 'Rendszer hozzaadott erteke - energiakoltseg-megtakaritas a szimulalt idoszakra');
%     xticks(ax1, x);
%     xticklabels(ax1, cellstr(xLabels));
% 
%     local_add_bar_value_labels(ax1, x, saving_mHUF);
% 
%     % ---------------------------------------------------------------------
%     % 2) Periodusra allokalt beruhazasi es OPEX komponensek
%     % ---------------------------------------------------------------------
%     ax2 = nexttile;
%     hold(ax2, 'on');
%     grid(ax2, 'on');
%     box(ax2, 'on');
% 
%     costData_mHUF = [ ...
%         T.reportPeriodPVCapex_HUF, ...
%         T.reportPeriodPVOpex_HUF, ...
%         T.reportPeriodInverterCapex_HUF, ...
%         T.reportPeriodInverterOpex_HUF, ...
%         T.reportPeriodBessDegradation_HUF, ...
%         T.reportPeriodBessOpex_HUF] ./ 1e6;
% 
%     bar(ax2, x, costData_mHUF, 'stacked', 'BarWidth', 0.65);
% 
%     ylabel(ax2, 'millio Ft');
%     title(ax2, 'Szimulalt idoszakra allokalt beruhazasi es uzemeltetesi koltsegek');
%     xticks(ax2, x);
%     xticklabels(ax2, cellstr(xLabels));
% 
%     legend(ax2, { ...
%         'PV CAPEX / lifetime', ...
%         'PV OPEX', ...
%         'Inverter CAPEX / lifetime', ...
%         'Inverter OPEX', ...
%         'BESS degradacios CAPEX', ...
%         'BESS OPEX'}, ...
%         'Location', 'bestoutside');
% 
%     % ---------------------------------------------------------------------
%     % 3) Netto periodusertek
%     % ---------------------------------------------------------------------
%     ax3 = nexttile;
%     hold(ax3, 'on');
%     grid(ax3, 'on');
%     box(ax3, 'on');
% 
%     periodNet_mHUF = T.reportPeriodNetValue_HUF ./ 1e6;
%     bar(ax3, x, periodNet_mHUF, 'BarWidth', 0.65);
%     yline(ax3, 0, 'k-', 'LineWidth', 1.0);
% 
%     ylabel(ax3, 'millio Ft');
%     title(ax3, 'Megterulesi ertek a szimulalt idoszakra - pozitiv ertek eseten gazdasagilag kedvezo');
%     xticks(ax3, x);
%     xticklabels(ax3, cellstr(xLabels));
% 
%     local_add_bar_value_labels(ax3, x, periodNet_mHUF);
% 
%     % ---------------------------------------------------------------------
%     % 4) BESS-only periodusertek
%     % ---------------------------------------------------------------------
%     ax4 = nexttile;
%     hold(ax4, 'on');
%     grid(ax4, 'on');
%     box(ax4, 'on');
% 
%     bessValueStack_mHUF = [ ...
%         T.reportPeriodBessAcSaving_HUF, ...
%         -T.reportPeriodBessDegradation_HUF, ...
%         -T.reportPeriodBessOpex_HUF] ./ 1e6;
% 
%     bar(ax4, x, bessValueStack_mHUF, 'stacked', 'BarWidth', 0.65);
% 
%     bessNet_mHUF = T.reportPeriodBessOnlyNetValue_HUF ./ 1e6;
% 
%     plot(ax4, x, bessNet_mHUF, 'k-o', ...
%         'LineWidth', 1.6, ...
%         'MarkerSize', 5, ...
%         'DisplayName', 'BESS-only netto ertek');
% 
%     yline(ax4, 0, 'k-', 'LineWidth', 1.0);
% 
%     ylabel(ax4, 'millio Ft');
%     title(ax4, 'BESS-only vizsgalat: BESS AC energiaertek - BESS degradacios CAPEX - BESS OPEX');
%     xticks(ax4, x);
%     xticklabels(ax4, cellstr(xLabels));
% 
%     legend(ax4, { ...
%         'BESS -> fogyaszto AC energia megtakaritasa', ...
%         'BESS degradacios CAPEX', ...
%         'BESS OPEX', ...
%         'BESS-only netto ertek'}, ...
%         'Location', 'bestoutside');
% 
%     local_add_bar_value_labels(ax4, x, bessNet_mHUF);
% 
%     local_save_figure(fig, figureFolder, 'acdc_selected_value_cost_payback_summary');
% end
% 
% 
% function local_plot_self_consumption_summary(T, xLabels, figureFolder)
% 
%     fig = figure('Name', 'AC/DC selected technical summary', ...
%         'Position', [80, 80, 1400, 900]);
% 
%     tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
% 
%     x = 1:height(T);
% 
%     metrics = { ...
%         'selfConsumption_pct', 'Onfogyasztasi arany', '%'; ...
%         'selfSufficiency_pct', 'Onellatasi arany', '%'; ...
%         'annualBessEquivalentCycles', 'Eves ekvivalens BESS ciklusszam', 'ciklus/ev'};
% 
%     for k = 1:size(metrics, 1)
%         ax = nexttile;
%         hold(ax, 'on');
%         grid(ax, 'on');
%         box(ax, 'on');
% 
%         fieldName = metrics{k, 1};
%         values = T.(fieldName);
% 
%         bar(ax, x, values, 'BarWidth', 0.65);
%         ylabel(ax, metrics{k, 3});
%         title(ax, metrics{k, 2});
%         xticks(ax, x);
%         xticklabels(ax, cellstr(xLabels));
% 
%         local_add_bar_value_labels(ax, x, values);
%     end
% 
%     local_save_figure(fig, figureFolder, 'acdc_selected_self_consumption_summary');
% end
% 
% 
% function local_plot_useful_energy_and_losses(T, xLabels, figureFolder)
% 
%     fig = figure('Name', 'AC/DC selected useful AC energy and losses', ...
%         'Position', [100, 90, 1500, 800]);
% 
%     ax = axes(fig);
%     hold(ax, 'on');
%     grid(ax, 'on');
%     box(ax, 'on');
% 
%     x = 1:height(T);
% 
%     energyData_MWh = [ ...
%         T.reportUsefulACEnergy_MWh, ...
%         T.reportInverterLoss_MWh, ...
%         T.reportDcdcLoss_MWh, ...
%         T.reportBessInternalLoss_MWh, ...
%         T.reportCurtailment_MWh];
% 
%     bar(ax, x, energyData_MWh, 'stacked', 'BarWidth', 0.65);
% 
%     ylabel(ax, 'MWh / szimulalt idoszak');
%     title(ax, 'Hasznos AC energia es fo vesztesegkomponensek');
%     xticks(ax, x);
%     xticklabels(ax, cellstr(xLabels));
% 
%     legend(ax, { ...
%         'Hasznos AC energia a fogyaszton', ...
%         'Inverter veszteseg', ...
%         'DC/DC veszteseg', ...
%         'BESS cella/belso veszteseg', ...
%         'Curtailment'}, ...
%         'Location', 'bestoutside');
% 
%     local_save_figure(fig, figureFolder, 'acdc_selected_useful_energy_and_losses');
% end
% 
% 
% % =========================================================================
% % PLOT HELPERS
% % =========================================================================
% function local_add_bar_value_labels(ax, x, values)
% 
%     for i = 1:numel(values)
%         if ~isfinite(values(i))
%             continue;
%         end
% 
%         if values(i) >= 0
%             vAlign = 'bottom';
%         else
%             vAlign = 'top';
%         end
% 
%         text(ax, x(i), values(i), ...
%             ['  ', char(local_format_number(values(i)))], ...
%             'HorizontalAlignment', 'center', ...
%             'VerticalAlignment', vAlign, ...
%             'FontSize', 8);
%     end
% end
% 
% 
% function cmap = local_green_yellow_red_colormap(direction, n)
% 
%     if nargin < 2
%         n = 256;
%     end
% 
%     red = [0.85, 0.15, 0.15];
%     yellow = [1.00, 0.90, 0.15];
%     green = [0.15, 0.70, 0.25];
% 
%     n1 = floor(n / 2);
%     n2 = n - n1;
% 
%     switch string(direction)
%         case "max"
%             c1 = local_interp_color(red, yellow, n1);
%             c2 = local_interp_color(yellow, green, n2);
%         case "min"
%             c1 = local_interp_color(green, yellow, n1);
%             c2 = local_interp_color(yellow, red, n2);
%         otherwise
%             error('Unknown direction: %s', string(direction));
%     end
% 
%     cmap = [c1; c2];
% end
% 
% 
% function C = local_interp_color(cStart, cEnd, n)
% 
%     t = linspace(0, 1, n).';
%     C = (1 - t) .* cStart + t .* cEnd;
% end
% 
% 
% function s = local_format_number(x)
% 
%     if ~isfinite(x)
%         if isinf(x)
%             s = "Inf";
%         else
%             s = "NaN";
%         end
%         return;
%     end
% 
%     ax = abs(x);
% 
%     if ax >= 1000
%         s = string(sprintf('%.0f', x));
%     elseif ax >= 100
%         s = string(sprintf('%.1f', x));
%     elseif ax >= 10
%         s = string(sprintf('%.1f', x));
%     elseif ax >= 1
%         s = string(sprintf('%.2f', x));
%     else
%         s = string(sprintf('%.3f', x));
%     end
% end
% 
% 
% function local_save_figure(fig, figureFolder, fileName)
% 
%     if ~exist(figureFolder, 'dir')
%         mkdir(figureFolder);
%     end
% 
%     savefig(fig, fullfile(figureFolder, [fileName, '.fig']));
% 
%     try
%         exportgraphics(fig, fullfile(figureFolder, [fileName, '.png']), 'Resolution', 150);
%     catch
%         saveas(fig, fullfile(figureFolder, [fileName, '.png']));
%     end
% end

function acdcEvaluation = evaluation_acdc_summary(cfg, options)
% EVALUATION_ACDC_SUMMARY
%
% AC/DC-csatolt PV+BESS kiértékelő hőtérképes összefoglaló.
%
% Ez a függvény nem számolja újra az NPV-t.
% A meglévő evaluation.m által előállított resultTable mezőket használja.
%
% Ábrázolt metrikák:
%   1) Teljes rendszer nettó jelenértéke (NPV)
%   2) Akkumulátor hozzáadott értékének nettó jelenértéke
%
% Nem készül nettó megtakarítás hőtérkép.
%
% Az ábrákon becsillagozva jelennek meg azok a jelöltek, amelyek
% a summary táblázatban is szerepelnek:
%   - sima napelemes rendszer
%   - legjobb DC-csatolt PV+BESS rendszer
%   - legjobb AC-csatolt PV+BESS rendszer

    if nargin < 2 || isempty(options)
        options = struct();
    end

    options = local_fill_default_options(options);

    if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'results')
        error('cfg.paths.results hianyzik.');
    end

    if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'figures')
        error('cfg.paths.figures hianyzik.');
    end

    fprintf('\n============================================================\n');
    fprintf('AC/DC EVALUATION SUMMARY - NPV HEATMAPS ONLY\n');
    fprintf('============================================================\n');

    [dcEval, dcTable] = local_run_single_coupling_evaluation(cfg, "dc", options);
    [acEval, acTable] = local_run_single_coupling_evaluation(cfg, "ac", options);

    dcTable = local_add_report_columns(dcTable, dcEval.evalCfg, "dc");
    acTable = local_add_report_columns(acTable, acEval.evalCfg, "ac");

    combinedTable = local_append_table_union(dcTable, acTable);

    outputRoot = fullfile(cfg.paths.figures, 'evaluation', 'acdc_summary_heatmaps');
    figureFolder = fullfile(outputRoot, 'figures');
    tableFolder = fullfile(outputRoot, 'tables');

    local_ensure_folder(outputRoot);
    local_ensure_folder(figureFolder);
    local_ensure_folder(tableFolder);

    writetable(dcTable, fullfile(tableFolder, 'dc_result_table.csv'));
    writetable(acTable, fullfile(tableFolder, 'ac_result_table.csv'));
    writetable(combinedTable, fullfile(tableFolder, 'combined_result_table.csv'));

    metricSpecs = local_metric_specs();

    summarySelection = local_select_summary_systems(combinedTable);
    plotMarkers = local_build_plot_markers(dcTable, acTable, combinedTable, summarySelection);

    summaryMarkerTable = local_build_summary_marker_table(combinedTable, summarySelection);
    writetable(summaryMarkerTable, fullfile(tableFolder, 'summary_marker_table.csv'));

    figureHandles = local_plot_npv_heatmap_family( ...
        dcTable, ...
        acTable, ...
        metricSpecs, ...
        plotMarkers, ...
        options, ...
        figureFolder);

    acdcEvaluation = struct();
    acdcEvaluation.createdAt = datetime('now');

    acdcEvaluation.outputRoot = outputRoot;
    acdcEvaluation.figureFolder = figureFolder;
    acdcEvaluation.tableFolder = tableFolder;

    acdcEvaluation.dcEvaluation = dcEval;
    acdcEvaluation.acEvaluation = acEval;

    acdcEvaluation.dcTable = dcTable;
    acdcEvaluation.acTable = acTable;
    acdcEvaluation.combinedTable = combinedTable;

    acdcEvaluation.metricSpecs = metricSpecs;
    acdcEvaluation.summarySelection = summarySelection;
    acdcEvaluation.summaryMarkerTable = summaryMarkerTable;
    acdcEvaluation.plotMarkers = plotMarkers;
    acdcEvaluation.figureHandles = figureHandles;
    acdcEvaluation.options = options;

    save(fullfile(outputRoot, 'acdc_evaluation_summary.mat'), ...
        'acdcEvaluation', ...
        '-v7.3');

    fprintf('\nAC/DC NPV heatmap summary finished.\n');
    fprintf('Output folder: %s\n', outputRoot);
    fprintf('============================================================\n');
end


% =========================================================================
% OPTIONS
% =========================================================================
function options = local_fill_default_options(options)

    if ~isfield(options, 'colorLimits_millionHUF') || isempty(options.colorLimits_millionHUF)
        options.colorLimits_millionHUF = [0, 400];
    end

    if numel(options.colorLimits_millionHUF) ~= 2 || ...
       any(~isfinite(options.colorLimits_millionHUF)) || ...
       options.colorLimits_millionHUF(2) <= options.colorLimits_millionHUF(1)

        error('options.colorLimits_millionHUF must be [min, max] with finite values.');
    end

    if ~isfield(options, 'evaluationSelectionMode') || strlength(string(options.evaluationSelectionMode)) == 0
        options.evaluationSelectionMode = "maxNPV";
    else
        options.evaluationSelectionMode = string(options.evaluationSelectionMode);
    end
end


% =========================================================================
% EVALUATION FUTTATAS
% =========================================================================
function [evaluationResult, resultTable] = local_run_single_coupling_evaluation(cfg, couplingLabel, options)

    cfgEval = cfg;
    cfgEval.system.bessCoupling = string(couplingLabel);

    evalCfg = create_evaluation_config(cfgEval);

    switch string(couplingLabel)

        case "dc"
            evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_dccoupled.mat');
            evalCfg.output.baseFolder = fullfile(cfg.paths.figures, 'evaluation', 'dc');

        case "ac"
            evalCfg.input.resultFilePath = fullfile(cfg.paths.results, 'results_accoupled.mat');
            evalCfg.output.baseFolder = fullfile(cfg.paths.figures, 'evaluation', 'ac');

        otherwise
            error('Ismeretlen couplingLabel: %s', string(couplingLabel));
    end

    if ~isfile(evalCfg.input.resultFilePath)
        error('Nem talalhato %s eredmenyfajl: %s', ...
            upper(string(couplingLabel)), evalCfg.input.resultFilePath);
    end

    evalCfg.selection.mode = options.evaluationSelectionMode;

    if isfield(evalCfg, 'plots') && isfield(evalCfg.plots, 'makePlots')
        evalCfg.plots.makePlots = false;
    end

    fprintf('\nRunning existing evaluation.m for %s-coupled results...\n', upper(string(couplingLabel)));
    fprintf('Input file: %s\n', evalCfg.input.resultFilePath);

    evaluationResult = evaluation(cfgEval, evalCfg);

    if ~isfield(evaluationResult, 'resultTable')
        error('evaluationResult.resultTable hianyzik a(z) %s-csatolt esetben.', upper(string(couplingLabel)));
    end

    if ~isfield(evaluationResult, 'evalCfg')
        evaluationResult.evalCfg = evalCfg;
    end

    resultTable = evaluationResult.resultTable;

    if isempty(resultTable) || height(resultTable) == 0
        error('evaluationResult.resultTable ures a(z) %s-csatolt esetben.', upper(string(couplingLabel)));
    end
end


% =========================================================================
% RESULT TABLE KIEGESZITES
% =========================================================================
function T = local_add_report_columns(T, evalCfg, couplingLabel)

    if ~ismember('DCAC_ratio', T.Properties.VariableNames)
        if ismember('dcac_ratio', T.Properties.VariableNames)
            T.DCAC_ratio = T.dcac_ratio;
        else
            T.DCAC_ratio = T.P_PV_kW ./ T.P_inv_kW;
        end
    end

    if ~ismember('NPV_millionHUF', T.Properties.VariableNames) && ...
            ismember('NPV_HUF', T.Properties.VariableNames)

        T.NPV_millionHUF = T.NPV_HUF ./ 1e6;
    end

    if ~ismember('NPV_BESSOnly_millionHUF', T.Properties.VariableNames) && ...
            ismember('NPV_BESSOnly_HUF', T.Properties.VariableNames)

        T.NPV_BESSOnly_millionHUF = T.NPV_BESSOnly_HUF ./ 1e6;
    end

    if ~ismember('annualBessEquivalentCycles', T.Properties.VariableNames) && ...
            ismember('bessEquivalentCycles', T.Properties.VariableNames)

        simYears = evalCfg.economics.simYears;
        T.annualBessEquivalentCycles = T.bessEquivalentCycles ./ simYears;
    end

    T.coupling = repmat(string(couplingLabel), height(T), 1);

    requiredMetrics = { ...
        'NPV_millionHUF', ...
        'NPV_BESSOnly_millionHUF'};

    for k = 1:numel(requiredMetrics)
        if ~ismember(requiredMetrics{k}, T.Properties.VariableNames)
            error('A resultTable nem tartalmazza a szukseges mezot: %s', requiredMetrics{k});
        end
    end
end


% =========================================================================
% ABRAZOLT METRIKAK
% =========================================================================
function metricSpecs = local_metric_specs()
% Csak NPV-hőtérképek. Nettó megtakarítási ábra nincs.

    metricSpecs = struct( ...
        'field', { ...
            'NPV_millionHUF', ...
            'NPV_BESSOnly_millionHUF'}, ...
        'title', { ...
            'Teljes rendszer nettó jelenértéke', ...
            'Akkumulátor hozzáadott értékének nettó jelenértéke'}, ...
        'shortTitle', { ...
            'Teljes rendszer NPV', ...
            'BESS hozzáadott érték NPV'}, ...
        'unit', { ...
            'millió Ft', ...
            'millió Ft'}, ...
        'fileTag', { ...
            'npv_teljes_rendszer', ...
            'npv_bess_hozzaadott_ertek'});
end


% =========================================================================
% SUMMARY JELÖLTEK KIVÁLASZTÁSA
% =========================================================================
function selection = local_select_summary_systems(T)

    valid = ...
        logical(T.wasSimulated) & ...
        ~logical(T.hasError) & ...
        isfinite(T.NPV_millionHUF);

    pvOnlyMask = ...
        valid & ...
        T.E_BESS_kWh <= 1e-9;

    dcMask = ...
        valid & ...
        lower(string(T.coupling)) == "dc" & ...
        T.E_BESS_kWh > 1e-9;

    acMask = ...
        valid & ...
        lower(string(T.coupling)) == "ac" & ...
        T.E_BESS_kWh > 1e-9;

    selection = struct();

    selection.pvOnlyIndex = local_pick_best_index(T.NPV_millionHUF, pvOnlyMask, "max");
    selection.bestDcIndex = local_pick_best_index(T.NPV_millionHUF, dcMask, "max");
    selection.bestAcIndex = local_pick_best_index(T.NPV_millionHUF, acMask, "max");

    selection.metric = "NPV_millionHUF";
end


function idx = local_pick_best_index(values, mask, direction)

    values = double(values(:));
    mask = logical(mask(:));

    valid = mask & isfinite(values);

    if ~any(valid)
        error('Nincs megfelelo candidate a summary jeloltek kivalasztasahoz.');
    end

    switch string(direction)

        case "max"
            tmp = values;
            tmp(~valid) = -inf;
            [~, idx] = max(tmp);

        case "min"
            tmp = values;
            tmp(~valid) = inf;
            [~, idx] = min(tmp);

        otherwise
            error('Ismeretlen direction: %s', string(direction));
    end
end


function summaryMarkerTable = local_build_summary_marker_table(T, selection)

    rows = [ ...
        selection.pvOnlyIndex; ...
        selection.bestDcIndex; ...
        selection.bestAcIndex];

    names = [ ...
        "Sima napelemes rendszer"; ...
        "Legjobb DC-csatolt PV+BESS"; ...
        "Legjobb AC-csatolt PV+BESS"];

    summaryMarkerTable = table();

    summaryMarkerTable.markerName = names;
    summaryMarkerTable.rowIndex = rows;
    summaryMarkerTable.coupling = string(T.coupling(rows));
    summaryMarkerTable.candidateIndex = T.candidateIndex(rows);
    summaryMarkerTable.P_inv_kW = T.P_inv_kW(rows);
    summaryMarkerTable.P_PV_kW = T.P_PV_kW(rows);
    summaryMarkerTable.DCAC_ratio = T.DCAC_ratio(rows);
    summaryMarkerTable.BESS_PV_ratio = T.BESS_PV_ratio(rows);
    summaryMarkerTable.E_BESS_kWh = T.E_BESS_kWh(rows);
    summaryMarkerTable.NPV_millionHUF = T.NPV_millionHUF(rows);

    if ismember('NPV_BESSOnly_millionHUF', T.Properties.VariableNames)
        summaryMarkerTable.NPV_BESSOnly_millionHUF = T.NPV_BESSOnly_millionHUF(rows);
    end
end


% =========================================================================
% PLOT MARKEREK
% =========================================================================
function plotMarkers = local_build_plot_markers(dcTable, acTable, combinedTable, selection)

    plotMarkers = struct();
    plotMarkers.dc = local_empty_marker_array();
    plotMarkers.ac = local_empty_marker_array();

    pvRow = combinedTable(selection.pvOnlyIndex, :);
    dcRow = combinedTable(selection.bestDcIndex, :);
    acRow = combinedTable(selection.bestAcIndex, :);

    % A sima napelemes rendszer architekturafuggetlen baseline.
    % Ezert mind a DC, mind az AC ábrán megjelöljük, ha van megfelelő sor.
    idxPvDc = local_find_matching_row(dcTable, pvRow);
    if ~isnan(idxPvDc)
        plotMarkers.dc(end+1) = local_create_marker(dcTable(idxPvDc, :), ...
            "PV", ...
            "Sima napelemes rendszer", ...
            "pvOnly");
    end

    idxPvAc = local_find_matching_row(acTable, pvRow);
    if ~isnan(idxPvAc)
        plotMarkers.ac(end+1) = local_create_marker(acTable(idxPvAc, :), ...
            "PV", ...
            "Sima napelemes rendszer", ...
            "pvOnly");
    end

    idxDc = local_find_matching_row(dcTable, dcRow);
    if ~isnan(idxDc)
        plotMarkers.dc(end+1) = local_create_marker(dcTable(idxDc, :), ...
            "DC", ...
            "Legjobb DC-csatolt PV+BESS", ...
            "bestDc");
    end

    idxAc = local_find_matching_row(acTable, acRow);
    if ~isnan(idxAc)
        plotMarkers.ac(end+1) = local_create_marker(acTable(idxAc, :), ...
            "AC", ...
            "Legjobb AC-csatolt PV+BESS", ...
            "bestAc");
    end
end


function markers = local_empty_marker_array()

    markers = struct( ...
        'enabled', {}, ...
        'label', {}, ...
        'description', {}, ...
        'type', {}, ...
        'P_inv_kW', {}, ...
        'P_PV_kW', {}, ...
        'DCAC_ratio', {}, ...
        'BESS_PV_ratio', {}, ...
        'E_BESS_kWh', {}, ...
        'candidateIndex', {}, ...
        'NPV_millionHUF', {}, ...
        'NPV_BESSOnly_millionHUF', {});
end


function marker = local_create_marker(row, label, description, markerType)

    marker = struct();

    marker.enabled = true;
    marker.label = string(label);
    marker.description = string(description);
    marker.type = string(markerType);

    marker.P_inv_kW = row.P_inv_kW(1);
    marker.P_PV_kW = row.P_PV_kW(1);
    marker.DCAC_ratio = row.DCAC_ratio(1);
    marker.BESS_PV_ratio = row.BESS_PV_ratio(1);
    marker.E_BESS_kWh = row.E_BESS_kWh(1);
    marker.candidateIndex = row.candidateIndex(1);

    marker.NPV_millionHUF = row.NPV_millionHUF(1);

    if ismember('NPV_BESSOnly_millionHUF', row.Properties.VariableNames)
        marker.NPV_BESSOnly_millionHUF = row.NPV_BESSOnly_millionHUF(1);
    else
        marker.NPV_BESSOnly_millionHUF = NaN;
    end
end


function idx = local_find_matching_row(T, row)

    if isempty(T) || height(T) == 0
        idx = NaN;
        return;
    end

    mask = ...
        abs(T.P_inv_kW - row.P_inv_kW(1)) <= 1e-6 & ...
        abs(T.P_PV_kW - row.P_PV_kW(1)) <= 1e-6 & ...
        abs(T.E_BESS_kWh - row.E_BESS_kWh(1)) <= 1e-6 & ...
        abs(T.BESS_PV_ratio - row.BESS_PV_ratio(1)) <= 1e-9 & ...
        abs(T.DCAC_ratio - row.DCAC_ratio(1)) <= 1e-9;

    rows = find(mask);

    if isempty(rows)
        idx = NaN;
    else
        idx = rows(1);
    end
end


% =========================================================================
% NPV HEATMAP PLOTTING
% =========================================================================
function figureHandles = local_plot_npv_heatmap_family( ...
    dcTable, acTable, metricSpecs, plotMarkers, options, figureFolder)

    figureHandles = struct();

    for m = 1:numel(metricSpecs)

        metricField = char(metricSpecs(m).field);

        localInvValuesDC = sort(unique(dcTable.P_inv_kW(isfinite(dcTable.P_inv_kW))));
        localInvValuesAC = sort(unique(acTable.P_inv_kW(isfinite(acTable.P_inv_kW))));

        for i = 1:numel(localInvValuesDC)

            invValue = localInvValuesDC(i);

            figDC = local_plot_single_coupling_single_inverter_heatmap( ...
                dcTable, ...
                metricSpecs(m), ...
                "dc", ...
                invValue, ...
                plotMarkers.dc, ...
                options, ...
                figureFolder);

            fieldName = sprintf('%s_dc_inv_%s', ...
                metricField, ...
                local_number_to_tag(invValue));

            fieldName = matlab.lang.makeValidName(fieldName);
            figureHandles.(fieldName) = figDC;
        end

        for i = 1:numel(localInvValuesAC)

            invValue = localInvValuesAC(i);

            figAC = local_plot_single_coupling_single_inverter_heatmap( ...
                acTable, ...
                metricSpecs(m), ...
                "ac", ...
                invValue, ...
                plotMarkers.ac, ...
                options, ...
                figureFolder);

            fieldName = sprintf('%s_ac_inv_%s', ...
                metricField, ...
                local_number_to_tag(invValue));

            fieldName = matlab.lang.makeValidName(fieldName);
            figureHandles.(fieldName) = figAC;
        end
    end
end


function fig = local_plot_single_coupling_single_inverter_heatmap( ...
    T, metricSpec, couplingLabel, invValue, markers, options, figureFolder)

    metricField = char(metricSpec.field);

    if ~ismember(metricField, T.Properties.VariableNames)
        error('A resultTable nem tartalmazza ezt a metrikat: %s', metricField);
    end

    invTag = ['inverter_', local_number_to_tag(invValue)];

    Tsub = T(abs(T.P_inv_kW - invValue) <= 1e-6, :);

    % ---------------------------------------------------------------------
    % FONTOS JAVITAS:
    % Csak azok a markerek mehetnek erre az abrara, amelyek tenylegesen
    % ehhez az invertermerethez tartoznak.
    % Igy a tablazatban szereplo jeloltek csak a sajat inverteres abrain
    % lesznek becsillagozva.
    % ---------------------------------------------------------------------
    markersForThisInverter = local_filter_markers_for_inverter(markers, invValue);

    figName = sprintf('heatmap %s %s - %s', ...
        lower(char(couplingLabel)), ...
        invTag, ...
        metricField);

    fig = figure( ...
        'Name', figName, ...
        'Color', 'w', ...
        'Position', [100, 80, 1050, 850]);

    ax = axes(fig);

    titleSuffix = sprintf('Inverter nevleges teljesitmenye: %.0f kW', invValue);

    local_plot_one_heatmap_axis( ...
        ax, ...
        Tsub, ...
        metricSpec, ...
        local_coupling_title(couplingLabel), ...
        titleSuffix, ...
        markersForThisInverter, ...
        options);

    fileName = sprintf('heatmap_%s_%s_%s', ...
        lower(char(couplingLabel)), ...
        char(metricSpec.fileTag), ...
        invTag);

    local_save_figure(fig, figureFolder, fileName);
end

function local_plot_one_heatmap_axis(ax, T, metricSpec, couplingTitle, titleSuffix, markers, options)

    metricField = char(metricSpec.field);
    colorLimits = options.colorLimits_millionHUF;

    if isempty(T) || height(T) == 0
        axis(ax, 'off');
        title(ax, sprintf('%s - nincs adat', couplingTitle), 'FontWeight', 'bold');
        return;
    end

    validMask = ...
        isfinite(T.DCAC_ratio) & ...
        isfinite(T.BESS_PV_ratio) & ...
        isfinite(T.(metricField)) & ...
        logical(T.wasSimulated) & ...
        ~logical(T.hasError);

    Tv = T(validMask, :);

    if isempty(Tv) || height(Tv) == 0
        axis(ax, 'off');
        title(ax, sprintf('%s - nincs véges adat', couplingTitle), 'FontWeight', 'bold');
        return;
    end

    xVals = unique(Tv.DCAC_ratio);
    yVals = unique(Tv.BESS_PV_ratio);

    xVals = sort(xVals(:).');
    yVals = sort(yVals(:));

    Z = NaN(numel(yVals), numel(xVals));

    for i = 1:height(Tv)

        ix = find(abs(xVals - Tv.DCAC_ratio(i)) <= 1e-9, 1, 'first');
        iy = find(abs(yVals - Tv.BESS_PV_ratio(i)) <= 1e-9, 1, 'first');

        if isempty(ix) || isempty(iy)
            continue;
        end

        Z(iy, ix) = Tv.(metricField)(i);
    end

    imagesc(ax, xVals, yVals, Z);

    set(ax, 'YDir', 'normal');
    set(ax, 'Color', [0.94, 0.94, 0.94]);

    colormap(ax, local_red_yellow_green_colormap(256));

    % Fix 0...400 millio Ft szintartomany.
    % A cellafeliratban tovabbra is a valos ertek latszik.
    caxis(ax, colorLimits);

    cb = colorbar(ax);
    cb.Label.String = sprintf('%s [%s]', metricSpec.shortTitle, metricSpec.unit);
    cb.Label.FontSize = 11;

    title(ax, { ...
        sprintf('%s - %s', couplingTitle, metricSpec.title), ...
        titleSuffix}, ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    xlabel(ax, 'DC/AC arány [-]', 'FontSize', 12);
    ylabel(ax, 'BESS/PV arány [kWh/kWp]', 'FontSize', 12);

    set(ax, ...
        'FontSize', 11, ...
        'LineWidth', 1.0, ...
        'TickDir', 'out', ...
        'Layer', 'top', ...
        'Box', 'on');

    xlim(ax, local_axis_limits_from_values(xVals));
    ylim(ax, local_axis_limits_from_values(yVals));

    local_apply_sparse_ticks(ax, xVals, yVals);
    local_draw_cell_grid(ax, xVals, yVals);
    local_add_cell_value_labels(ax, xVals, yVals, Z, colorLimits);
    local_draw_summary_markers(ax, xVals, yVals, markers, metricField, colorLimits);
end


function local_draw_summary_markers(ax, xVals, yVals, markers, metricField, colorLimits)

    if isempty(markers)
        return;
    end

    for i = 1:numel(markers)

        marker = markers(i);

        if ~marker.enabled
            continue;
        end

        if string(metricField) == "NPV_BESSOnly_millionHUF" && marker.E_BESS_kWh <= 1e-9
            continue;
        end

        ix = find(abs(xVals - marker.DCAC_ratio) <= 1e-9, 1, 'first');
        iy = find(abs(yVals - marker.BESS_PV_ratio) <= 1e-9, 1, 'first');

        if isempty(ix) || isempty(iy)
            continue;
        end

        x = xVals(ix);
        y = yVals(iy);

        xOffset = local_marker_x_offset(xVals);
        yOffset = local_marker_y_offset(yVals);

        switch string(metricField)
            case "NPV_millionHUF"
                markerValue = marker.NPV_millionHUF;
            case "NPV_BESSOnly_millionHUF"
                markerValue = marker.NPV_BESSOnly_millionHUF;
            otherwise
                markerValue = marker.NPV_millionHUF;
        end

        markerColor = local_choose_label_color(markerValue, colorLimits);

        text(ax, x + xOffset, y + yOffset, '*', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 28, ...
            'FontWeight', 'bold', ...
            'Color', markerColor, ...
            'Clipping', 'on');

        text(ax, x + 1.8 * xOffset, y + yOffset, char(marker.label), ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 9, ...
            'FontWeight', 'bold', ...
            'Color', markerColor, ...
            'Clipping', 'on');
    end
end


function titleText = local_coupling_title(couplingLabel)

    switch lower(string(couplingLabel))

        case "dc"
            titleText = "DC-csatolt rendszer";

        case "ac"
            titleText = "AC-csatolt rendszer";

        otherwise
            titleText = upper(string(couplingLabel)) + "-csatolt rendszer";
    end
end


% =========================================================================
% TABLA OSSZEFUZES
% =========================================================================
function out = local_append_table_union(A, B)

    if isempty(A) || height(A) == 0
        out = B;
        return;
    end

    if isempty(B) || height(B) == 0
        out = A;
        return;
    end

    varsA = string(A.Properties.VariableNames);
    varsB = string(B.Properties.VariableNames);

    allVars = unique([varsA(:); varsB(:)], 'stable');

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


% =========================================================================
% HEATMAP RAJZOLASI HELPEREK
% =========================================================================
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

    nCells = numel(xVals) * numel(yVals);

    if nCells <= 60
        fontSize = 10;
    elseif nCells <= 120
        fontSize = 8;
    else
        fontSize = 6;
    end

    for iy = 1:numel(yVals)
        for ix = 1:numel(xVals)

            value = Z(iy, ix);

            if ~isfinite(value)
                continue;
            end

            text(ax, xVals(ix), yVals(iy), local_format_heatmap_value(value), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', fontSize, ...
                'FontWeight', 'bold', ...
                'Color', local_choose_label_color(value, colorLimits), ...
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


function color = local_choose_label_color(value, colorLimits)

    if ~isfinite(value)
        color = [1, 1, 1];
        return;
    end

    t = (value - colorLimits(1)) ./ max(colorLimits(2) - colorLimits(1), eps);
    t = max(0, min(1, t));

    if t > 0.35 && t < 0.75
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
            'LineWidth', 0.45, ...
            'HandleVisibility', 'off');
    end

    for i = 1:numel(yEdges)
        line(ax, [xEdges(1), xEdges(end)], [yEdges(i), yEdges(i)], ...
            'Color', [1, 1, 1], ...
            'LineWidth', 0.45, ...
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
        offset = 0.08;
        return;
    end

    dy = min(diff(sort(yVals)));
    offset = 0.12 * dy;
end


function local_save_figure(fig, folderPath, fileName)

    local_ensure_folder(folderPath);

    savefig(fig, fullfile(folderPath, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(folderPath, [fileName, '.png']), 'Resolution', 300);
    catch
        saveas(fig, fullfile(folderPath, [fileName, '.png']));
    end

    try
        exportgraphics(fig, fullfile(folderPath, [fileName, '.pdf']), 'ContentType', 'vector');
    catch
    end
end


function local_ensure_folder(folderPath)

    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end
end


function tag = local_number_to_tag(value)

    tag = sprintf('%.4f', value);
    tag = strrep(tag, '-', 'm');
    tag = strrep(tag, '.', 'p');
end

function filteredMarkers = local_filter_markers_for_inverter(markers, invValue)

    filteredMarkers = local_empty_marker_array();

    if isempty(markers)
        return;
    end

    for i = 1:numel(markers)

        marker = markers(i);

        if ~marker.enabled
            continue;
        end

        if abs(marker.P_inv_kW - invValue) <= 1e-6
            filteredMarkers(end+1) = marker; %#ok<AGROW>
        end
    end
end