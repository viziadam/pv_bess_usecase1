function [out, pvGroupsOut] = mppt_dcdc_converter_model(pvGroupsIn, V_dc_link_V, pars, dt_h)
% MPPT_DCDC_CONVERTER_MODEL
%
% Orientation-specific averaged MPPT DC/DC converter model.
%
% Efficiency model:
%   eta_total = eta_load(P/P_rated) * eta_voltage(Uin/Uout)
%
% For PV MPPT DC/DC:
%   Uin  = V_string_mpp
%   Uout = V_dc_link
%
% Main assumptions:
%   - Each pvGroupsIn(g) is an independent MPPT group.
%   - Different PV orientations are not mixed.
%   - The converter keeps the PV group at its MPP voltage.
%   - The output side is the regulated common DC-link.

    if nargin < 3 || isempty(pars)
        pars = struct();
    end

    if nargin < 4 || isempty(dt_h)
        dt_h = 1;
    end

    if isempty(pvGroupsIn)
        out = local_empty_output(0, dt_h);
        pvGroupsOut = pvGroupsIn;
        return;
    end

    N = local_detect_length(pvGroupsIn);

    V_dc_link_V = local_fit_vector(V_dc_link_V, N, 1000);

    pars = local_apply_default_pars(pars);

    nG = numel(pvGroupsIn);

    groupTemplate = struct( ...
        'tiltX', [], ...
        'tiltZ', [], ...
        'P_rated_kW', [], ...
        'P_mpp_in_kW', [], ...
        'P_input_limited_kW', [], ...
        'P_dc_link_kW', [], ...
        'P_loss_kW', [], ...
        'P_clipped_kW', [], ...
        'V_in_V', [], ...
        'V_out_V', [], ...
        'voltageRatio', [], ...
        'loadFraction', [], ...
        'etaLoad', [], ...
        'etaVoltage', [], ...
        'etaTotal', [], ...
        'I_in_A', [], ...
        'I_out_A', [], ...
        'voltage_ok', [], ...
        'current_ok', []);

    groups = repmat(groupTemplate, 1, nG);
    pvGroupsOut = pvGroupsIn;

    P_mpp_total_kW = zeros(N, 1);
    P_input_limited_total_kW = zeros(N, 1);
    P_dc_link_total_kW = zeros(N, 1);
    P_loss_total_kW = zeros(N, 1);
    P_clipped_total_kW = zeros(N, 1);

    for g = 1:nG

        raw = pvGroupsIn(g);

        P_mpp_in_kW = local_get_group_power(raw, N);
        V_in_V = local_get_group_voltage(raw, N);
        V_out_V = V_dc_link_V;

        P_mpp_in_kW = max(0, P_mpp_in_kW);

        P_rated_kW = local_get_group_rated_power(raw, P_mpp_in_kW);

        voltageRatio = V_in_V ./ max(V_out_V, eps);

        voltage_ok = ...
            isfinite(V_in_V) & ...
            isfinite(V_out_V) & ...
            V_in_V > 0 & ...
            V_out_V > 0 & ...
            V_in_V >= pars.VinMin_V & ...
            V_in_V <= pars.VinMax_V & ...
            V_out_V >= pars.VoutMin_V & ...
            V_out_V <= pars.VoutMax_V & ...
            voltageRatio >= pars.ratioMin & ...
            voltageRatio <= pars.ratioMax;

        P_limited_kW = min(P_mpp_in_kW, P_rated_kW);

        P_by_iin_kW = V_in_V .* pars.IinMax_A / 1000;
        P_by_iout_kW = V_out_V .* pars.IoutMax_A / 1000;

        P_limited_kW = min(P_limited_kW, P_by_iin_kW);
        P_limited_kW = min(P_limited_kW, P_by_iout_kW);

        P_limited_kW(~voltage_ok) = 0;
        P_limited_kW = max(0, P_limited_kW);

        loadFraction = P_limited_kW ./ max(P_rated_kW, eps);
        loadFraction = min(max(loadFraction, 0), 1);

        etaLoad = local_interp_curve( ...
            pars.loadFractionCurve, ...
            pars.etaLoadCurve, ...
            loadFraction);

        etaVoltage = local_interp_curve( ...
            pars.voltageRatioCurve, ...
            pars.etaVoltageCurve, ...
            voltageRatio);

        etaTotal = etaLoad .* etaVoltage;
        etaTotal = min(max(etaTotal, pars.etaMin), pars.etaMax);
        etaTotal(P_limited_kW <= 1e-12) = 0;

        P_dc_link_kW = etaTotal .* P_limited_kW;
        P_loss_kW = max(P_limited_kW - P_dc_link_kW, 0);
        P_clipped_kW = max(P_mpp_in_kW - P_limited_kW, 0);

        I_in_A = zeros(N, 1);
        idxIn = V_in_V > 0;
        I_in_A(idxIn) = P_limited_kW(idxIn) * 1000 ./ V_in_V(idxIn);

        I_out_A = zeros(N, 1);
        idxOut = V_out_V > 0;
        I_out_A(idxOut) = P_dc_link_kW(idxOut) * 1000 ./ V_out_V(idxOut);

        current_ok = ...
            I_in_A <= pars.IinMax_A & ...
            I_out_A <= pars.IoutMax_A;

        groups(g).tiltX = local_get_optional_field(raw, 'tiltX', []);
        groups(g).tiltZ = local_get_optional_field(raw, 'tiltZ', []);

        groups(g).P_rated_kW = P_rated_kW;
        groups(g).P_mpp_in_kW = P_mpp_in_kW;
        groups(g).P_input_limited_kW = P_limited_kW;
        groups(g).P_dc_link_kW = P_dc_link_kW;
        groups(g).P_loss_kW = P_loss_kW;
        groups(g).P_clipped_kW = P_clipped_kW;

        groups(g).V_in_V = V_in_V;
        groups(g).V_out_V = V_out_V;
        groups(g).voltageRatio = voltageRatio;
        groups(g).loadFraction = loadFraction;

        groups(g).etaLoad = etaLoad;
        groups(g).etaVoltage = etaVoltage;
        groups(g).etaTotal = etaTotal;

        groups(g).I_in_A = I_in_A;
        groups(g).I_out_A = I_out_A;

        groups(g).voltage_ok = voltage_ok;
        groups(g).current_ok = current_ok;

        pvGroupsOut(g).P_mppt_in_kW = P_mpp_in_kW;
        pvGroupsOut(g).P_mppt_limited_kW = P_limited_kW;
        pvGroupsOut(g).P_mppt_to_dc_link_kW = P_dc_link_kW;
        pvGroupsOut(g).P_mppt_loss_kW = P_loss_kW;
        pvGroupsOut(g).P_mppt_clipped_kW = P_clipped_kW;

        pvGroupsOut(g).mppt_eta_load = etaLoad;
        pvGroupsOut(g).mppt_eta_voltage = etaVoltage;
        pvGroupsOut(g).mppt_eta_total = etaTotal;

        pvGroupsOut(g).mppt_voltage_ratio = voltageRatio;
        pvGroupsOut(g).mppt_voltage_ok = voltage_ok;
        pvGroupsOut(g).mppt_current_ok = current_ok;

        P_mpp_total_kW = P_mpp_total_kW + P_mpp_in_kW;
        P_input_limited_total_kW = P_input_limited_total_kW + P_limited_kW;
        P_dc_link_total_kW = P_dc_link_total_kW + P_dc_link_kW;
        P_loss_total_kW = P_loss_total_kW + P_loss_kW;
        P_clipped_total_kW = P_clipped_total_kW + P_clipped_kW;
    end

    out = struct();

    out.P_mpp_total_kW = P_mpp_total_kW;
    out.P_input_limited_total_kW = P_input_limited_total_kW;
    out.P_dc_link_total_kW = P_dc_link_total_kW;
    out.P_loss_total_kW = P_loss_total_kW;
    out.P_clipped_total_kW = P_clipped_total_kW;

    out.E_mpp_total_kWh = P_mpp_total_kW * dt_h;
    out.E_dc_link_total_kWh = P_dc_link_total_kW * dt_h;
    out.E_loss_total_kWh = P_loss_total_kW * dt_h;
    out.E_clipped_total_kWh = P_clipped_total_kW * dt_h;

    out.groups = groups;
