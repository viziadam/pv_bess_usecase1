function dayResult = simulate_day_vectorized(dayInput, stateStart, design, cfg)
% SIMULATE_DAY_VECTORIZED
%
% One-day grid-connected PV+BESS self-consumption simulation.
%
% DC-coupled case:
%   PV groups -> MPPT DC/DC -> regulated DC-link -> inverter -> AC load
%   BESS pack <-> bidirectional buck-boost DC/DC <-> regulated DC-link
%
% AC-coupled case:
%   PV DC -> PV inverter -> AC bus
%   BESS pack <-> PCS <-> AC bus

    % ---------------------------------------------------------------------
    % 1) Inputs
    % ---------------------------------------------------------------------
    P_load_kW = dayInput.P_load_kW(:);
    P_pv_base_kW = dayInput.P_pv_base_kW(:);
    dt_h = dayInput.dt_h;

    N = min(numel(P_load_kW), numel(P_pv_base_kW));

    P_load_kW = max(0, P_load_kW(1:N));
    P_pv_base_kW = max(0, P_pv_base_kW(1:N));

    if ~isfield(design, 'P_PV_kW')
        error('design.P_PV_kW is missing.');
    end

    % Orientation-specific / MPPT-group PV data.
    % This creates:
    %   modules -> strings -> parallel strings -> MPPT groups.
    pvGroups = local_build_pv_mppt_groups(dayInput, design, cfg, N);

    % Use the MPPT-group sum as the authoritative PV input if available.
    % This prevents scaling mismatch between P_pv_base_kW and pvGroups.
    if ~isempty(pvGroups)
        P_pv_dc_kW = local_sum_pv_group_power(pvGroups, N);
    else
        scaleFactor = local_get_reference_scale_factor(dayInput, design, cfg);
        P_pv_dc_kW = P_pv_base_kW * scaleFactor;
    end

    % Ambient temperature vector.
    if isfield(dayInput, 'T_amb_C')
        T_amb_C = dayInput.T_amb_C(:);
        T_amb_C = T_amb_C(1:min(numel(T_amb_C), N));

        if numel(T_amb_C) < N
            T_amb_C(end+1:N) = T_amb_C(end);
        end
    else
        T_amb_C = 25 * ones(N, 1);
    end

    % ---------------------------------------------------------------------
    % 2) No grid export in this application
    % ---------------------------------------------------------------------
    if ~isfield(cfg, 'grid')
        cfg.grid = struct();
    end

    cfg.grid.allowExport = false;

    % ---------------------------------------------------------------------
    % 3) Topology selection
    % ---------------------------------------------------------------------
    coupling = local_get_bess_coupling(cfg);

    switch coupling

        case "dc"
            [step, stateAfterBess] = dccoupled_energy_strategy_vector( ...
                P_pv_dc_kW, ...
                P_load_kW, ...
                design, ...
                stateStart, ...
                dt_h, ...
                T_amb_C, ...
                cfg, ...
                pvGroups);

        case "ac"
            [step, stateAfterBess] = accoupled_energy_strategy_vector( ...
                P_pv_dc_kW, ...
                P_load_kW, ...
                design, ...
                stateStart, ...
                dt_h, ...
                T_amb_C, ...
                cfg);

        otherwise
            error('Unknown BESS coupling: %s. Use "dc" or "ac".', coupling);
    end

    % ---------------------------------------------------------------------
    % 4) Grid-connected final balance
    % ---------------------------------------------------------------------
    P_grid_import_kW = step.P_grid_import_kW;

    P_grid_export_kW = zeros(N, 1);

    P_served_kW = ...
        step.P_pv_to_load_kW + ...
        step.P_bess_to_load_kW + ...
        P_grid_import_kW;

    P_served_kW = min(P_served_kW, P_load_kW);

    P_unserved_kW = max(P_load_kW - P_served_kW, 0);

    P_internal_network_loss_kW = zeros(N, 1);

    % ---------------------------------------------------------------------
    % 5) dayVectors for metric update and diagnostics
    % ---------------------------------------------------------------------
    dayVectors = struct();

    dayVectors.P_load_kW = P_load_kW;
    dayVectors.P_pv_available_kW = step.P_pv_available_kW;

    dayVectors.P_served_kW = P_served_kW;
    dayVectors.P_unserved_kW = P_unserved_kW;

    dayVectors.P_pv_to_load_kW = step.P_pv_to_load_kW;
    dayVectors.P_pv_to_bess_kW = step.P_pv_to_bess_kW;
    dayVectors.P_bess_to_load_kW = step.P_bess_to_load_kW;

    dayVectors.P_grid_import_kW = P_grid_import_kW;
    dayVectors.P_grid_export_kW = P_grid_export_kW;

    dayVectors.P_curtailment_kW = step.P_curtailment_kW;

    dayVectors.P_inv_loss_kW = step.P_inv_loss_kW;
    dayVectors.P_dcdc_loss_kW = step.P_dcdc_loss_kW;
    dayVectors.P_internal_network_loss_kW = P_internal_network_loss_kW;

    dayVectors.SoC = step.SoC;

    % ---------------------------------------------------------------------
    % Detailed BESS losses
    % ---------------------------------------------------------------------
    dayVectors.P_bess_cell_loss_kW = step.P_bess_cell_loss_kW;
    dayVectors.P_bess_soc_full_loss_kW = step.P_bess_soc_full_loss_kW;
    dayVectors.P_bess_soc_empty_loss_kW = step.P_bess_soc_empty_loss_kW;
    dayVectors.P_bess_total_internal_loss_kW = step.P_bess_total_internal_loss_kW;

    % ---------------------------------------------------------------------
    % Detailed DC/DC losses
    % ---------------------------------------------------------------------
    dayVectors.P_dcdc_conversion_loss_kW = step.P_dcdc_conversion_loss_kW;
    dayVectors.P_dcdc_power_clipped_kW = step.P_dcdc_power_clipped_kW;

    % ---------------------------------------------------------------------
    % Detailed inverter / PCS losses
    % ---------------------------------------------------------------------
    dayVectors.P_inv_conversion_loss_kW = step.P_inv_conversion_loss_kW;
    dayVectors.P_inv_power_clipped_kW = step.P_inv_power_clipped_kW;

    dayVectors.P_inv_pv_conversion_loss_kW = step.P_inv_pv_conversion_loss_kW;
    dayVectors.P_inv_bess_conversion_loss_kW = step.P_inv_bess_conversion_loss_kW;

    dayVectors.P_inv_pv_clipped_kW = step.P_inv_pv_clipped_kW;
    dayVectors.P_inv_bess_clipped_kW = step.P_inv_bess_clipped_kW;

    % ---------------------------------------------------------------------
    % Optional detailed DC-coupled diagnostics
    % ---------------------------------------------------------------------
    optionalNames = { ...
        'V_pv_mpp_mean_V', ...
        'V_dc_link_V', ...
        'V_pack_pre_V', ...
        'V_pack_actual_V', ...
        'P_pv_mpp_total_kW', ...
        'P_pv_after_mppt_dcdc_kW', ...
        'P_pv_mppt_balance_error_kW', ...
        'P_pv_dcdc_conversion_loss_kW', ...
        'P_pv_dcdc_power_clipped_kW', ...
        'P_bess_dcdc_conversion_loss_kW', ...
        'P_bess_dcdc_power_clipped_kW', ...
        'P_ac_required_from_inv_kW', ...
        'P_dc_required_at_inv_kW', ...
        'P_pv_dc_to_inv_kW', ...
        'P_dc_deficit_kW', ...
        'P_pv_surplus_kW', ...
        'P_bess_high_req_kW', ...
        'P_bess_high_actual_kW', ...
        'P_pack_req_kW', ...
        'P_pack_actual_kW', ...
        'P_inv_dc_input_total_kW', ...
        'P_inv_ac_output_kW', ...
        'eta_inverter', ...
        'inverter_loadFraction', ...
        'eta_pv_mppt_dcdc', ...
        'mppt_voltageRatio_mean', ...
        'mppt_loadFraction_mean', ...
        'mppt_etaLoad_mean', ...
        'mppt_etaVoltage_mean', ...
        'eta_bess_dcdc', ...
        'bess_dcdc_etaLoad', ...
        'bess_dcdc_etaVoltage', ...
        'bess_dcdc_voltageRatio', ...
        'bess_dcdc_loadFraction'};

    for k = 1:numel(optionalNames)
        name = optionalNames{k};

        if isfield(step, name)
            dayVectors.(name) = local_fit_vector(step.(name), N, NaN);
        end
    end

    if ~isempty(pvGroups)
        dayVectors.pvGroups = pvGroups;
    end

    % ---------------------------------------------------------------------
    % 6) Output
    % ---------------------------------------------------------------------
    dayResult = struct();
    dayResult.dayVectors = dayVectors;
    dayResult.stateEnd = stateAfterBess;
    dayResult.coupling = coupling;
