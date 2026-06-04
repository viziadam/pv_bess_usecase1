function state = init_bess_state_for_candidate(design, cfg, dt_h)
% INIT_BESS_STATE_FOR_CANDIDATE
%
% BESS allapot inicializalasa egy candidate futtatasa elott.
%
% Cel:
%   - a BESS pack feszultsegszintje ne automatikus teljesitmeny-alapu
%     valasztasbol jojjon,
%   - hanem a cfg.bess konfiguraciobol,
%   - igy a 1000 V-os rendszerosztalyhoz illesztett rack/string
%     vegig megmarad a szimulacio soran.
%
% Bemenet:
%   design.E_BESS_kWh
%   design.P_BESS_kW
%   cfg.bess.SoC_initial
%   cfg.bess.Ns
%   cfg.bess.V_nominal_pack
%   cfg.bess.cellCapacity_Ah
%   cfg.bess.cellNominalVoltage_V
%   dt_h
%
% Kimenet:
%   state.SoC
%   state.bess_state
%   state.pack_info

    if isfield(cfg, 'bess') && isfield(cfg.bess, 'SoC_initial')
        SoC_initial = cfg.bess.SoC_initial;
    else
        SoC_initial = 0.5;
    end

    pack_params = struct();
    pack_params.target_energy_kWh = design.E_BESS_kWh;
    pack_params.max_power_W = design.P_BESS_kW * 1000;
    pack_params.initial_soc = SoC_initial;

    % ---------------------------------------------------------------------
    % BESS rack / pack voltage configuration from cfg
    % ---------------------------------------------------------------------
    if isfield(cfg, 'bess') && isfield(cfg.bess, 'Ns')
        pack_params.Ns = cfg.bess.Ns;
    end

    if isfield(cfg, 'bess') && isfield(cfg.bess, 'V_nominal_pack')
        pack_params.V_nominal_pack = cfg.bess.V_nominal_pack;
    end

    if isfield(cfg, 'bess') && isfield(cfg.bess, 'cellCapacity_Ah')
        pack_params.cellCapacity_Ah = cfg.bess.cellCapacity_Ah;
    end

    if isfield(cfg, 'bess') && isfield(cfg.bess, 'cellNominalVoltage_V')
        pack_params.cellNominalVoltage_V = cfg.bess.cellNominalVoltage_V;
    end

    [pack_info, bess_state] = bess_pack_model( ...
        0, ...
        'init', ...
        pack_params, ...
        dt_h, ...
        []);

    state = struct();
    state.SoC = SoC_initial;
    state.bess_state = bess_state;
    state.pack_info = pack_info;
end