function [step, stateEnd] = dccoupled_energy_strategy_vector(P_pv_dc_kW, P_load_ac_kW, design, stateStart, dt_h, T_amb_C, cfg, pvGroups)
% DCCOUPLED_ENERGY_STRATEGY_VECTOR
%
% DC-coupled PV+BESS energy-flow strategy for grid-connected
% self-consumption analysis without grid export.
%
% Topology:
%
%   PV group 1 -> MPPT DC/DC --+
%   PV group 2 -> MPPT DC/DC --+--> common regulated DC-link --> inverter --> AC load
%   PV group n -> MPPT DC/DC --+
%                                      |
%                                      +--> bidirectional buck-boost DC/DC <-> BESS pack
%
% Control interpretation:
%   - PV MPPT DC/DC converters regulate their own PV input voltage to MPP.
%   - The common DC-link voltage is treated as a regulated reference.
%   - The DC-link reference can be fixed or automatically selected.
%   - The BESS DC/DC converter follows the EMS charge/discharge power request.
%   - The inverter supplies the AC load up to its rated power.
%
% Sign convention for BESS high-side power:
%   positive -> BESS discharges to DC-link
%   negative -> DC-link charges BESS

    % ---------------------------------------------------------------------
    % 1) Input formatting
    % ---------------------------------------------------------------------
    P_pv_dc_kW = P_pv_dc_kW(:);
    P_load_ac_kW = P_load_ac_kW(:);

    N = min(numel(P_pv_dc_kW), numel(P_load_ac_kW));

    P_pv_dc_kW = max(0, P_pv_dc_kW(1:N));
    P_load_ac_kW = max(0, P_load_ac_kW(1:N));

    if nargin < 6 || isempty(T_amb_C)
        T_vec = 25 * ones(1, N);
    else
        T_vec = T_amb_C(:).';
        T_vec = T_vec(1:min(numel(T_vec), N));

        if numel(T_vec) < N
            T_vec(end+1:N) = T_vec(end);
        end
    end

    if nargin < 7 || isempty(cfg)
        cfg = struct();
    end

    if nargin < 8
        pvGroups = [];
    end

    if ~isfield(stateStart, 'bess_state') || isempty(stateStart.bess_state)
        error('dccoupled_energy_strategy_vector: stateStart.bess_state is missing.');
    end

    bess_state = stateStart.bess_state;

    P_inv_nom_kW = design.P_inv_kW;
    P_bess_nom_kW = design.P_BESS_kW;

    V_pack_pre_V = local_estimate_pack_voltage_before_step(bess_state, cfg, N);

    V_dc_link_V = local_get_dc_link_voltage( ...
        cfg, ...
        design, ...
        N, ...
        pvGroups, ...
        V_pack_pre_V);

    % ---------------------------------------------------------------------
    % 2) PV MPPT DC/DC conversion to common DC-link
    % ---------------------------------------------------------------------
    if isempty(pvGroups)

        % Fallback:
        % If no orientation-specific MPPT groups are available, keep the old
        % behavior: PV MPP power is directly available on the DC-link.
        P_pv_mpp_total_kW = P_pv_dc_kW;
        P_pv_dc_link_kW = P_pv_dc_kW;

        P_pv_dcdc_conversion_loss_kW = zeros(N, 1);
        P_pv_dcdc_power_clipped_kW = zeros(N, 1);
        P_pv_mppt_balance_error_kW = zeros(N, 1);

        pvDcdc = struct();
        pvDcdc.groups = [];

    else

        mpptPars = local_get_mppt_dcdc_pars(cfg);

        [pvDcdc, pvGroups] = mppt_dcdc_converter_model( ...
            pvGroups, ...
            V_dc_link_V, ...
            mpptPars, ...
            dt_h);

        P_pv_mpp_total_kW = pvDcdc.P_mpp_total_kW(:);
        P_pv_dc_link_kW = pvDcdc.P_dc_link_total_kW(:);

        P_pv_dcdc_conversion_loss_kW = pvDcdc.P_loss_total_kW(:);
        P_pv_dcdc_power_clipped_kW = pvDcdc.P_clipped_total_kW(:);

        P_pv_mppt_balance_error_kW = P_pv_dc_kW - P_pv_mpp_total_kW;
    end

    % ---------------------------------------------------------------------
    % 3) AC load required -> DC inverter input required
    % ---------------------------------------------------------------------
    P_ac_required_from_inv_kW = min(P_load_ac_kW, P_inv_nom_kW);

    inv_req = inverter_model( ...
        P_ac_required_from_inv_kW, ...
        P_inv_nom_kW, ...
        dt_h, ...
        'ac_required', ...
        cfg);

    P_dc_required_at_inv_kW = inv_req.P_input_required_kW(:);

    % ---------------------------------------------------------------------
    % 4) PV on common DC-link
    % ---------------------------------------------------------------------
    P_pv_dc_to_inv_kW = min(P_pv_dc_link_kW, P_dc_required_at_inv_kW);

    P_dc_deficit_kW = max(P_dc_required_at_inv_kW - P_pv_dc_to_inv_kW, 0);
    P_pv_surplus_kW = max(P_pv_dc_link_kW - P_pv_dc_to_inv_kW, 0);

    % ---------------------------------------------------------------------
    % 5) BESS DC/DC high-side request
    % ---------------------------------------------------------------------
    P_bess_high_req_kW = zeros(N, 1);

    maskCharge = P_pv_surplus_kW > 1e-9;
    maskDischg = P_dc_deficit_kW > 1e-9 & ~maskCharge;

    % PV surplus -> BESS charge
    P_bess_high_req_kW(maskCharge) = -min( ...
        P_pv_surplus_kW(maskCharge), ...
        P_bess_nom_kW);

    % PV deficit -> BESS discharge
    P_bess_high_req_kW(maskDischg) = min( ...
        P_dc_deficit_kW(maskDischg), ...
        P_bess_nom_kW);

    % ---------------------------------------------------------------------
    % 6) BESS DC/DC request conversion: DC-link side -> pack side
    % ---------------------------------------------------------------------
    bessDcdcPars = local_get_bess_dcdc_pars(cfg);

    dcdc_req = bidir_buckboost_dcdc_model( ...
        P_bess_high_req_kW(:).' * 1000, ...
        P_bess_nom_kW * 1000, ...
        dt_h, ...
        'dc_to_pack', ...
        V_dc_link_V(:).', ...
        V_pack_pre_V(:).', ...
        bessDcdcPars);

    P_pack_req_W = dcdc_req.P_output_W(:).';

    % ---------------------------------------------------------------------
    % 7) BESS pack model
    % ---------------------------------------------------------------------
    pack_params = struct();
    pack_params.target_energy_kWh = design.E_BESS_kWh;
    pack_params.max_power_W = P_bess_nom_kW * 1000;
    pack_params.T_vec = T_vec;

    [pack_out, bess_state] = bess_pack_model( ...
        P_pack_req_W, ...
        'run', ...
        pack_params, ...
        dt_h, ...
        bess_state);

    % Pack actual power:
    %   positive = discharge from pack
    %   negative = charge into pack
    P_pack_actual_W = ...
        (pack_out.E_discharged(:) - pack_out.E_stored(:)) / max(dt_h, eps);

    if isfield(pack_out, 'V_pack')
        V_pack_actual_V = pack_out.V_pack(:);
    else
        V_pack_actual_V = V_pack_pre_V(:);
    end

    % ---------------------------------------------------------------------
    % 8) BESS DC/DC actual conversion: pack side -> DC-link side
    % ---------------------------------------------------------------------
    dcdc_actual = bidir_buckboost_dcdc_model( ...
        P_pack_actual_W(:).' , ...
        P_bess_nom_kW * 1000, ...
        dt_h, ...
        'pack_to_dc', ...
        V_dc_link_V(:).', ...
        V_pack_actual_V(:).', ...
        bessDcdcPars);

    P_bess_high_actual_kW = dcdc_actual.P_output_W(:) / 1000;

    % Actual DC-side BESS flows
    P_pv_to_bess_kW = min( ...
        max(-P_bess_high_actual_kW, 0), ...
        P_pv_surplus_kW);

    P_bess_dc_to_inv_kW = min( ...
        max(P_bess_high_actual_kW, 0), ...
        P_dc_deficit_kW);

    % ---------------------------------------------------------------------
    % 9) Common inverter input
    % ---------------------------------------------------------------------
    P_inv_dc_input_total_kW = ...
        P_pv_dc_to_inv_kW + ...
        P_bess_dc_to_inv_kW;

    inv_total = inverter_model( ...
        P_inv_dc_input_total_kW, ...
        P_inv_nom_kW, ...
        dt_h, ...
        'dc_to_ac', ...
        cfg);

    P_inv_ac_output_kW = min(inv_total.P_forwarded_kW(:), P_load_ac_kW);

    % ---------------------------------------------------------------------
    % 10) PV/BESS useful AC output allocation
    % ---------------------------------------------------------------------
    totalInvInput_kW = P_inv_dc_input_total_kW;

    pvShare = zeros(N, 1);
    bessShare = zeros(N, 1);

    activeInv = totalInvInput_kW > 1e-9;

    pvShare(activeInv) = ...
        P_pv_dc_to_inv_kW(activeInv) ./ totalInvInput_kW(activeInv);

    bessShare(activeInv) = ...
        P_bess_dc_to_inv_kW(activeInv) ./ totalInvInput_kW(activeInv);

    P_pv_to_load_kW = P_inv_ac_output_kW .* pvShare;
    P_bess_to_load_kW = P_inv_ac_output_kW .* bessShare;

    % ---------------------------------------------------------------------
    % 11) Grid import/export
    % ---------------------------------------------------------------------
    P_grid_import_kW = max( ...
        P_load_ac_kW - P_pv_to_load_kW - P_bess_to_load_kW, ...
        0);

    % No export in this application.
    P_grid_export_kW = zeros(N, 1);

    % ---------------------------------------------------------------------
    % 12) Inverter losses and clipping
    % ---------------------------------------------------------------------
    P_inv_conversion_loss_kW = inv_total.P_loss_kW(:);
    P_inv_power_clipped_kW = inv_total.P_clipped_kW(:);

    P_inv_loss_kW = P_inv_conversion_loss_kW;

    % The common inverter loss is calculated once.
    % The PV/BESS split is only proportional accounting.
    P_inv_pv_conversion_loss_kW = P_inv_conversion_loss_kW .* pvShare;
    P_inv_bess_conversion_loss_kW = P_inv_conversion_loss_kW .* bessShare;

    P_inv_pv_clipped_kW = P_inv_power_clipped_kW .* pvShare;
    P_inv_bess_clipped_kW = P_inv_power_clipped_kW .* bessShare;

    % ---------------------------------------------------------------------
    % 13) Curtailment
    % ---------------------------------------------------------------------
    % DC-link side PV remaining after direct load supply and BESS charge.
    P_pv_curtailed_direct_kW = max( ...
        P_pv_dc_link_kW - P_pv_dc_to_inv_kW - P_pv_to_bess_kW, ...
        0);

    % Total PV curtailment-type loss:
    %   - MPPT DC/DC power clipping
    %   - unused PV surplus on DC-link
    %   - PV share of inverter clipping
    P_curtailment_kW = ...
        P_pv_dcdc_power_clipped_kW + ...
        P_pv_curtailed_direct_kW + ...
        P_inv_pv_clipped_kW;

    % ---------------------------------------------------------------------
    % 14) DC/DC losses
    % ---------------------------------------------------------------------
    P_bess_dcdc_conversion_loss_kW = dcdc_actual.P_loss_W(:) / 1000;
    P_bess_dcdc_power_clipped_kW = dcdc_req.P_clipped_W(:) / 1000;

    P_dcdc_conversion_loss_kW = ...
        P_pv_dcdc_conversion_loss_kW + ...
        P_bess_dcdc_conversion_loss_kW;

    P_dcdc_power_clipped_kW = ...
        P_pv_dcdc_power_clipped_kW + ...
        P_bess_dcdc_power_clipped_kW;

    P_dcdc_loss_kW = P_dcdc_conversion_loss_kW;

    % ---------------------------------------------------------------------
    % 15) BESS internal losses
    % ---------------------------------------------------------------------
    P_bess_cell_loss_kW = pack_out.E_loss_joule(:) / 1000 / max(dt_h, eps);

    P_bess_soc_full_loss_kW = pack_out.E_loss_sat(:) / 1000 / max(dt_h, eps);

    P_bess_soc_empty_loss_kW = pack_out.E_loss_empty(:) / 1000 / max(dt_h, eps);

    P_bess_total_internal_loss_kW = ...
        P_bess_cell_loss_kW + ...
        P_bess_soc_full_loss_kW + ...
        P_bess_soc_empty_loss_kW;

    % ---------------------------------------------------------------------
    % 16) Output step
    % ---------------------------------------------------------------------
    step = struct();

    % PV availability and PV after MPPT DC/DC
    step.P_pv_available_kW = P_pv_dc_kW;
    step.P_pv_mpp_total_kW = P_pv_mpp_total_kW;
    step.P_pv_after_mppt_dcdc_kW = P_pv_dc_link_kW;
    step.P_pv_mppt_balance_error_kW = P_pv_mppt_balance_error_kW;

    step.P_load_ac_kW = P_load_ac_kW;

    % DC bus
    step.V_dc_link_V = V_dc_link_V(:);
    step.V_pack_pre_V = V_pack_pre_V(:);
    step.V_pack_actual_V = V_pack_actual_V(:);

    % PV MPPT DC/DC
    step.pvGroups = pvGroups;
    step.pvDcdc = pvDcdc;
    step.P_pv_dcdc_conversion_loss_kW = P_pv_dcdc_conversion_loss_kW;
    step.P_pv_dcdc_power_clipped_kW = P_pv_dcdc_power_clipped_kW;

    % Main power flows
    step.P_pv_to_load_kW = P_pv_to_load_kW;
    step.P_pv_to_bess_kW = P_pv_to_bess_kW;
    step.P_bess_to_load_kW = P_bess_to_load_kW;

    step.P_grid_import_kW = P_grid_import_kW;
    step.P_grid_export_kW = P_grid_export_kW;

    step.P_curtailment_kW = P_curtailment_kW;

    step.P_inv_loss_kW = P_inv_loss_kW;
    step.P_dcdc_loss_kW = P_dcdc_loss_kW;

    % Debug / detailed power flow fields
    step.P_ac_required_from_inv_kW = P_ac_required_from_inv_kW;
    step.P_dc_required_at_inv_kW = P_dc_required_at_inv_kW;

    step.P_pv_dc_to_inv_kW = P_pv_dc_to_inv_kW;
    step.P_dc_deficit_kW = P_dc_deficit_kW;
    step.P_pv_surplus_kW = P_pv_surplus_kW;

    step.P_bess_high_req_kW = P_bess_high_req_kW;
    step.P_bess_high_actual_kW = P_bess_high_actual_kW;
    step.P_pack_req_kW = P_pack_req_W(:) / 1000;
    step.P_pack_actual_kW = P_pack_actual_W(:) / 1000;

    step.P_inv_dc_input_total_kW = P_inv_dc_input_total_kW;
    step.P_inv_ac_output_kW = P_inv_ac_output_kW;

    % Inverter losses
    step.P_inv_conversion_loss_kW = P_inv_conversion_loss_kW;
    step.P_inv_power_clipped_kW = P_inv_power_clipped_kW;

    step.P_inv_pv_conversion_loss_kW = P_inv_pv_conversion_loss_kW;
    step.P_inv_bess_conversion_loss_kW = P_inv_bess_conversion_loss_kW;

    step.P_inv_pv_clipped_kW = P_inv_pv_clipped_kW;
    step.P_inv_bess_clipped_kW = P_inv_bess_clipped_kW;

    % DC/DC losses
    step.P_dcdc_conversion_loss_kW = P_dcdc_conversion_loss_kW;
    step.P_dcdc_power_clipped_kW = P_dcdc_power_clipped_kW;

    step.P_bess_dcdc_conversion_loss_kW = P_bess_dcdc_conversion_loss_kW;
    step.P_bess_dcdc_power_clipped_kW = P_bess_dcdc_power_clipped_kW;

    step.dcdc_req = dcdc_req;
    step.dcdc_actual = dcdc_actual;

    % BESS internal losses
    step.P_bess_cell_loss_kW = P_bess_cell_loss_kW;
    step.P_bess_soc_full_loss_kW = P_bess_soc_full_loss_kW;
    step.P_bess_soc_empty_loss_kW = P_bess_soc_empty_loss_kW;
    step.P_bess_total_internal_loss_kW = P_bess_total_internal_loss_kW;

    % BESS state
    step.SoC = pack_out.SOC(:);

    if isfield(pack_out, 'SOH')
        step.SOH = pack_out.SOH(:);
    end

    % Energy fields
    step.E_pv_available_kWh = step.P_pv_available_kW * dt_h;
    step.E_pv_mpp_total_kWh = step.P_pv_mpp_total_kW * dt_h;
    step.E_pv_after_mppt_dcdc_kWh = step.P_pv_after_mppt_dcdc_kW * dt_h;

    step.E_pv_to_load_kWh = step.P_pv_to_load_kW * dt_h;
    step.E_pv_to_bess_kWh = step.P_pv_to_bess_kW * dt_h;
    step.E_bess_to_load_kWh = step.P_bess_to_load_kW * dt_h;
    step.E_grid_import_kWh = step.P_grid_import_kW * dt_h;
    step.E_grid_export_kWh = step.P_grid_export_kW * dt_h;
    step.E_curtailment_kWh = step.P_curtailment_kW * dt_h;

    step.E_inv_conversion_loss_kWh = step.P_inv_conversion_loss_kW * dt_h;
    step.E_dcdc_conversion_loss_kWh = step.P_dcdc_conversion_loss_kW * dt_h;
    step.E_bess_total_internal_loss_kWh = step.P_bess_total_internal_loss_kW * dt_h;

    step.E_pv_dcdc_conversion_loss_kWh = step.P_pv_dcdc_conversion_loss_kW * dt_h;
    step.E_pv_dcdc_power_clipped_kWh = step.P_pv_dcdc_power_clipped_kW * dt_h;

    step.E_bess_dcdc_conversion_loss_kWh = step.P_bess_dcdc_conversion_loss_kW * dt_h;
    step.E_bess_dcdc_power_clipped_kWh = step.P_bess_dcdc_power_clipped_kW * dt_h;

    % ---------------------------------------------------------------------
    % Converter efficiencies and control diagnostics
    % ---------------------------------------------------------------------

    if exist('inv_total', 'var') && isfield(inv_total, 'eta')
        step.eta_inverter = inv_total.eta(:);
    else
        step.eta_inverter = NaN(size(P_load_ac_kW));
    end

    if exist('inv_total', 'var') && isfield(inv_total, 'loadFraction')
        step.inverter_loadFraction = inv_total.loadFraction(:);
    else
        step.inverter_loadFraction = NaN(size(P_load_ac_kW));
    end

    if exist('pvDcdc', 'var') && isfield(pvDcdc, 'P_dc_link_total_kW') && ...
            isfield(pvDcdc, 'P_input_limited_total_kW')

        step.eta_pv_mppt_dcdc = local_safe_divide_vector( ...
            pvDcdc.P_dc_link_total_kW(:), ...
            pvDcdc.P_input_limited_total_kW(:));
    else
        step.eta_pv_mppt_dcdc = NaN(size(P_load_ac_kW));
    end

    if exist('pvDcdc', 'var') && isfield(pvDcdc, 'groups') && ~isempty(pvDcdc.groups)
        step.mppt_voltageRatio_mean = local_group_mean_signal(pvDcdc.groups, 'voltageRatio', numel(P_load_ac_kW));
        step.mppt_loadFraction_mean = local_group_mean_signal(pvDcdc.groups, 'loadFraction', numel(P_load_ac_kW));
        step.mppt_etaLoad_mean = local_group_mean_signal(pvDcdc.groups, 'etaLoad', numel(P_load_ac_kW));
        step.mppt_etaVoltage_mean = local_group_mean_signal(pvDcdc.groups, 'etaVoltage', numel(P_load_ac_kW));
    else
        step.mppt_voltageRatio_mean = NaN(size(P_load_ac_kW));
        step.mppt_loadFraction_mean = NaN(size(P_load_ac_kW));
        step.mppt_etaLoad_mean = NaN(size(P_load_ac_kW));
        step.mppt_etaVoltage_mean = NaN(size(P_load_ac_kW));
    end

    if exist('dcdc_actual', 'var') && isfield(dcdc_actual, 'eta_effective')
        step.eta_bess_dcdc = dcdc_actual.eta_effective(:);
    else
        step.eta_bess_dcdc = NaN(size(P_load_ac_kW));
    end

    if exist('dcdc_actual', 'var') && isfield(dcdc_actual, 'etaLoad')
        step.bess_dcdc_etaLoad = dcdc_actual.etaLoad(:);
    else
        step.bess_dcdc_etaLoad = NaN(size(P_load_ac_kW));
    end

    if exist('dcdc_actual', 'var') && isfield(dcdc_actual, 'etaVoltage')
        step.bess_dcdc_etaVoltage = dcdc_actual.etaVoltage(:);
    else
        step.bess_dcdc_etaVoltage = NaN(size(P_load_ac_kW));
    end

    if exist('dcdc_actual', 'var') && isfield(dcdc_actual, 'voltageRatio')
        step.bess_dcdc_voltageRatio = dcdc_actual.voltageRatio(:);
    else
        step.bess_dcdc_voltageRatio = NaN(size(P_load_ac_kW));
    end

    if exist('dcdc_actual', 'var') && isfield(dcdc_actual, 'loadFraction')
        step.bess_dcdc_loadFraction = dcdc_actual.loadFraction(:);
    else
        step.bess_dcdc_loadFraction = NaN(size(P_load_ac_kW));
    end

    % ---------------------------------------------------------------------
    % 17) State update
    % ---------------------------------------------------------------------
    stateEnd = stateStart;
    stateEnd.bess_state = bess_state;
    stateEnd.SoC = pack_out.SOC(end);

    if isfield(pack_out, 'SOH')
        stateEnd.SOH = pack_out.SOH(end);
    end
