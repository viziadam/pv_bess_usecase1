function out = inverter_model(P_input_kW, P_inv_nom_kW, dt_h, mode, cfg)
% INVERTER_MODEL
%
% Power-dependent inverter model.
%
% Modes:
%
%   mode = 'dc_to_ac'
%       P_input_kW = available DC power [kW]
%       Output: forwarded AC power, loss and clipping.
%
%   mode = 'ac_required'
%       P_input_kW = required AC power [kW]
%       Output: required DC power, available AC power, loss and clipping.
%
% Efficiency model:
%
%   cfg.inverter.efficiencyModel = "parabolic"
%
%       eta = etaMax - curvature * (loadFraction - loadOpt)^2
%
%   cfg.inverter.efficiencyModel = "curve"
%
%       eta = interp1(loadFractionCurve, etaCurve, loadFraction)
%
% Backward compatibility:
%   If cfg is missing, default parabolic parameters are used.

    if nargin < 5 || isempty(cfg)
        cfg = struct();
    end

    P_input_kW = max(P_input_kW(:), 0);

    if P_inv_nom_kW <= 0
        out = local_zero_output(size(P_input_kW));
        return;
    end

    switch lower(mode)

        case 'dc_to_ac'
            P_dc_available_kW = P_input_kW;

            loadGuess = min(P_dc_available_kW / P_inv_nom_kW, 1);
            etaGuess = local_inverter_efficiency(loadGuess, cfg);

            P_ac_raw_kW = P_dc_available_kW .* etaGuess;
            P_ac_forwarded_kW = min(P_ac_raw_kW, P_inv_nom_kW);

            loadFraction = P_ac_forwarded_kW / P_inv_nom_kW;
            eta = local_inverter_efficiency(loadFraction, cfg);

            P_dc_used_kW = P_ac_forwarded_kW ./ max(eta, eps);
            P_dc_used_kW = min(P_dc_used_kW, P_dc_available_kW);

            P_loss_kW = max(P_dc_used_kW - P_ac_forwarded_kW, 0);
            P_clipped_kW = max(P_dc_available_kW - P_dc_used_kW, 0);

            P_input_required_kW = P_dc_used_kW;

        case 'ac_required'
            P_ac_required_kW = P_input_kW;

            P_ac_forwarded_kW = min(P_ac_required_kW, P_inv_nom_kW);

            loadFraction = P_ac_forwarded_kW / P_inv_nom_kW;
            eta = local_inverter_efficiency(loadFraction, cfg);

            P_dc_required_kW = P_ac_forwarded_kW ./ max(eta, eps);

            P_loss_kW = max(P_dc_required_kW - P_ac_forwarded_kW, 0);
            P_clipped_kW = max(P_ac_required_kW - P_ac_forwarded_kW, 0);

            P_dc_used_kW = P_dc_required_kW;
            P_input_required_kW = P_dc_required_kW;

        otherwise
            error('Unknown inverter mode: %s. Use dc_to_ac or ac_required.', mode);
    end

    out = struct();

    out.P_input_used_kW = P_dc_used_kW;
    out.P_input_required_kW = P_input_required_kW;
    out.P_forwarded_kW = P_ac_forwarded_kW;
    out.P_loss_kW = P_loss_kW;
    out.P_clipped_kW = P_clipped_kW;

    out.E_forwarded_kWh = P_ac_forwarded_kW * dt_h;
    out.E_loss_kWh = P_loss_kW * dt_h;
    out.E_clipped_kWh = P_clipped_kW * dt_h;

    out.eta = eta;
    out.loadFraction = loadFraction;
end


function eta = local_inverter_efficiency(loadFraction, cfg)

    loadFraction = min(max(loadFraction, 0), 1);

    pars = local_get_inverter_pars(cfg);

    switch pars.efficiencyModel

        case "parabolic"

            eta = pars.etaMax - pars.curvature .* ...
                (loadFraction - pars.loadOpt).^2;

            eta = min(max(eta, pars.etaMin), pars.etaMax);

            eta(loadFraction <= pars.minActiveLoadFraction) = 1;

        case "curve"

            eta = interp1( ...
                pars.loadFractionCurve, ...
                pars.etaCurve, ...
                loadFraction, ...
                'linear', ...
                'extrap');

            eta = min(max(eta, pars.etaMin), pars.etaMax);

            eta(loadFraction <= pars.minActiveLoadFraction) = 1;

        otherwise
            error('Unknown inverter efficiency model: %s', pars.efficiencyModel);
    end
end


function pars = local_get_inverter_pars(cfg)

    inv = struct();

    if isfield(cfg, 'inverter')
        inv = cfg.inverter;
    end

    pars = struct();

    pars.efficiencyModel = local_get_string(inv, 'efficiencyModel', "parabolic");

    pars.etaMax = local_get_numeric(inv, 'etaMax', 0.985);
    pars.etaMin = local_get_numeric(inv, 'etaMin', 0.80);

    pars.loadOpt = local_get_numeric(inv, 'loadOpt', 0.55);
    pars.curvature = local_get_numeric(inv, 'curvature', 0.09);

    pars.minActiveLoadFraction = local_get_numeric(inv, 'minActiveLoadFraction', 1e-6);

    pars.loadFractionCurve = local_get_vector(inv, ...
        'loadFractionCurve', ...
        [0.00 0.05 0.10 0.20 0.50 0.75 1.00]);

    pars.etaCurve = local_get_vector(inv, ...
        'etaCurve', ...
        [0.00 0.88 0.92 0.95 0.970 0.965 0.955]);
end


function value = local_get_numeric(s, fieldName, defaultValue)

    value = defaultValue;

    if isfield(s, fieldName)
        candidate = s.(fieldName);

        if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end


function value = local_get_string(s, fieldName, defaultValue)

    value = defaultValue;

    if isfield(s, fieldName)
        value = lower(string(s.(fieldName)));
    end
end


function value = local_get_vector(s, fieldName, defaultValue)

    value = defaultValue;

    if isfield(s, fieldName)
        candidate = s.(fieldName);

        if isnumeric(candidate) && isvector(candidate) && ~isempty(candidate)
            value = candidate(:).';
        end
    end
end


function out = local_zero_output(sz)

    z = zeros(sz);

    out = struct();

    out.P_input_used_kW = z;
    out.P_input_required_kW = z;
    out.P_forwarded_kW = z;
    out.P_loss_kW = z;
    out.P_clipped_kW = z;

    out.E_forwarded_kWh = z;
    out.E_loss_kWh = z;
    out.E_clipped_kWh = z;

    out.eta = z;
    out.loadFraction = z;
end