end


function pars = local_apply_default_pars(pars)

    pars = local_set_default(pars, 'loadFractionCurve', ...
        [0.00 0.01 0.02 0.05 0.10 0.20 0.50 0.75 1.00]);

    pars = local_set_default(pars, 'etaLoadCurve', ...
        [0.00 0.80 0.90 0.94 0.960 0.972 0.982 0.985 0.980]);

    pars = local_set_default(pars, 'voltageRatioCurve', ...
        [0.35 0.50 0.65 0.80 0.90 1.00 1.10 1.25 1.50 2.00 2.50 3.00]);

    pars = local_set_default(pars, 'etaVoltageCurve', ...
        [0.955 0.970 0.982 0.992 0.997 1.000 0.997 0.993 0.985 0.972 0.960 0.950]);

    pars = local_set_default(pars, 'etaMin', 0.00);
    pars = local_set_default(pars, 'etaMax', 0.985);

    pars = local_set_default(pars, 'etaMin', 0.00);
    pars = local_set_default(pars, 'etaMax', 0.985);

    pars = local_set_default(pars, 'VinMin_V', 100);
    pars = local_set_default(pars, 'VinMax_V', 1500);

    pars = local_set_default(pars, 'VoutMin_V', 500);
    pars = local_set_default(pars, 'VoutMax_V', 1000);

    pars = local_set_default(pars, 'IinMax_A', inf);
    pars = local_set_default(pars, 'IoutMax_A', inf);

    pars = local_set_default(pars, 'ratioMin', min(pars.voltageRatioCurve));
    pars = local_set_default(pars, 'ratioMax', max(pars.voltageRatioCurve));