end


function coupling = local_get_bess_coupling(cfg)

    coupling = "dc";

    if isfield(cfg, 'system') && isfield(cfg.system, 'bessCoupling')
        coupling = lower(string(cfg.system.bessCoupling));
    elseif isfield(cfg, 'bess') && isfield(cfg.bess, 'coupling')
        coupling = lower(string(cfg.bess.coupling));
    end

    if coupling == "dc-coupled"
        coupling = "dc";
    end

    if coupling == "ac-coupled"
        coupling = "ac";
    end
end


function pvGroups = local_build_pv_mppt_groups(dayInput, design, cfg, N)

    pvGroups = [];

    if ~isfield(dayInput, 'pvGroups') || isempty(dayInput.pvGroups)
        error(['simulate_day_vectorized: dayInput.pvGroups is missing. ', ...
           'The simulation requires pvGroups for PV voltage and MPPT/DC-link modelling.']);
    end

    rawGroups = dayInput.pvGroups;

    modulePower_kWp = local_get_module_power_kWp(cfg);
    stringDesign = local_get_pv_string_design(cfg);

    Ns = stringDesign.Ns;

    scaleFactor = local_get_reference_scale_factor(dayInput, design, cfg);

    enforceIntegerStrings = local_get_bool_cfg(cfg, {'pv', 'enforceIntegerStrings'}, false);
    stringRoundingMode = local_get_string_cfg(cfg, {'pv', 'stringRoundingMode'}, "round");

    template = struct( ...
        'tiltX', [], ...
        'tiltZ', [], ...
        'Pdc_ref_kWp', [], ...
        'Pdc_scaled_kWp', [], ...
        'Pdc_installed_kWp', [], ...
        'modulePower_kWp', modulePower_kWp, ...
        'Ns', Ns, ...
        'NsMaxVoc', stringDesign.NsMaxVoc, ...
        'VocColdModule_V', stringDesign.VocColdModule_V, ...
        'VocColdString_V', stringDesign.VocColdString_V, ...
        'maxStringVoltage_V', stringDesign.maxStringVoltage_V, ...
        'Np', [], ...
        'N_modules', [], ...
        'N_modules_ref', [], ...
        'P_string_stc_kWp', [], ...
        'P_module_W', [], ...
        'V_mpp_module_V', [], ...
        'V_string_mpp_V', [], ...
        'P_orientation_ref_kW', [], ...
        'P_orientation_available_kW', [], ...
        'P_mppt_in_kW', [], ...
        'scaleFactor', scaleFactor, ...
        'stringScaleFactor', [], ...
        'voltageAvailable', false);

    pvGroups = repmat(template, 1, numel(rawGroups));

    for g = 1:numel(rawGroups)

        raw = rawGroups(g);

        Pdc_ref_kWp = local_get_numeric_field(raw, 'Pdc_ref_kWp', NaN);

        if ~isfinite(Pdc_ref_kWp) || Pdc_ref_kWp <= 0
            Pdc_ref_kWp = 1 / max(numel(rawGroups), 1);
        end

        Pdc_target_kWp = Pdc_ref_kWp * scaleFactor;

        N_modules_target = Pdc_target_kWp / modulePower_kWp;
        Np_ideal = N_modules_target / Ns;

        if enforceIntegerStrings
            Np = local_round_string_count(Np_ideal, stringRoundingMode);
            Np = max(1, Np);

            N_modules = Ns * Np;
            Pdc_installed_kWp = N_modules * modulePower_kWp;

            stringScaleFactor = Pdc_installed_kWp / Pdc_ref_kWp;
        else
            Np = Np_ideal;
            N_modules = N_modules_target;
            Pdc_installed_kWp = Pdc_target_kWp;

            stringScaleFactor = scaleFactor;
        end

        P_string_stc_kWp = Ns * modulePower_kWp;

        P_module_W = local_fit_vector(local_get_field_or_empty(raw, 'P_module_W'), N, NaN);
        V_mpp_module_V = local_fit_vector(local_get_field_or_empty(raw, 'V_mpp_module_V'), N, NaN);
        P_orientation_ref_kW = local_fit_vector(local_get_field_or_empty(raw, 'P_orientation_kW'), N, 0);

        P_orientation_available_kW = max(0, P_orientation_ref_kW * stringScaleFactor);

        V_string_mpp_V = Ns * V_mpp_module_V;

        if isfield(raw, 'voltageAvailable')
            voltageAvailable = logical(raw.voltageAvailable);
        else
            voltageAvailable = any(isfinite(V_mpp_module_V) & V_mpp_module_V > 0);
        end

        if isfield(raw, 'tiltX')
            pvGroups(g).tiltX = raw.tiltX;
        end

        if isfield(raw, 'tiltZ')
            pvGroups(g).tiltZ = raw.tiltZ;
        end

        pvGroups(g).Pdc_ref_kWp = Pdc_ref_kWp;
        pvGroups(g).Pdc_scaled_kWp = Pdc_target_kWp;
        pvGroups(g).Pdc_installed_kWp = Pdc_installed_kWp;

        pvGroups(g).modulePower_kWp = modulePower_kWp;

        pvGroups(g).Ns = Ns;
        pvGroups(g).Np = Np;
        pvGroups(g).N_modules = N_modules;

        if isfield(raw, 'N_modules_ref') && ~isempty(raw.N_modules_ref)
            pvGroups(g).N_modules_ref = raw.N_modules_ref;
        else
            pvGroups(g).N_modules_ref = Pdc_ref_kWp / modulePower_kWp;
        end

        pvGroups(g).P_string_stc_kWp = P_string_stc_kWp;

        pvGroups(g).P_module_W = P_module_W;
        pvGroups(g).V_mpp_module_V = V_mpp_module_V;
        pvGroups(g).V_string_mpp_V = V_string_mpp_V;

        pvGroups(g).P_orientation_ref_kW = P_orientation_ref_kW;
        pvGroups(g).P_orientation_available_kW = P_orientation_available_kW;
        pvGroups(g).P_mppt_in_kW = P_orientation_available_kW;

        pvGroups(g).scaleFactor = scaleFactor;
        pvGroups(g).stringScaleFactor = stringScaleFactor;

        pvGroups(g).voltageAvailable = voltageAvailable;
    end
