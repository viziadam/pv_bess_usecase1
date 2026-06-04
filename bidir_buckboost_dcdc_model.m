function out = bidir_buckboost_dcdc_model(P_input_W, P_max_W, dt_h, mode, V_high_V, V_low_V, pars)
% BIDIR_BUCKBOOST_DCDC_MODEL
%
% Averaged bidirectional buck-boost type DC/DC converter model.
%
% High side:
%   common DC-link
%
% Low side:
%   BESS pack
%
% Sign convention:
%   P > 0  -> discharge, pack -> DC-link
%   P < 0  -> charge, DC-link -> pack
%
% Efficiency model:
%   eta_total = eta_load(P/P_rated) * eta_voltage(Uin/Uout)
%
% Directional voltage ratio:
%   discharge:
%       Uin  = V_low
%       Uout = V_high
%
%   charge:
%       Uin  = V_high
%       Uout = V_low
%
% Modes:
%   mode = 'dc_to_pack'
%       Input is requested high-side power.
%       Output is requested pack-side power.
%
%   mode = 'pack_to_dc'
%       Input is actual pack-side power.
%       Output is actual high-side power.

    if nargin < 7 || isempty(pars)
        pars = struct();
    end

    pars = local_apply_default_pars(pars);

    P_input_W = P_input_W(:).';
    N = numel(P_input_W);

    V_high_V = local_fit_vector(V_high_V, N, pars.VhighNom_V).';
    V_low_V = local_fit_vector(V_low_V, N, pars.VlowNom_V).';

    P_max_W = abs(P_max_W);

    if P_max_W <= 0 || ~isfinite(P_max_W)
        out = local_zero_output(P_input_W, dt_h);
        out.P_clipped_W = abs(P_input_W);
        out.E_clipped_kWh = abs(P_input_W) * dt_h / 1000;
        return;
    end

    voltage_ok_basic = ...
        isfinite(V_high_V) & ...
        isfinite(V_low_V) & ...
        V_high_V > 0 & ...
        V_low_V > 0 & ...
        V_high_V >= pars.VhighMin_V & ...
        V_high_V <= pars.VhighMax_V & ...
        V_low_V >= pars.VlowMin_V & ...
        V_low_V <= pars.VlowMax_V;

    % Directional Uin/Uout ratio.
    %
    % P > 0:
    %   discharge, pack -> DC-link:
    %       Uin/Uout = V_low / V_high
    %
    % P < 0:
    %   charge, DC-link -> pack:
    %       Uin/Uout = V_high / V_low
    voltageRatio = ones(1, N);

    maskDis = P_input_W > 0;
    maskChg = P_input_W < 0;

    voltageRatio(maskDis) = V_low_V(maskDis) ./ max(V_high_V(maskDis), eps);
    voltageRatio(maskChg) = V_high_V(maskChg) ./ max(V_low_V(maskChg), eps);

    ratio_ok = ...
        voltageRatio >= pars.ratioMin & ...
        voltageRatio <= pars.ratioMax;

    voltage_ok = voltage_ok_basic & ratio_ok;

    P_abs_max_by_power_W = P_max_W * ones(1, N);
    P_abs_max_by_high_current_W = V_high_V .* pars.IhighMax_A;
    P_abs_max_by_low_current_W = V_low_V .* pars.IlowMax_A;

    P_abs_limit_W = min(P_abs_max_by_power_W, P_abs_max_by_high_current_W);
    P_abs_limit_W = min(P_abs_limit_W, P_abs_max_by_low_current_W);

    P_abs_limit_W(~voltage_ok) = 0;
    P_abs_limit_W = max(0, P_abs_limit_W);

    P_input_clipped_W = sign(P_input_W) .* min(abs(P_input_W), P_abs_limit_W);

    loadFraction = abs(P_input_clipped_W) ./ max(P_max_W, eps);
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

    etaTotal(maskChg) = etaTotal(maskChg) .* pars.etaChargeFactor;
    etaTotal(maskDis) = etaTotal(maskDis) .* pars.etaDischargeFactor;

    etaTotal = min(max(etaTotal, pars.etaMin), pars.etaMax);
    etaTotal(abs(P_input_clipped_W) <= 1e-12) = 0;

    P_output_W = zeros(size(P_input_W));

    switch lower(mode)

        case 'dc_to_pack'
            % Input:
            %   high-side requested power.
            %
            % Output:
            %   pack-side requested power.

            mask_chg = P_input_clipped_W < 0;
            mask_dis = P_input_clipped_W > 0;

            % Charge:
            %   DC-link supplies power, pack receives less.
            P_output_W(mask_chg) = P_input_clipped_W(mask_chg) .* etaTotal(mask_chg);

            % Discharge:
            %   required high-side power, pack must provide more.
            P_output_W(mask_dis) = P_input_clipped_W(mask_dis) ./ max(etaTotal(mask_dis), eps);

        case 'pack_to_dc'
            % Input:
            %   actual pack-side power.
            %
            % Output:
            %   actual high-side power.

            mask_chg = P_input_clipped_W < 0;
            mask_dis = P_input_clipped_W > 0;

            % Charge:
            %   if this much enters the pack, DC-link supplied more.
            P_output_W(mask_chg) = P_input_clipped_W(mask_chg) ./ max(etaTotal(mask_chg), eps);

            % Discharge:
            %   pack supplies power, DC-link receives less.
            P_output_W(mask_dis) = P_input_clipped_W(mask_dis) .* etaTotal(mask_dis);

        otherwise
            error('Unknown bidirectional DC/DC mode: %s. Use dc_to_pack or pack_to_dc.', mode);
    end

    P_loss_W = abs(abs(P_output_W) - abs(P_input_clipped_W));
    P_clipped_W = abs(P_input_W - P_input_clipped_W);

    I_high_A = zeros(size(P_input_W));
    I_low_A = zeros(size(P_input_W));

    idxHigh = V_high_V > 0;
    idxLow = V_low_V > 0;

    switch lower(mode)

        case 'dc_to_pack'
            I_high_A(idxHigh) = abs(P_input_clipped_W(idxHigh)) ./ V_high_V(idxHigh);
            I_low_A(idxLow) = abs(P_output_W(idxLow)) ./ V_low_V(idxLow);

        case 'pack_to_dc'
            I_low_A(idxLow) = abs(P_input_clipped_W(idxLow)) ./ V_low_V(idxLow);
            I_high_A(idxHigh) = abs(P_output_W(idxHigh)) ./ V_high_V(idxHigh);
    end

    current_ok = ...
        I_high_A <= pars.IhighMax_A & ...
        I_low_A <= pars.IlowMax_A;

    eta_effective = zeros(size(P_input_W));
    active = abs(P_input_clipped_W) > 1e-9;

    eta_effective(active) = ...
        min(abs(P_input_clipped_W(active)), abs(P_output_W(active))) ./ ...
        max(abs(P_input_clipped_W(active)), abs(P_output_W(active)));

    out = struct();

    out.P_input_W = P_input_W;
    out.P_input_clipped_W = P_input_clipped_W;
    out.P_output_W = P_output_W;
    out.P_loss_W = P_loss_W;
    out.P_clipped_W = P_clipped_W;

    out.E_input_kWh = abs(P_input_clipped_W) * dt_h / 1000;
    out.E_output_kWh = abs(P_output_W) * dt_h / 1000;
    out.E_loss_kWh = P_loss_W * dt_h / 1000;
    out.E_clipped_kWh = P_clipped_W * dt_h / 1000;

    out.V_high_V = V_high_V;
    out.V_low_V = V_low_V;
    out.voltageRatio = voltageRatio;
    out.loadFraction = loadFraction;

    out.etaLoad = etaLoad;
    out.etaVoltage = etaVoltage;
    out.etaTotal = etaTotal;
    out.eta_effective = eta_effective;

    out.I_high_A = I_high_A;
    out.I_low_A = I_low_A;

    out.voltage_ok = voltage_ok;
    out.current_ok = current_ok;
