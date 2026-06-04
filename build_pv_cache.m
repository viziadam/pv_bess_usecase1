function PV = build_pv_cache(tiltX, tiltZ, Pdc_kWp, modulePower_kWp)
% BUILD_PV_CACHE
%
% PV production cache for the requested orientations.
%
% Important:
%   - It does not require complete 365-day years.
%   - It does not drop partial years.
%   - It loads every day with a valid date.
%   - It sorts the output by date.
%   - It does not mix different orientations.
%   - Identical tiltX / tiltZ pairs are merged into one MPPT group.
%
% Input:
%   tiltX            : tilt angle [deg], scalar or vector
%   tiltZ            : azimuth angle [deg], scalar or vector
%   Pdc_kWp          : DC capacity assigned to each orientation [kWp]
%   modulePower_kWp  : rated power of one module [kWp]
%
% Output:
%   PV(k).Ppv        : total reference PV power [kW], one day
%   PV(k).pvGroups   : orientation-specific / MPPT-group data
%   PV(k).timeMinVec : time axis [min]
%   PV(k).dt_h       : time step [h]
%   PV(k).timeDay    : date string
%   PV(k).date       : datetime date
%
% Notes:
%   tPDC_raw  [W] is one module MPP power.
%   tVMPP_raw [V] is one module MPP voltage.
%
%   The string voltage is not created here.
%   It is created later in simulate_day_vectorized:
%
%       V_string_mpp = Ns * V_mpp_module
%
%   Each pvGroups(c) represents one unique orientation / MPPT input.

    persistent PV_MAP

    if nargin < 4 || isempty(modulePower_kWp)
        modulePower_kWp = 0.5;
    end

    if ~isnumeric(modulePower_kWp) || ~isscalar(modulePower_kWp) || ...
            ~isfinite(modulePower_kWp) || modulePower_kWp <= 0
        error('modulePower_kWp must be a positive finite scalar.');
    end

    thisDir = fileparts(mfilename('fullpath'));
    pvDir = fullfile(thisDir, 'production');

    if isempty(PV_MAP)
        PV_MAP = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    % ---------------------------------------------------------------------
    % Input normalization
    % ---------------------------------------------------------------------
    tiltX = tiltX(:).';
    tiltZ = tiltZ(:).';
    Pdc_kWp = Pdc_kWp(:).';

    if isscalar(tiltX) && numel(tiltZ) > 1
        tiltX = repmat(tiltX, 1, numel(tiltZ));
    end

    if isscalar(Pdc_kWp) && numel(tiltZ) > 1
        Pdc_kWp = repmat(Pdc_kWp / numel(tiltZ), 1, numel(tiltZ));
    end

    if numel(tiltX) ~= numel(tiltZ)
        error('tiltX must be scalar or must have the same length as tiltZ.');
    end

    if numel(Pdc_kWp) ~= numel(tiltZ)
        error('Pdc_kWp length must match tiltZ length, or Pdc_kWp must be scalar.');
    end

    % ---------------------------------------------------------------------
    % Merge identical orientations
    % ---------------------------------------------------------------------
    [tiltX, tiltZ, Pdc_kWp] = local_merge_identical_orientations( ...
        tiltX, ...
        tiltZ, ...
        Pdc_kWp);

    cacheKey = sprintf('PV_CACHE_GROUPED_MPPT_V2_X%s_Z%s_P%s_MOD%.6f_DIR%s', ...
        mat2str(tiltX), mat2str(tiltZ), mat2str(Pdc_kWp), modulePower_kWp, pvDir);

    if PV_MAP.isKey(cacheKey)
        fprintf('PV reference data loaded from RAM cache.\n');
        PV = PV_MAP(cacheKey);
        return;
    end

    fprintf('Reading PV reference data from production files...\n');

    files = dir(fullfile(pvDir, '*.mat'));

    if isempty(files)
        error('No .mat files found in PV folder: %s', pvDir);
    end

    nF = numel(files);
    dates = nan(nF, 3);

    for i = 1:nF

        dates(i, :) = local_parse_date_from_filename(files(i).name);

        if any(isnan(dates(i, :)))
            S = load(fullfile(pvDir, files(i).name), 'resultBuffer');

            if isfield(S, 'resultBuffer') && isfield(S.resultBuffer, 'timeDay')
                dates(i, :) = local_parse_date_from_string(S.resultBuffer.timeDay);
            end
        end
    end

    validDate = ~isnan(dates(:, 1));
    files = files(validDate);
    dates = dates(validDate, :);

    if isempty(files)
        error('No PV files with valid dates were found in folder: %s', pvDir);
    end

    dateSerial = datenum(dates(:, 1), dates(:, 2), dates(:, 3));
    [~, order] = sort(dateSerial);

    files = files(order);
    dates = dates(order, :);

    nF = numel(files);

    PV(nF) = struct( ...
        'Ppv', [], ...
        'pvGroups', [], ...
        'timeMinVec', [], ...
        'dt_h', [], ...
        'timeDay', '', ...
        'date', NaT);

    for k = 1:nF

        fPath = fullfile(pvDir, files(k).name);
        S = load(fPath);

        if ~isfield(S, 'resultBuffer')
            error('Missing resultBuffer in file: %s', files(k).name);
        end

        rb = S.resultBuffer;

        if ~isfield(rb, 'timeVectorMin')
            error('Missing resultBuffer.timeVectorMin in file: %s', files(k).name);
        end

        if ~isfield(rb, 'results')
            error('Missing resultBuffer.results in file: %s', files(k).name);
        end

        timeMinVec = rb.timeVectorMin(:).';
        resTable = rb.results;

        requiredColumns = {'tiltX', 'tiltZ', 'tPDC'};

        for q = 1:numel(requiredColumns)
            if ~ismember(requiredColumns{q}, resTable.Properties.VariableNames)
                error('Missing %s column in resultBuffer.results: %s', ...
                    requiredColumns{q}, files(k).name);
            end
        end

        Ppv_total_kW = zeros(1, numel(timeMinVec));

        pvGroups = repmat( ...
            struct( ...
                'tiltX', [], ...
                'tiltZ', [], ...
                'Pdc_ref_kWp', [], ...
                'modulePower_kWp', modulePower_kWp, ...
                'N_modules_ref', [], ...
                'P_module_W', [], ...
                'V_mpp_module_V', [], ...
                'P_orientation_kW', [], ...
                'voltageAvailable', false), ...
            1, numel(tiltZ));

        for c = 1:numel(tiltZ)

            cX = tiltX(c);
            cZ = tiltZ(c);
            cPower_kWp = Pdc_kWp(c);

            rowIdx = find(resTable.tiltX == cX & resTable.tiltZ == cZ, 1);

            if isempty(rowIdx)
                warning('PV orientation not found: tiltX=%g, tiltZ=%g in %s', ...
                    cX, cZ, files(k).name);
                continue;
            end

            if iscell(resTable.tPDC)
                tPDC_raw = resTable.tPDC{rowIdx};
            else
                tPDC_raw = resTable.tPDC(rowIdx, :);
            end

            tPDC_raw = double(tPDC_raw(:).');

            if numel(tPDC_raw) ~= numel(timeMinVec)
                error(['Length mismatch between tPDC and time vector in file: %s. ', ...
                       'tPDC length = %d, time length = %d.'], ...
                       files(k).name, numel(tPDC_raw), numel(timeMinVec));
            end

            if ismember('tVMPP', resTable.Properties.VariableNames)

                if iscell(resTable.tVMPP)
                    tVMPP_raw = resTable.tVMPP{rowIdx};
                else
                    tVMPP_raw = resTable.tVMPP(rowIdx, :);
                end

                tVMPP_raw = double(tVMPP_raw(:).');
                voltageAvailable = true;

            else
                warning('Missing tVMPP in %s. Voltage data will be set to NaN.', files(k).name);
                tVMPP_raw = NaN(size(tPDC_raw));
                voltageAvailable = false;
            end

            if numel(tVMPP_raw) ~= numel(tPDC_raw)
                error('Length mismatch between tPDC and tVMPP in file: %s', files(k).name);
            end

            % tPDC_raw is one module MPP power.
            % Scale it to the reference orientation capacity.
            N_modules_ref = cPower_kWp / modulePower_kWp;

            Ppv_orientation_kW = (tPDC_raw / 1000) * N_modules_ref;

            Ppv_total_kW = Ppv_total_kW + Ppv_orientation_kW;

            pvGroups(c).tiltX = cX;
            pvGroups(c).tiltZ = cZ;
            pvGroups(c).Pdc_ref_kWp = cPower_kWp;
            pvGroups(c).modulePower_kWp = modulePower_kWp;
            pvGroups(c).N_modules_ref = N_modules_ref;

            pvGroups(c).P_module_W = tPDC_raw;
            pvGroups(c).V_mpp_module_V = tVMPP_raw;
            pvGroups(c).P_orientation_kW = Ppv_orientation_kW;
            pvGroups(c).voltageAvailable = voltageAvailable;
        end

        PV(k).Ppv = Ppv_total_kW;
        PV(k).pvGroups = pvGroups;

        PV(k).timeMinVec = timeMinVec;

        if isfield(rb, 'timeStepMin') && ~isempty(rb.timeStepMin)
            PV(k).dt_h = rb.timeStepMin / 60;
        else
            if numel(timeMinVec) >= 2
                PV(k).dt_h = (timeMinVec(2) - timeMinVec(1)) / 60;
            else
                error('Cannot determine dt_h for file: %s', files(k).name);
            end
        end

        PV(k).date = datetime(dates(k, 1), dates(k, 2), dates(k, 3));

        if isfield(rb, 'timeDay')
            PV(k).timeDay = rb.timeDay;
        else
            PV(k).timeDay = sprintf('%04d.%02d.%02d', dates(k, 1), dates(k, 2), dates(k, 3));
        end
    end

    PV_MAP(cacheKey) = PV;

    fprintf('PV reference cache ready: %d days, %.3f kWp reference, %d MPPT groups.\n', ...
        numel(PV), sum(Pdc_kWp), numel(tiltZ));
end


function [tiltX_out, tiltZ_out, Pdc_out] = local_merge_identical_orientations(tiltX, tiltZ, Pdc_kWp)

    orientationTable = table( ...
        tiltX(:), ...
        tiltZ(:), ...
        Pdc_kWp(:), ...
        'VariableNames', {'tiltX', 'tiltZ', 'Pdc_kWp'});

    [G, uniqueOrientations] = findgroups(orientationTable(:, {'tiltX', 'tiltZ'}));

    Pdc_sum = splitapply(@sum, orientationTable.Pdc_kWp, G);

    tiltX_out = uniqueOrientations.tiltX(:).';
    tiltZ_out = uniqueOrientations.tiltZ(:).';
    Pdc_out = Pdc_sum(:).';
end


function dateParts = local_parse_date_from_filename(fileName)

    tok = regexp(fileName, '(\d{4})[._-](\d{2})[._-](\d{2})', 'tokens', 'once');

    if isempty(tok)
        dateParts = [NaN NaN NaN];
    else
        dateParts = str2double(tok);
    end
end


function dateParts = local_parse_date_from_string(str)

    tok = regexp(char(str), '(\d{4})[._-](\d{2})[._-](\d{2})', 'tokens', 'once');

    if isempty(tok)
        dateParts = [NaN NaN NaN];
    else
        dateParts = str2double(tok);
    end
end