end


function V_dc_link_V = local_get_dc_link_voltage(cfg, design, N, pvGroups, V_pack_V)

    controlMode = "fixed";

    if isfield(cfg, 'dcBus') && isfield(cfg.dcBus, 'controlMode')
        controlMode = lower(string(cfg.dcBus.controlMode));
    end

    V_fixed = local_get_fixed_dc_link_voltage(cfg, design);

    if controlMode ~= "auto_optimal"
        V_dc_link_V = V_fixed * ones(N, 1);
        return;
    end

    if isfield(cfg, 'dcBus') && isfield(cfg.dcBus, 'V_candidate_vec_V') && ...
            ~isempty(cfg.dcBus.V_candidate_vec_V)
        Vcand = cfg.dcBus.V_candidate_vec_V(:);
    else
        Vcand = (700:25:1200).';
    end

    Vcand = Vcand(isfinite(Vcand) & Vcand > 0);

    if isempty(Vcand)
        V_dc_link_V = V_fixed * ones(N, 1);
        return;
    end

    V_inv_pref = V_fixed;

    if isfield(cfg, 'dcBus') && isfield(cfg.dcBus, 'inverterPreferred_V') && ...
            ~isempty(cfg.dcBus.inverterPreferred_V)
        V_inv_pref = cfg.dcBus.inverterPreferred_V;
    end

    wInv = local_get_weight(cfg, 'weightInverter', 0.50);
    wPv = local_get_weight(cfg, 'weightPvDcdc', 0.30);
    wBess = local_get_weight(cfg, 'weightBessDcdc', 0.20);

    mpptPars = local_get_mppt_dcdc_pars(cfg);
    bessPars = local_get_bess_dcdc_pars(cfg);

    V_pv_ref = local_estimate_representative_pv_voltage(pvGroups);

    V_pack_ref = median(V_pack_V(isfinite(V_pack_V) & V_pack_V > 0));

    if isempty(V_pack_ref) || ~isfinite(V_pack_ref) || V_pack_ref <= 0
        V_pack_ref = 700;
    end

    score = inf(size(Vcand));

    for i = 1:numel(Vcand)

        V = Vcand(i);

        invPenalty = ((V - V_inv_pref) / max(V_inv_pref, eps))^2;

        pvPenalty = 0;

        if isfinite(V_pv_ref) && V_pv_ref > 0
            pvRatio = V_pv_ref / V;
            etaPvV = local_interp_curve( ...
                mpptPars.voltageRatioCurve, ...
                mpptPars.etaVoltageCurve, ...
                pvRatio);

            pvPenalty = 1 - etaPvV / max(mpptPars.etaVoltageCurve);
        end

        % For DC bus selection, use the more demanding BESS direction:
        % discharge ratio = V_pack / V_dc
        % charge ratio    = V_dc / V_pack
        ratioDis = V_pack_ref / V;
        ratioChg = V / V_pack_ref;

        etaBessDis = local_interp_curve( ...
            bessPars.voltageRatioCurve, ...
            bessPars.etaVoltageCurve, ...
            ratioDis);

        etaBessChg = local_interp_curve( ...
            bessPars.voltageRatioCurve, ...
            bessPars.etaVoltageCurve, ...
            ratioChg);

        etaBessV = min(etaBessDis, etaBessChg);

        bessPenalty = 1 - etaBessV / max(bessPars.etaVoltageCurve);

        score(i) = ...
            wInv * invPenalty + ...
            wPv * pvPenalty + ...
            wBess * bessPenalty;
    end

    [~, bestIdx] = min(score);

    V_ref = Vcand(bestIdx);

    V_dc_link_V = V_ref * ones(N, 1);
