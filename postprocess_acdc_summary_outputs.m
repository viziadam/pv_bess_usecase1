function acdcResult = postprocess_acdc_summary_outputs(acdcResult, cfg)
% POSTPROCESS_ACDC_SUMMARY_OUTPUTS
%
% Letrehoz egy jol elerheto, szep osszefoglalo tablazatot:
%   1) sima napelemes rendszer
%   2) legjobb DC-csatolt PV+BESS rendszer
%   3) legjobb AC-csatolt PV+BESS rendszer
%
% A fuggveny nem szamolja ujra a gazdasagi mutatokat.
% Csak az evaluation_acdc_summary / evaluation altal mar eloallitott
% resultTable mezokbol dolgozik.

    if nargin < 2
        error('Hasznalat: acdcResult = postprocess_acdc_summary_outputs(acdcResult, cfg)');
    end

    if ~isstruct(acdcResult)
        error('acdcResult must be a struct.');
    end

    if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'figures')
        error('cfg.paths.figures hianyzik.');
    end

    acdcResult = local_ensure_combined_table(acdcResult);

    T = acdcResult.combinedTable;

    if isempty(T) || height(T) == 0
        error('acdcResult.combinedTable ures.');
    end

    T = local_ensure_required_columns(T);

    outputRoot = fullfile(cfg.paths.figures, 'evaluation', 'acdc_summary_best_systems');

    if ~exist(outputRoot, 'dir')
        mkdir(outputRoot);
    end

    selection = local_select_summary_systems(T);

    summaryTable = local_create_best_systems_summary_table(T, selection);

    writetable(summaryTable, fullfile(outputRoot, 'best_systems_summary.csv'));

    save(fullfile(outputRoot, 'best_systems_summary.mat'), ...
        'summaryTable', ...
        'selection', ...
        '-v7.3');

    local_plot_best_systems_summary_table( ...
        summaryTable, ...
        outputRoot, ...
        'best_systems_summary');

    local_write_best_systems_summary_html( ...
        summaryTable, ...
        outputRoot, ...
        'best_systems_summary');

    acdcResult.bestSystemsSummary = struct();
    acdcResult.bestSystemsSummary.outputRoot = outputRoot;
    acdcResult.bestSystemsSummary.selection = selection;
    acdcResult.bestSystemsSummary.summaryTable = summaryTable;

    fprintf('\nBest systems summary table created.\n');
    fprintf('Output folder: %s\n', outputRoot);
end


% =========================================================================
% COMBINED TABLE
% =========================================================================
function acdcResult = local_ensure_combined_table(acdcResult)

    if isfield(acdcResult, 'combinedTable') && ...
            istable(acdcResult.combinedTable) && ...
            height(acdcResult.combinedTable) > 0

        return;
    end

    if isfield(acdcResult, 'dcTable') && isfield(acdcResult, 'acTable')
        acdcResult.combinedTable = local_append_table_union( ...
            acdcResult.dcTable, ...
            acdcResult.acTable);
        return;
    end

    error('acdcResult.combinedTable is missing, and dcTable/acTable are also missing.');