end


function scaleFactor = local_get_reference_scale_factor(dayInput, design, cfg)

    P_ref_kWp = [];

    if isfield(dayInput, 'pvGroups') && ~isempty(dayInput.pvGroups)

        P_ref_kWp = 0;

        for g = 1:numel(dayInput.pvGroups)
            if isfield(dayInput.pvGroups(g), 'Pdc_ref_kWp') && ...
                    ~isempty(dayInput.pvGroups(g).Pdc_ref_kWp) && ...
                    isfinite(dayInput.pvGroups(g).Pdc_ref_kWp)

                P_ref_kWp = P_ref_kWp + dayInput.pvGroups(g).Pdc_ref_kWp;
            end
        end
    end

    if isempty(P_ref_kWp) || P_ref_kWp <= 0
        if isfield(cfg, 'pv') && isfield(cfg.pv, 'referencePdc_kWp')
            P_ref_kWp = sum(cfg.pv.referencePdc_kWp);
        end
    end

    if isempty(P_ref_kWp) || ~isfinite(P_ref_kWp) || P_ref_kWp <= 0
        P_ref_kWp = 1;
    end

    scaleFactor = design.P_PV_kW / P_ref_kWp;
end


function P_total_kW = local_sum_pv_group_power(pvGroups, N)

    P_total_kW = zeros(N, 1);

    for g = 1:numel(pvGroups)

        if isfield(pvGroups(g), 'P_mppt_in_kW') && ~isempty(pvGroups(g).P_mppt_in_kW)
            P = local_fit_vector(pvGroups(g).P_mppt_in_kW, N, 0);
        elseif isfield(pvGroups(g), 'P_orientation_available_kW') && ~isempty(pvGroups(g).P_orientation_available_kW)
            P = local_fit_vector(pvGroups(g).P_orientation_available_kW, N, 0);
        else
            P = zeros(N, 1);
        end

        P_total_kW = P_total_kW + P(:);
    end