end


function pars = local_apply_default_pars(pars)

    pars = local_set_default(pars, 'loadFractionCurve', ...
        [0.00 0.05 0.10 0.20 0.50 0.75 1.00]);

    pars = local_set_default(pars, 'etaLoadCurve', ...
        [0.00 0.82 0.88 0.93 0.965 0.972 0.970]);

    pars = local_set_default(pars, 'voltageRatioCurve', ...
        [0.35 0.50 0.65 0.80 1.00 1.25 1.50 2.00 2.50 3.00]);

    pars = local_set_default(pars, 'etaVoltageCurve', ...
        [0.920 0.940 0.955 0.965 0.975 0.970 0.962 0.950 0.935 0.920]);

    pars = local_set_default(pars, 'etaMin', 0.00);
    pars = local_set_default(pars, 'etaMax', 0.975);

    pars = local_set_default(pars, 'etaChargeFactor', 0.995);
    pars = local_set_default(pars, 'etaDischargeFactor', 1.000);

    pars = local_set_default(pars, 'VhighNom_V', 1000);
    pars = local_set_default(pars, 'VlowNom_V', 700);

    pars = local_set_default(pars, 'VhighMin_V', 0);
    pars = local_set_default(pars, 'VhighMax_V', inf);
    pars = local_set_default(pars, 'VlowMin_V', 0);
    pars = local_set_default(pars, 'VlowMax_V', inf);

    pars = local_set_default(pars, 'IhighMax_A', inf);
    pars = local_set_default(pars, 'IlowMax_A', inf);

    pars = local_set_default(pars, 'ratioMin', min(pars.voltageRatioCurve));
    pars = local_set_default(pars, 'ratioMax', max(pars.voltageRatioCurve));
end


function pars = local_set_default(pars, name, value)

    if ~isfield(pars, name) || isempty(pars.(name))
        pars.(name) = value;
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

    y = y(:).';
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


function out = local_zero_output(P_input_W, dt_h)

    z = zeros(size(P_input_W));

    out = struct();

    out.P_input_W = P_input_W;
    out.P_input_clipped_W = z;
    out.P_output_W = z;
    out.P_loss_W = z;
    out.P_clipped_W = z;

    out.E_input_kWh = z;
    out.E_output_kWh = z;
    out.E_loss_kWh = z;
    out.E_clipped_kWh = abs(P_input_W) * dt_h / 1000;

    out.V_high_V = z;
    out.V_low_V = z;
    out.voltageRatio = z;
    out.loadFraction = z;

    out.etaLoad = z;
    out.etaVoltage = z;
    out.etaTotal = z;
    out.eta_effective = z;

    out.I_high_A = z;
    out.I_low_A = z;

    out.voltage_ok = false(size(P_input_W));
    out.current_ok = false(size(P_input_W));
end