end


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
% COLUMN NORMALIZATION
% =========================================================================
function T = local_ensure_required_columns(T)

    if ~ismember('DCAC_ratio', T.Properties.VariableNames)
        if ismember('dcac_ratio', T.Properties.VariableNames)
            T.DCAC_ratio = T.dcac_ratio;
        elseif ismember('P_PV_kW', T.Properties.VariableNames) && ismember('P_inv_kW', T.Properties.VariableNames)
            T.DCAC_ratio = T.P_PV_kW ./ T.P_inv_kW;
        else
            error('DCAC_ratio hianyzik, es nem szamolhato P_PV_kW/P_inv_kW alapjan.');
        end
    end

    if ~ismember('coupling', T.Properties.VariableNames)
        error('A combinedTable nem tartalmaz coupling mezot. Varhato ertekek: dc, ac.');
    end

    if ~ismember('NPV_millionHUF', T.Properties.VariableNames) && ismember('NPV_HUF', T.Properties.VariableNames)
        T.NPV_millionHUF = T.NPV_HUF ./ 1e6;
    end

    if ~ismember('NPV_BESSOnly_millionHUF', T.Properties.VariableNames) && ismember('NPV_BESSOnly_HUF', T.Properties.VariableNames)
        T.NPV_BESSOnly_millionHUF = T.NPV_BESSOnly_HUF ./ 1e6;
    end

    if ~ismember('periodNetValue_millionHUF', T.Properties.VariableNames) && ismember('periodNetValue_HUF', T.Properties.VariableNames)
        T.periodNetValue_millionHUF = T.periodNetValue_HUF ./ 1e6;
    end

    if ~ismember('periodNetValue_BESSOnly_millionHUF', T.Properties.VariableNames) && ismember('periodNetValue_BESSOnly_HUF', T.Properties.VariableNames)
        T.periodNetValue_BESSOnly_millionHUF = T.periodNetValue_BESSOnly_HUF ./ 1e6;
    end

    required = { ...
        'candidateIndex', ...
        'coupling', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'BESS_PV_ratio', ...
        'DCAC_ratio', ...
        'NPV_millionHUF', ...
        'periodNetValue_millionHUF', ...
        'wasSimulated', ...
        'hasError'};

    for i = 1:numel(required)
        if ~ismember(required{i}, T.Properties.VariableNames)
            error('A combinedTable nem tartalmazza a szukseges mezot: %s', required{i});
        end
    end
end


% =========================================================================
% SELECTION
% =========================================================================
function selection = local_select_summary_systems(T)

    valid = logical(T.wasSimulated) & ~logical(T.hasError);

    pvOnlyMask = ...
        valid & ...
        T.E_BESS_kWh <= 1e-9 & ...
        isfinite(T.NPV_millionHUF);

    dcMask = ...
        valid & ...
        lower(string(T.coupling)) == "dc" & ...
        T.E_BESS_kWh > 1e-9 & ...
        isfinite(T.NPV_millionHUF);

    acMask = ...
        valid & ...
        lower(string(T.coupling)) == "ac" & ...
        T.E_BESS_kWh > 1e-9 & ...
        isfinite(T.NPV_millionHUF);

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
        error('Nincs megfelelo candidate a summary tablazathoz.');
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


function summaryTable = local_create_best_systems_summary_table(T, selection)

    indices = [ ...
        selection.pvOnlyIndex, ...
        selection.bestDcIndex, ...
        selection.bestAcIndex];

    labels = {
        'Architektúra'
        'PV névleges teljesítménye'
        'Inverter névleges teljesítménye'
        'DC/AC arány'
        'BESS kapacitása'
        'BESS teljesítménye'
        'BESS/PV arány'
        'Teljes rendszer NPV-je'
        'BESS hozzáadott értékének NPV-je'
        'Szimulált időszak nettó értéke'
        'BESS hozzáadott értéke a szimulált időszakban'
        'Éves energiaköltség-megtakarítás'
        'Teljes beruházási költség'
        'BESS beruházási költség'
        'Sajátfogyasztási arány'
        'Önellátási arány'
        'Nem hasznosított PV energia'
        'Éves BESS ciklusszám'
        'Végső SoH'
        'Statikus megtérülési idő'
        'Diszkontált megtérülési idő'
        };

    units = {
        '-'
        'kWp'
        'kW'
        '-'
        'kWh'
        'kW'
        'kWh/kWp'
        'millió Ft'
        'millió Ft'
        'millió Ft'
        'millió Ft'
        'millió Ft/év'
        'millió Ft'
        'millió Ft'
        '%'
        '%'
        '%'
        'db/év'
        '-'
        'év'
        'év'
        };

    values = strings(numel(labels), 3);

    for c = 1:3
        idx = indices(c);
        values(:, c) = local_get_column_values_for_candidate(T, idx);
    end

    summaryTable = table();

    summaryTable.Mennyiseg = string(labels);
    summaryTable.CsakPV = values(:, 1);
    summaryTable.LegjobbDC = values(:, 2);
    summaryTable.LegjobbAC = values(:, 3);
    summaryTable.Mertekegyseg = string(units);