end


function Vref = local_get_fixed_dc_link_voltage(cfg, design)

    Vref = [];

    if isfield(cfg, 'dcBus') && isfield(cfg.dcBus, 'V_ref_V')
        Vref = cfg.dcBus.V_ref_V;
    elseif isfield(cfg, 'dc') && isfield(cfg.dc, 'V_dc_link_ref_V')
        Vref = cfg.dc.V_dc_link_ref_V;
    elseif isfield(design, 'V_dc_link_V')
        Vref = design.V_dc_link_V;
    elseif isfield(design, 'V_dc_link_ref_V')
        Vref = design.V_dc_link_ref_V;
    end

    if isempty(Vref) || ~isnumeric(Vref) || ~isscalar(Vref) || ~isfinite(Vref) || Vref <= 0
        Vref = 1000;
    end
end


function w = local_get_weight(cfg, fieldName, defaultValue)

    w = defaultValue;

    if isfield(cfg, 'dcBus') && isfield(cfg.dcBus, fieldName)
        value = cfg.dcBus.(fieldName);

        if isnumeric(value) && isscalar(value) && isfinite(value) && value >= 0
            w = value;
        end
    end
end


function V_pv_ref = local_estimate_representative_pv_voltage(pvGroups)

    values = [];

    if isempty(pvGroups)
        V_pv_ref = NaN;
        return;
    end

    for g = 1:numel(pvGroups)

        if isfield(pvGroups(g), 'V_string_mpp_V') && ~isempty(pvGroups(g).V_string_mpp_V)
            v = pvGroups(g).V_string_mpp_V(:);
        elseif isfield(pvGroups(g), 'V_mpp_module_V') && ~isempty(pvGroups(g).V_mpp_module_V)

            if isfield(pvGroups(g), 'Ns') && ~isempty(pvGroups(g).Ns)
                Ns = pvGroups(g).Ns;
            else
                Ns = 24;
            end

            v = Ns * pvGroups(g).V_mpp_module_V(:);
        else
            continue;
        end

        if isfield(pvGroups(g), 'P_mppt_in_kW') && ~isempty(pvGroups(g).P_mppt_in_kW)
            p = pvGroups(g).P_mppt_in_kW(:);
        elseif isfield(pvGroups(g), 'P_orientation_available_kW') && ~isempty(pvGroups(g).P_orientation_available_kW)
            p = pvGroups(g).P_orientation_available_kW(:);
        else
            p = ones(size(v));
        end

        n = min(numel(v), numel(p));
        v = v(1:n);
        p = p(1:n);

        valid = isfinite(v) & v > 0 & isfinite(p) & p > 0;

        values = [values; v(valid)]; %#ok<AGROW>
    end

    if isempty(values)
        V_pv_ref = NaN;
    else
        V_pv_ref = median(values);
    end