end


function stringDesign = local_get_pv_string_design(cfg)

    if ~isfield(cfg, 'pv')
        error('cfg.pv is missing.');
    end

    sizingMode = "auto_voc_max";

    if isfield(cfg.pv, 'stringSizingMode') && ~isempty(cfg.pv.stringSizingMode)
        sizingMode = lower(string(cfg.pv.stringSizingMode));
    end

    Voc_STC = local_get_required_numeric_cfg(cfg, {'pv', 'moduleVoc_STC_V'});
    betaVoc = local_get_required_numeric_cfg(cfg, {'pv', 'moduleVocTempCoeff_per_C'});
    Tmin = local_get_required_numeric_cfg(cfg, {'pv', 'minCellTemp_C'});
    Vmax = local_get_pv_max_string_voltage_from_cfg(cfg);

    if Voc_STC <= 0
        error('cfg.pv.moduleVoc_STC_V must be positive.');
    end

    if Vmax <= 0
        error('PV maximum string voltage must be positive.');
    end

    VocColdModule_V = Voc_STC * (1 + betaVoc * (Tmin - 25));

    if ~isfinite(VocColdModule_V) || VocColdModule_V <= 0
        error(['Calculated cold module Voc is invalid. ', ...
               'Check cfg.pv.moduleVoc_STC_V, cfg.pv.moduleVocTempCoeff_per_C and cfg.pv.minCellTemp_C.']);
    end

    NsMaxVoc = floor(Vmax / VocColdModule_V);

    if NsMaxVoc < 1
        error(['No valid PV string length is possible. ', ...
               'Cold module Voc = %.3f V, maximum string voltage = %.3f V.'], ...
               VocColdModule_V, Vmax);
    end

    switch sizingMode

        case {"auto", "auto_voc", "auto_voc_max"}

            Ns = NsMaxVoc;

        case "manual"

            if ~isfield(cfg.pv, 'Ns') || isempty(cfg.pv.Ns) || ...
                    ~isnumeric(cfg.pv.Ns) || ~isscalar(cfg.pv.Ns) || ...
                    ~isfinite(cfg.pv.Ns) || cfg.pv.Ns <= 0

                error('Manual PV string sizing requires a valid cfg.pv.Ns.');
            end

            Ns = round(cfg.pv.Ns);

            if abs(Ns - cfg.pv.Ns) > 1e-9
                error('cfg.pv.Ns must be an integer in manual string sizing mode.');
            end

            if Ns > NsMaxVoc
                error(['Manual PV string sizing is invalid. ', ...
                       'cfg.pv.Ns = %d gives cold string Voc = %.3f V, ', ...
                       'while max allowed string voltage is %.3f V. ', ...
                       'Maximum allowed Ns from cold Voc is %d.'], ...
                       Ns, ...
                       Ns * VocColdModule_V, ...
                       Vmax, ...
                       NsMaxVoc);
            end

        otherwise

            error('Unknown cfg.pv.stringSizingMode: %s', sizingMode);
    end

    stringDesign = struct();
    stringDesign.Ns = Ns;
    stringDesign.NsMaxVoc = NsMaxVoc;
    stringDesign.VocColdModule_V = VocColdModule_V;
    stringDesign.VocColdString_V = Ns * VocColdModule_V;
    stringDesign.maxStringVoltage_V = Vmax;
    stringDesign.stringSizingMode = sizingMode;