end


function values = local_get_column_values_for_candidate(T, idx)

    values = strings(21, 1);

    values(1) = local_get_architecture_label(T, idx);

    values(2) = local_format_value(T.P_PV_kW(idx));
    values(3) = local_format_value(T.P_inv_kW(idx));
    values(4) = local_format_value(T.DCAC_ratio(idx));
    values(5) = local_format_optional_bess_value(T.E_BESS_kWh(idx));
    values(6) = local_format_optional_bess_value(T.P_BESS_kW(idx));
    values(7) = local_format_optional_bess_value(T.BESS_PV_ratio(idx));

    values(8) = local_format_existing(T, idx, 'NPV_millionHUF');
    values(9) = local_format_existing_optional_bess(T, idx, 'NPV_BESSOnly_millionHUF');

    values(10) = local_format_existing(T, idx, 'periodNetValue_millionHUF');
    values(11) = local_format_existing_optional_bess(T, idx, 'periodNetValue_BESSOnly_millionHUF');

    if ismember('annualEnergySavings_HUF', T.Properties.VariableNames)
        values(12) = local_format_value(T.annualEnergySavings_HUF(idx) ./ 1e6);
    else
        values(12) = "-";
    end

    if ismember('initialCapex_HUF', T.Properties.VariableNames)
        values(13) = local_format_value(T.initialCapex_HUF(idx) ./ 1e6);
    else
        values(13) = "-";
    end

    if ismember('capexBESS_HUF', T.Properties.VariableNames)
        values(14) = local_format_optional_bess_value(T.capexBESS_HUF(idx) ./ 1e6);
    else
        values(14) = "-";
    end

    values(15) = local_format_existing(T, idx, 'selfConsumption_pct');
    values(16) = local_format_existing(T, idx, 'selfSufficiency_pct');
    values(17) = local_format_existing(T, idx, 'unusedPV_pct');
    values(18) = local_format_existing_optional_bess(T, idx, 'annualBessEquivalentCycles');
    values(19) = local_format_existing_optional_bess(T, idx, 'finalSoH');
    values(20) = local_format_existing(T, idx, 'simplePayback_year');
    values(21) = local_format_existing(T, idx, 'discountedPayback_year');
end


function s = local_format_existing(T, idx, fieldName)

    if ~ismember(fieldName, T.Properties.VariableNames)
        s = "-";
        return;
    end

    s = local_format_value(T.(fieldName)(idx));
end

function label = local_get_architecture_label(T, idx)

    if T.E_BESS_kWh(idx) <= 1e-9
        label = "Sima napelemes rendszer";
        return;
    end

    switch lower(string(T.coupling(idx)))

        case "dc"
            label = "DC-csatolt PV+BESS rendszer";

        case "ac"
            label = "AC-csatolt PV+BESS rendszer";

        otherwise
            label = string(T.coupling(idx));
    end
end


function s = local_format_existing_optional_bess(T, idx, fieldName)

    if T.E_BESS_kWh(idx) <= 1e-9
        s = "-";
        return;
    end

    s = local_format_existing(T, idx, fieldName);
end


function s = local_format_optional_bess_value(value)

    if ~isfinite(value) || abs(value) <= 1e-9
        s = "-";
    else
        s = local_format_value(value);
    end
end


function s = local_format_value(value)

    if isstring(value)
        s = value;
        return;
    end

    if ischar(value)
        s = string(value);
        return;
    end

    if ~isfinite(value)
        s = "-";
        return;
    end

    ax = abs(value);

    if ax >= 1000
        s = string(sprintf('%.0f', value));
    elseif ax >= 100
        s = string(sprintf('%.1f', value));
    elseif ax >= 10
        s = string(sprintf('%.2f', value));
    elseif ax >= 1
        s = string(sprintf('%.3f', value));
    else
        s = string(sprintf('%.4f', value));
    end