end


function pars = local_get_mppt_dcdc_pars(cfg)

    if isfield(cfg, 'mpptDcdc')
        pars = cfg.mpptDcdc;
    else
        pars = struct();
    end

    pars = local_apply_mppt_default_pars(pars);
end


function pars = local_apply_mppt_default_pars(pars)

    pars = local_set_default(pars, 'loadFractionCurve', ...
        [0.00 0.05 0.10 0.20 0.50 0.75 1.00]);

    pars = local_set_default(pars, 'etaLoadCurve', ...
        [0.00 0.86 0.91 0.95 0.975 0.982 0.980]);

    pars = local_set_default(pars, 'voltageRatioCurve', ...
        [0.50 0.65 0.80 1.00 1.20 1.50 2.00]);

    pars = local_set_default(pars, 'etaVoltageCurve', ...
        [0.955 0.965 0.975 0.985 0.980 0.970 0.955]);

    pars = local_set_default(pars, 'etaMin', 0.00);
    pars = local_set_default(pars, 'etaMax', 0.985);
end


function pars = local_get_bess_dcdc_pars(cfg)

    if isfield(cfg, 'bessDcdc')
        pars = cfg.bessDcdc;
    else
        pars = struct();
    end

    pars = local_apply_bess_dcdc_default_pars(pars);