end

function modulePower_kWp = local_get_module_power_kWp(cfg)

    if ~isfield(cfg, 'pv') || ...
            ~isfield(cfg.pv, 'modulePower_kWp') || ...
            isempty(cfg.pv.modulePower_kWp) || ...
            ~isnumeric(cfg.pv.modulePower_kWp) || ...
            ~isscalar(cfg.pv.modulePower_kWp) || ...
            ~isfinite(cfg.pv.modulePower_kWp) || ...
            cfg.pv.modulePower_kWp <= 0

        error('Missing or invalid cfg.pv.modulePower_kWp.');
    end

    modulePower_kWp = cfg.pv.modulePower_kWp;
end


function value = local_get_numeric_field(s, fieldName, defaultValue)

    value = defaultValue;

    if isfield(s, fieldName)
        candidate = s.(fieldName);

        if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end


function value = local_get_field_or_empty(s, fieldName)

    if isfield(s, fieldName)
        value = s.(fieldName);
    else
        value = [];
    end
end


function value = local_get_bool_cfg(cfg, path, defaultValue)

    value = defaultValue;

    try
        candidate = cfg;

        for k = 1:numel(path)
            candidate = candidate.(path{k});
        end

        if islogical(candidate) && isscalar(candidate)
            value = candidate;
        elseif isnumeric(candidate) && isscalar(candidate)
            value = candidate ~= 0;
        end
    catch
        value = defaultValue;
    end