end


function pars = local_set_default(pars, name, value)

    if ~isfield(pars, name) || isempty(pars.(name))
        pars.(name) = value;
    end
end


function N = local_detect_length(pvGroups)

    N = 0;

    for g = 1:numel(pvGroups)

        if isfield(pvGroups(g), 'P_mppt_in_kW') && ~isempty(pvGroups(g).P_mppt_in_kW)
            N = numel(pvGroups(g).P_mppt_in_kW);
            return;
        end

        if isfield(pvGroups(g), 'P_orientation_available_kW') && ~isempty(pvGroups(g).P_orientation_available_kW)
            N = numel(pvGroups(g).P_orientation_available_kW);
            return;
        end

        if isfield(pvGroups(g), 'P_orientation_kW') && ~isempty(pvGroups(g).P_orientation_kW)
            N = numel(pvGroups(g).P_orientation_kW);
            return;
        end
    end

    N = 1;
end


function P = local_get_group_power(group, N)

    if isfield(group, 'P_mppt_in_kW') && ~isempty(group.P_mppt_in_kW)
        P = local_fit_vector(group.P_mppt_in_kW, N, 0);
    elseif isfield(group, 'P_orientation_available_kW') && ~isempty(group.P_orientation_available_kW)
        P = local_fit_vector(group.P_orientation_available_kW, N, 0);
    elseif isfield(group, 'P_orientation_kW') && ~isempty(group.P_orientation_kW)
        P = local_fit_vector(group.P_orientation_kW, N, 0);
    else
        P = zeros(N, 1);
    end
end


function V = local_get_group_voltage(group, N)

    if isfield(group, 'V_string_mpp_V') && ~isempty(group.V_string_mpp_V)
        V = local_fit_vector(group.V_string_mpp_V, N, NaN);
    elseif isfield(group, 'V_mpp_module_V') && ~isempty(group.V_mpp_module_V)

        if isfield(group, 'Ns') && ~isempty(group.Ns)
            Ns = group.Ns;
        else
            Ns = 24;
        end

        V = Ns * local_fit_vector(group.V_mpp_module_V, N, NaN);
    else
        V = NaN(N, 1);
    end
end


function P_rated_kW = local_get_group_rated_power(group, P_mpp_in_kW)

    if isfield(group, 'Pdc_scaled_kWp') && ~isempty(group.Pdc_scaled_kWp)
        P_rated_kW = group.Pdc_scaled_kWp;
    elseif isfield(group, 'Pdc_ref_kWp') && isfield(group, 'scaleFactor') && ...
            ~isempty(group.Pdc_ref_kWp) && ~isempty(group.scaleFactor)
        P_rated_kW = group.Pdc_ref_kWp * group.scaleFactor;
    elseif isfield(group, 'Pdc_ref_kWp') && ~isempty(group.Pdc_ref_kWp)
        P_rated_kW = group.Pdc_ref_kWp;
    else
        P_rated_kW = max(max(P_mpp_in_kW), 1);
    end

    if ~isfinite(P_rated_kW) || P_rated_kW <= 0
        P_rated_kW = max(max(P_mpp_in_kW), 1);
    end
end


function y = local_interp_curve(xCurve, yCurve, x)

    xCurve = xCurve(:);
    yCurve = yCurve(:);
    x = x(:);

    y = interp1(xCurve, yCurve, x, 'linear', 'extrap');

    yMin = min(yCurve);
    yMax = max(yCurve);

    y = min(max(y, yMin), yMax);
    y(~isfinite(y)) = 0;
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
        y(end+1:N, 1) = y(end);
    end
end


function value = local_get_optional_field(s, fieldName, defaultValue)

    if isfield(s, fieldName)
        value = s.(fieldName);
    else
        value = defaultValue;
    end
end


function out = local_empty_output(N, dt_h)

    z = zeros(N, 1);

    out = struct();
    out.P_mpp_total_kW = z;
    out.P_input_limited_total_kW = z;
    out.P_dc_link_total_kW = z;
    out.P_loss_total_kW = z;
    out.P_clipped_total_kW = z;

    out.E_mpp_total_kWh = z * dt_h;
    out.E_dc_link_total_kWh = z * dt_h;
    out.E_loss_total_kWh = z * dt_h;
    out.E_clipped_total_kWh = z * dt_h;

    out.groups = [];
end