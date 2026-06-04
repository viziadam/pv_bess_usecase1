function [P_dc_vec, V_mpp_vec, aux] = pv_module_model( ...
    pvPars, ...
    tminVec, ...
    GHI_vec, ...
    DIF_vec, ...
    SWU_vec, ...
    Tamb_vec, ...
    sunElev_vec, ...
    sunAzim_vec, ...
    tiltX, ...
    tiltZ)
% PV_MODULE_MODEL
%
% Cfg-alapu modulszintu PV modell.
%
% Kimenetek:
%   P_dc_vec   - modul DC teljesitmeny MPP munkapontban [W]
%   V_mpp_vec  - modul MPP feszultseg [V]
%   aux        - kiegeszito diagnosztikai adatok

    %#ok<*NASGU>

    % ---------------------------------------------------------------------
    % 0) Input formatting
    % ---------------------------------------------------------------------
    GHI_vec      = GHI_vec(:).';
    DIF_vec      = DIF_vec(:).';
    SWU_vec      = SWU_vec(:).';
    Tamb_vec     = Tamb_vec(:).';
    sunElev_vec  = sunElev_vec(:).';
    sunAzim_vec  = sunAzim_vec(:).';

    N = numel(GHI_vec);

    if numel(DIF_vec) ~= N || numel(SWU_vec) ~= N || ...
            numel(Tamb_vec) ~= N || numel(sunElev_vec) ~= N || ...
            numel(sunAzim_vec) ~= N

        error('pv_module_model: input vectors must have the same length.');
    end

    % ---------------------------------------------------------------------
    % 1) PV module parameters from cfg-derived pvPars
    % ---------------------------------------------------------------------
    P_stc = pvPars.P_stc_W;

    gamma = pvPars.gamma_P_per_C;
    NOCT = pvPars.NOCT_C;

    V_mpp_stc = pvPars.V_mpp_stc_V;
    beta_vmp = pvPars.beta_vmp_per_C;

    phi_p = pvPars.bifacialFactor;
    useBifacial = pvPars.useBifacial;

    groundAlbedo = pvPars.groundAlbedo;

    G_ref = pvPars.G_ref_Wm2;
    G_min_for_voltage = pvPars.G_min_for_voltage_Wm2;

    vmp_irr_log_coeff = pvPars.vmp_irr_log_coeff;
    vmp_irr_factor_min = pvPars.vmp_irr_factor_min;
    vmp_irr_factor_max = pvPars.vmp_irr_factor_max;
    vmp_temp_factor_min = pvPars.vmp_temp_factor_min;

    % ---------------------------------------------------------------------
    % 2) Geometriai szamitasok
    % ---------------------------------------------------------------------
    DNI_hor = GHI_vec - DIF_vec;
    DNI_hor(DNI_hor < 0) = 0;

    cos_aoi = sind(sunElev_vec) .* cosd(tiltX) + ...
              cosd(sunElev_vec) .* sind(tiltX) .* cosd(sunAzim_vec - tiltZ);

    cos_aoi = max(0, cos_aoi);

    % ---------------------------------------------------------------------
    % 3) Front oldali besugarzas
    % ---------------------------------------------------------------------
    G_beam_t = DNI_hor .* (cos_aoi ./ max(sind(sunElev_vec), 0.01));

    anisotropy_index = DNI_hor ./ 1367;
    anisotropy_index = min(max(anisotropy_index, 0), 1);

    G_diffuse_t = DIF_vec .* ...
        (anisotropy_index .* (cos_aoi ./ max(sind(sunElev_vec), 0.01)) + ...
        (1 - anisotropy_index) .* (1 + cosd(tiltX)) / 2);

    G_ground_t = GHI_vec .* groundAlbedo .* (1 - cosd(tiltX)) / 2;

    G_front = G_beam_t + G_diffuse_t;

    % ---------------------------------------------------------------------
    % 4) Hatoldali besugarzas
    % ---------------------------------------------------------------------
    G_sky_diffuse_r = DIF_vec .* (1 - cosd(tiltX)) / 2;

    % SWU a BSRN adatban felfele verodo rovidhullamu sugarzas.
    G_rear = phi_p .* (SWU_vec + G_sky_diffuse_r);

    % ---------------------------------------------------------------------
    % 5) Effektiv besugarzas
    % ---------------------------------------------------------------------
    if useBifacial
        G_total = G_front + G_rear;
    else
        G_total = G_front;
    end

    G_total = max(G_total, 0);

    % ---------------------------------------------------------------------
    % 6) Cellahomerseklet
    % ---------------------------------------------------------------------
    T_cell = Tamb_vec + (G_total / 800) * (NOCT - 20);

    % ---------------------------------------------------------------------
    % 7) Modul DC teljesitmeny MPP-ben
    % ---------------------------------------------------------------------
    P_dc_vec = (G_total / G_ref) * P_stc .* ...
        (1 + gamma * (T_cell - 25));

    P_dc_vec(sunElev_vec <= 0 | G_total <= 0) = 0;
    P_dc_vec = max(0, P_dc_vec);

    % ---------------------------------------------------------------------
    % 8) Modul MPP feszultseg
    % ---------------------------------------------------------------------
    tempFactor = 1 + beta_vmp * (T_cell - 25);

    G_for_voltage = max(G_total, G_min_for_voltage);
    irrFactor = 1 + vmp_irr_log_coeff * log(G_for_voltage / G_ref);

    irrFactor = min(max(irrFactor, vmp_irr_factor_min), vmp_irr_factor_max);
    tempFactor = max(tempFactor, vmp_temp_factor_min);

    V_mpp_vec = V_mpp_stc .* tempFactor .* irrFactor;

    % Ha nincs termeles, akkor nincs ertelmezett MPP uzemi feszultseg sem
    % az energiaaramlasi modell szempontjabol.
    V_mpp_vec(P_dc_vec <= 0) = 0;

    % ---------------------------------------------------------------------
    % 9) Output formatting
    % ---------------------------------------------------------------------
    P_dc_vec = P_dc_vec(:).';
    V_mpp_vec = V_mpp_vec(:).';

    aux = struct();
    aux.G_front_Wm2 = G_front(:).';
    aux.G_rear_Wm2 = G_rear(:).';
    aux.G_total_Wm2 = G_total(:).';
    aux.T_cell_C = T_cell(:).';
    aux.tiltX = tiltX;
    aux.tiltZ = tiltZ;
end

