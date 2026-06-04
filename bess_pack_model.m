function [pack_out, pack_state] = bess_pack_model(P_pack_req, mode, pack_params, dt_h, pack_state)
% BESS_PACK_MODEL
%
% System-level BESS pack model using one representative LFP cell model.
%
% Sign convention:
%   P_pack_req > 0  : discharge from pack
%   P_pack_req < 0  : charge into pack
%
% The pack is scaled by:
%   Ns : number of series cells
%   Np : number of parallel strings
%
% Important:
%   For this PV+BESS case study, Ns should come from cfg.bess.Ns.
%   This keeps the BESS voltage level consistent with the selected
%   1000 V class DC architecture.

    if strcmp(mode, 'init')

        % -----------------------------------------------------------------
        % 1) Read sizing parameters
        % -----------------------------------------------------------------
        E_target_kWh = pack_params.target_energy_kWh;
        P_max_W = pack_params.max_power_W;

        CELL_AH = local_get_param(pack_params, 'cellCapacity_Ah', 280);
        CELL_V_NOM = local_get_param(pack_params, 'cellNominalVoltage_V', 3.2);

        CELL_KWH = (CELL_AH * CELL_V_NOM) / 1000;

        % -----------------------------------------------------------------
        % 2) Select series cell number
        % -----------------------------------------------------------------
        if isfield(pack_params, 'Ns') && ~isempty(pack_params.Ns) && ...
                isnumeric(pack_params.Ns) && isscalar(pack_params.Ns) && ...
                isfinite(pack_params.Ns) && pack_params.Ns > 0

            Ns = round(pack_params.Ns);

        elseif isfield(pack_params, 'V_nominal_pack') && ~isempty(pack_params.V_nominal_pack) && ...
                isnumeric(pack_params.V_nominal_pack) && isscalar(pack_params.V_nominal_pack) && ...
                isfinite(pack_params.V_nominal_pack) && pack_params.V_nominal_pack > 0

            Ns = round(pack_params.V_nominal_pack / CELL_V_NOM);

        else

            % Fallback only.
            % In this project, prefer setting cfg.bess.Ns explicitly.
            Ns = 270;
        end

        Ns = max(1, Ns);

        % -----------------------------------------------------------------
        % 3) Select parallel string number based on target energy
        % -----------------------------------------------------------------
        E_string_kWh = Ns * CELL_KWH;

        if E_target_kWh <= 0 || P_max_W <= 0
            Np = 0;
            E_installed_kWh = 0;
        else
            Np = round(E_target_kWh / E_string_kWh);
            Np = max(1, Np);
            E_installed_kWh = Np * E_string_kWh;
        end

        V_nominal_pack = Ns * CELL_V_NOM;

        % -----------------------------------------------------------------
        % 4) Initialize pack state
        % -----------------------------------------------------------------
        pack_state = struct();

        pack_state.Ns = Ns;
        pack_state.Np = Np;

        pack_state.cellCapacity_Ah = CELL_AH;
        pack_state.cellNominalVoltage_V = CELL_V_NOM;

        pack_state.V_nominal_pack = V_nominal_pack;
        pack_state.E_installed_kWh = E_installed_kWh;
        pack_state.P_max_W = P_max_W;

        if Np <= 0
            pack_state.cell_state = [];
        else
            cell_params = struct();
            cell_params.C_nom_Ah = CELL_AH;
            cell_params.V_nom = CELL_V_NOM;
            cell_params.initial_soc = local_get_param(pack_params, 'initial_soc', 0.5);

            if isfield(pack_params, 'initial_T')
                cell_params.initial_T = pack_params.initial_T;
            end

            if isfield(pack_params, 'cap_floor_frac')
                cell_params.cap_floor_frac = pack_params.cap_floor_frac;
            end

            [~, cell_init_state] = lfp_cell(0, 'init', cell_params, dt_h, []);
            pack_state.cell_state = cell_init_state;
        end

        pack_out = struct();

        pack_out.Ns = Ns;
        pack_out.Np = Np;
        pack_out.V_nominal_pack = V_nominal_pack;
        pack_out.E_installed_kWh = E_installed_kWh;
        pack_out.Total_cells = Ns * Np;

        return;
    end

    if ~strcmp(mode, 'run')
        error('Unknown mode. Use ''init'' or ''run''.');
    end

    % ---------------------------------------------------------------------
    % Run mode
    % ---------------------------------------------------------------------
    P_pack_req = P_pack_req(:).';
    N = numel(P_pack_req);

    if isempty(pack_state) || ~isfield(pack_state, 'Ns') || ~isfield(pack_state, 'Np')
        error('bess_pack_model: pack_state is not initialized.');
    end

    Ns = pack_state.Ns;
    Np = pack_state.Np;

    if Np <= 0 || Ns <= 0 || isempty(pack_state.cell_state)
        pack_out = local_zero_run_output(N);
        return;
    end

    % ---------------------------------------------------------------------
    % Power request per cell
    % ---------------------------------------------------------------------
    P_req_cell_vec = P_pack_req / max(Ns * Np, eps);

    % ---------------------------------------------------------------------
    % Cell model run
    % ---------------------------------------------------------------------
    cell_params = struct();

    if isfield(pack_params, 'T_vec')
        cell_params.T_vec = pack_params.T_vec;
    else
        cell_params.T_vec = 25 * ones(1, N);
    end

    [cell_out, next_cell_state] = lfp_cell( ...
        P_req_cell_vec, ...
        'run', ...
        cell_params, ...
        dt_h, ...
        pack_state.cell_state);

    % ---------------------------------------------------------------------
    % Scale results to full pack
    % ---------------------------------------------------------------------
    pack_out = struct();

    pack_out.V_pack = cell_out.Ut(:) * Ns;
    pack_out.I_pack = cell_out.I_cell(:) * Np;

    % Positive = discharge, negative = charge.
    pack_out.P_pack_req_W = P_pack_req(:);
    pack_out.P_pack_actual_W = pack_out.V_pack(:) .* pack_out.I_pack(:);

    pack_out.SOC = cell_out.SOC(:);
    pack_out.T_cell = cell_out.T_cell(:);

    pack_out.E_stored = cell_out.E_stored(:) * Ns * Np;
    pack_out.E_discharged = cell_out.E_discharged(:) * Ns * Np;
    pack_out.E_loss_joule = cell_out.E_loss_joule(:) * Ns * Np;
    pack_out.E_loss_sat = cell_out.E_loss_sat(:) * Ns * Np;
    pack_out.E_loss_empty = cell_out.E_loss_empty(:) * Ns * Np;

    pack_out.SOH = cell_out.SOH(:);

    pack_out.Ns = Ns;
    pack_out.Np = Np;
    pack_out.V_nominal_pack = pack_state.V_nominal_pack;
    pack_out.E_installed_kWh = pack_state.E_installed_kWh;

    % State update
    pack_state.cell_state = next_cell_state;
end


function value = local_get_param(s, fieldName, defaultValue)

    value = defaultValue;

    if isfield(s, fieldName)
        candidate = s.(fieldName);

        if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end


function pack_out = local_zero_run_output(N)

    z = zeros(N, 1);

    pack_out = struct();

    pack_out.V_pack = z;
    pack_out.I_pack = z;

    pack_out.P_pack_req_W = z;
    pack_out.P_pack_actual_W = z;

    pack_out.SOC = z;
    pack_out.T_cell = z;

    pack_out.E_stored = z;
    pack_out.E_discharged = z;
    pack_out.E_loss_joule = z;
    pack_out.E_loss_sat = z;
    pack_out.E_loss_empty = z;

    pack_out.SOH = ones(N, 1);

    pack_out.Ns = 0;
    pack_out.Np = 0;
    pack_out.V_nominal_pack = 0;
    pack_out.E_installed_kWh = 0;
end