end


% =========================================================================
% FIGURE OUTPUT
% =========================================================================
function local_plot_best_systems_summary_table(summaryTable, outputRoot, fileTag)

    nRows = height(summaryTable);
    nCols = width(summaryTable);

    figW = 1500;
    figH = max(780, 120 + 34 * nRows);

    fig = figure( ...
        'Name', 'Best systems summary', ...
        'Color', 'w', ...
        'Position', [80, 80, figW, figH]);

    ax = axes(fig);
    hold(ax, 'on');
    axis(ax, 'off');

    rowH = 1.0;
    headerH = 1.15;

    colW = [4.2, 4.0, 4.0, 4.0, 2.0];

    totalW = sum(colW);
    totalH = headerH + nRows * rowH;

    xlim(ax, [0, totalW]);
    ylim(ax, [0, totalH]);

    headerColor = [0.12, 0.20, 0.32];
    headerTextColor = [1, 1, 1];

    labelColor = [0.94, 0.96, 0.98];
    unitColor = [0.94, 0.96, 0.98];

    pvColor = [0.90, 0.96, 1.00];
    dcColor = [0.92, 0.98, 0.92];
    acColor = [1.00, 0.95, 0.90];

    dataColors = {labelColor, pvColor, dcColor, acColor, unitColor};

    varNames = summaryTable.Properties.VariableNames;

    yHeader = totalH - headerH;

    x0 = 0;

    for c = 1:nCols

        rectangle(ax, ...
            'Position', [x0, yHeader, colW(c), headerH], ...
            'FaceColor', headerColor, ...
            'EdgeColor', [1, 1, 1], ...
            'LineWidth', 1.0);

        text(ax, x0 + colW(c) / 2, yHeader + headerH / 2, ...
            local_pretty_var_name(varNames{c}), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontWeight', 'bold', ...
            'FontSize', 10, ...
            'Color', headerTextColor, ...
            'Interpreter', 'none');

        x0 = x0 + colW(c);
    end

    for r = 1:nRows

        y0 = totalH - headerH - r * rowH;

        x0 = 0;

        for c = 1:nCols

            rectangle(ax, ...
                'Position', [x0, y0, colW(c), rowH], ...
                'FaceColor', dataColors{c}, ...
                'EdgeColor', [0.78, 0.78, 0.78], ...
                'LineWidth', 0.75);

            rawValue = summaryTable.(varNames{c})(r);

            if isstring(rawValue)
                textValue = char(rawValue);
            elseif iscell(rawValue)
                textValue = char(rawValue{1});
            else
                textValue = char(string(rawValue));
            end

            if c == 1
                hAlign = 'left';
                xText = x0 + 0.08;
                fontWeight = 'bold';
            else
                hAlign = 'center';
                xText = x0 + colW(c) / 2;
                fontWeight = 'normal';
            end

            text(ax, xText, y0 + rowH / 2, ...
                textValue, ...
                'HorizontalAlignment', hAlign, ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 9, ...
                'FontWeight', fontWeight, ...
                'Color', [0.05, 0.05, 0.05], ...
                'Interpreter', 'none');

            x0 = x0 + colW(c);
        end
    end

    title(ax, 'Best AC, best DC and PV-only system summary', ...
        'FontSize', 16, ...
        'FontWeight', 'bold');

    savefig(fig, fullfile(outputRoot, [fileTag, '.fig']));

    try
        exportgraphics(fig, fullfile(outputRoot, [fileTag, '.png']), 'Resolution', 300);
    catch
        saveas(fig, fullfile(outputRoot, [fileTag, '.png']));
    end

    try
        exportgraphics(fig, fullfile(outputRoot, [fileTag, '.pdf']), 'ContentType', 'vector');
    catch
    end