end


function pars = local_apply_bess_dcdc_default_pars(pars)

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
end


function pars = local_set_default(pars, name, value)

    if ~isfield(pars, name) || isempty(pars.(name))
        pars.(name) = value;
    end
end


function y = local_interp_curve(xCurve, yCurve, x)

    xCurve = xCurve(:);
    yCurve = yCurve(:);

    y = interp1(xCurve, yCurve, x, 'linear', 'extrap');

    yMin = min(yCurve);
    yMax = max(yCurve);

    y = min(max(y, yMin), yMax);

    if ~isfinite(y)
        y = 0;
    end
end


function V_pack_V = local_estimate_pack_voltage_before_step(bess_state, cfg, N)

    Vpack = [];

    if isfield(bess_state, 'V_pack') && ~isempty(bess_state.V_pack)
        Vpack = bess_state.V_pack;
    elseif isfield(bess_state, 'V_nominal_pack') && ~isempty(bess_state.V_nominal_pack)
        Vpack = bess_state.V_nominal_pack;
    elseif isfield(bess_state, 'Ns') && ~isempty(bess_state.Ns)
        Vpack = bess_state.Ns * 3.2;
    elseif isfield(cfg, 'bess') && isfield(cfg.bess, 'V_nominal_pack')
        Vpack = cfg.bess.V_nominal_pack;
    end

    if isempty(Vpack) || ~isnumeric(Vpack) || ~isfinite(Vpack(1)) || Vpack(1) <= 0
        Vpack = 700;
    end

    V_pack_V = local_fit_vector(Vpack, N, Vpack(1));
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

function y = local_safe_divide_vector(a, b)

    a = a(:);
    b = b(:);

    n = min(numel(a), numel(b));

    y = NaN(n, 1);

    idx = abs(b(1:n)) > 1e-12;
    y(idx) = a(idx) ./ b(idx);
end


function y = local_group_mean_signal(groups, fieldName, N)

    M = NaN(N, numel(groups));

    for g = 1:numel(groups)

        if isfield(groups(g), fieldName) && ~isempty(groups(g).(fieldName))
            x = groups(g).(fieldName)(:);

            if numel(x) >= N
                M(:, g) = x(1:N);
            else
                x(end+1:N, 1) = NaN;
                M(:, g) = x;
            end
        end
    end

    y = mean(M, 2, 'omitnan');
end