end


function value = local_get_string_cfg(cfg, path, defaultValue)

    value = defaultValue;

    try
        candidate = cfg;

        for k = 1:numel(path)
            candidate = candidate.(path{k});
        end

        value = lower(string(candidate));
    catch
        value = defaultValue;
    end
end


function Np = local_round_string_count(Np_ideal, mode)

    switch lower(string(mode))

        case "floor"
            Np = floor(Np_ideal);

        case "ceil"
            Np = ceil(Np_ideal);

        otherwise
            Np = round(Np_ideal);
    end
end


function y = local_fit_vector(x, N, fillValue)

    if isempty(x)
        y = fillValue * ones(N, 1);
        return;
    end

    y = x(:);

    if numel(y) >= N
        y = y(1:N);
    else
        if isempty(y)
            lastValue = fillValue;
        else
            lastValue = y(end);
        end

        y(end+1:N, 1) = lastValue;
    end
end



function value = local_get_required_numeric_cfg(cfg, path)

    candidate = cfg;

    for k = 1:numel(path)

        fieldName = path{k};

        if ~isstruct(candidate) || ~isfield(candidate, fieldName)
            error('Missing configuration field: cfg.%s', strjoin(path, '.'));
        end

        candidate = candidate.(fieldName);
    end

    if isempty(candidate) || ~isnumeric(candidate) || ~isscalar(candidate) || ~isfinite(candidate)
        error('Invalid numeric configuration field: cfg.%s', strjoin(path, '.'));
    end

    value = candidate;
end

function Vmax = local_get_pv_max_string_voltage_from_cfg(cfg)

    usePvMpptDcdc = true;

    if isfield(cfg, 'mpptDcdc') && isfield(cfg.mpptDcdc, 'enabled')
        usePvMpptDcdc = logical(cfg.mpptDcdc.enabled);
    end

    Vmax = [];

    % Explicit PV string design limit has highest priority.
    if isfield(cfg, 'pv') && isfield(cfg.pv, 'maxStringVoltage_V') && ...
            ~isempty(cfg.pv.maxStringVoltage_V)

        Vmax = cfg.pv.maxStringVoltage_V;
    end

    % If PV-side MPPT DC/DC is used, the string is connected to the MPPT
    % converter input, therefore its input voltage window is relevant.
    if isempty(Vmax) && usePvMpptDcdc && ...
            isfield(cfg, 'mpptDcdc') && isfield(cfg.mpptDcdc, 'VinMax_V')

        Vmax = cfg.mpptDcdc.VinMax_V;
    end

    % If PV-direct mode is used, the string is connected to the inverter/DC bus.
    if isempty(Vmax) && ~usePvMpptDcdc && ...
            isfield(cfg, 'inverter') && isfield(cfg.inverter, 'VdcMax_V')

        Vmax = cfg.inverter.VdcMax_V;
    end

    % Generic DC bus maximum, if defined.
    if isempty(Vmax) && isfield(cfg, 'dcBus') && isfield(cfg.dcBus, 'V_max_V')
        Vmax = cfg.dcBus.V_max_V;
    end

    if isempty(Vmax) || ~isnumeric(Vmax) || ~isscalar(Vmax) || ...
            ~isfinite(Vmax) || Vmax <= 0

        error(['Missing or invalid maximum PV string voltage. ', ...
               'Set cfg.pv.maxStringVoltage_V, or define the relevant ', ...
               'cfg.mpptDcdc.VinMax_V / cfg.inverter.VdcMax_V limit.']);
    end
end