end


function s = local_pretty_var_name(varName)

    switch string(varName)

        case "Mennyiseg"
            s = "Mennyiség";

        case "CsakPV"
            s = "Sima napelemes rendszer";

        case "LegjobbDC"
            s = "Legjobb DC-csatolt rendszer";

        case "LegjobbAC"
            s = "Legjobb AC-csatolt rendszer";

        case "Mertekegyseg"
            s = "Mértékegység";

        otherwise
            s = string(varName);
    end
end


% =========================================================================
% HTML OUTPUT
% =========================================================================
function local_write_best_systems_summary_html(summaryTable, outputRoot, fileTag)

    htmlPath = fullfile(outputRoot, [fileTag, '.html']);

    fid = fopen(htmlPath, 'w');

    if fid < 0
        error('Nem sikerult megnyitni HTML irasra: %s', htmlPath);
    end

    cleanupObj = onCleanup(@() fclose(fid));

    varNames = summaryTable.Properties.VariableNames;

    fprintf(fid, '<!DOCTYPE html>\n');
    fprintf(fid, '<html lang=\"hu\">\n');
    fprintf(fid, '<head>\n');
    fprintf(fid, '<meta charset=\"UTF-8\">\n');
    fprintf(fid, '<title>Best systems summary</title>\n');
    fprintf(fid, '<style>\n');
    fprintf(fid, 'body { font-family: Arial, sans-serif; margin: 32px; background: #f5f7fb; color: #111827; }\n');
    fprintf(fid, 'h1 { color: #111827; }\n');
    fprintf(fid, 'table { border-collapse: collapse; width: 100%%; background: white; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }\n');
    fprintf(fid, 'th { background: #1f2937; color: white; padding: 10px; text-align: center; }\n');
    fprintf(fid, 'td { border: 1px solid #d1d5db; padding: 8px; text-align: center; }\n');
    fprintf(fid, 'td:first-child { text-align: left; font-weight: bold; background: #f3f4f6; }\n');
    fprintf(fid, 'td:nth-child(2) { background: #eff6ff; }\n');
    fprintf(fid, 'td:nth-child(3) { background: #f0fdf4; }\n');
    fprintf(fid, 'td:nth-child(4) { background: #fff7ed; }\n');
    fprintf(fid, 'td:last-child { background: #f3f4f6; }\n');
    fprintf(fid, '</style>\n');
    fprintf(fid, '</head>\n');
    fprintf(fid, '<body>\n');
    fprintf(fid, '<h1>Best AC, best DC and PV-only system summary</h1>\n');
    fprintf(fid, '<table>\n');

    fprintf(fid, '<tr>');
    for c = 1:numel(varNames)
        fprintf(fid, '<th>%s</th>', char(local_pretty_var_name(varNames{c})));
    end
    fprintf(fid, '</tr>\n');

    for r = 1:height(summaryTable)

        fprintf(fid, '<tr>');

        for c = 1:numel(varNames)

            rawValue = summaryTable.(varNames{c})(r);

            if isstring(rawValue)
                valueText = char(rawValue);
            elseif iscell(rawValue)
                valueText = char(rawValue{1});
            else
                valueText = char(string(rawValue));
            end

            fprintf(fid, '<td>%s</td>', local_escape_html(valueText));
        end

        fprintf(fid, '</tr>\n');
    end

    fprintf(fid, '</table>\n');
    fprintf(fid, '</body>\n');
    fprintf(fid, '</html>\n');
end


function escaped = local_escape_html(inputText)

    escaped = char(inputText);
    escaped = strrep(escaped, '&', '&amp;');
    escaped = strrep(escaped, '<', '&lt;');
    escaped = strrep(escaped, '>', '&gt;');
    escaped = strrep(escaped, '\"', '&quot;');
    escaped = strrep(escaped, '''', '&#39;');
end