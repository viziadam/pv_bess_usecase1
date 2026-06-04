function [P_dc_vec, V_mpp_vec] = pv_module_model( ...
    P_stc, ...
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
% Modulszintu PV modell.
%
% Kimenetek:
%   P_dc_vec   - modul DC teljesitmeny MPP munkapontban [W]
%   V_mpp_vec  - modul MPP feszultseg [V]
%
% Fontos:
%   Itt csak egyetlen modul eredmenyeit szamoljuk.
%   A string es PV park szintu meretezes kesobb tortenik:
%       V_string_mpp = Ns * V_mpp_vec
%       P_park       = P_dc_vec * Ns * Np

    %#ok<*NASGU>
    % tminVec jelenleg csak kompatibilitas miatt marad bemenetkent.
    % A modell vektorizaltan a meteorologiai idosorokon dolgozik.

    % ---------------------------------------------------------------------
    % 0) Modul parameterek
    % ---------------------------------------------------------------------
    % P_stc: bemenetkent adott nevleges modul teljesitmeny [W]
    GHI_vec      = GHI_vec(:).';
    DIF_vec      = DIF_vec(:).';
    SWU_vec      = SWU_vec(:).';
    Tamb_vec     = Tamb_vec(:).';
    sunElev_vec  = sunElev_vec(:).';
    sunAzim_vec  = sunAzim_vec(:).';

    phi_p = 0.85;       % Bifacialis faktor [-]
    gamma = -0.0038;    % Teljesitmeny homersekleti egyutthato [1/C]
    NOCT  = 43.7;       % Nevleges uzemi cellahomerseklet [C]
    Area  = 1.68;       % Modul felulet [m2]

    % ---------------------------------------------------------------------
    % MPP feszultseg egyszerusitett modellparameterei
    % ---------------------------------------------------------------------
    % Ezt adatlap alapjan kesobb pontositsd.
    % Tipikus nagy teljesitmenyu Si modulnal Vmp_stc kb. 40-45 V.
    V_mpp_stc = 41.5;       % Modul MPP feszultseg STC mellett [V]
    beta_vmp  = -0.0028;    % Vmp homersekleti egyutthato [1/C]

    % Gyenge besugarzasnal a Vmp kisse csokken.
    % Ez csak egyszeru kozelites, nem reszletes egy-diodas modell.
    vmp_irr_log_coeff = 0.025;
    G_ref = 1000;           % STC besugarzas [W/m2]
    G_min_for_voltage = 50; % Numerikus also hatar [W/m2]

    % ---------------------------------------------------------------------
    % 1) Geometriai szamitasok
    % ---------------------------------------------------------------------
    DNI_hor = GHI_vec - DIF_vec;
    DNI_hor(DNI_hor < 0) = 0;

    cos_aoi = sind(sunElev_vec) .* cosd(tiltX) + ...
              cosd(sunElev_vec) .* sind(tiltX) .* cosd(sunAzim_vec - tiltZ);

    cos_aoi = max(0, cos_aoi);

    % ---------------------------------------------------------------------
    % 2) Front oldali sugarzas
    % ---------------------------------------------------------------------
    G_beam_t = DNI_hor .* (cos_aoi ./ max(sind(sunElev_vec), 0.01));

    anisotropy_index = DNI_hor ./ 1367;
    anisotropy_index = min(max(anisotropy_index, 0), 1);

    G_diffuse_t = DIF_vec .* ...
        (anisotropy_index .* (cos_aoi ./ max(sind(sunElev_vec), 0.01)) + ...
        (1 - anisotropy_index) .* (1 + cosd(tiltX)) / 2);

    G_ground_t = GHI_vec .* 0.2 .* (1 - cosd(tiltX)) / 2;

    G_front = G_beam_t + G_diffuse_t;

    % ---------------------------------------------------------------------
    % 3) Hatoldali sugarzas
    % ---------------------------------------------------------------------
    G_sky_diffuse_r = DIF_vec .* (1 - cosd(tiltX)) / 2;
    G_rear = phi_p .* (SWU_vec + G_sky_diffuse_r);

    % ---------------------------------------------------------------------
    % 4) Effektiv besugarzas
    % ---------------------------------------------------------------------
    % Fontos:
    % Itt szandekosan megtartjuk az eredeti modell logikajat, vagyis
    % a teljesitmeny csak a front oldali komponensbol szamolodik.
    % Ha kesobb a bifacialis hatast is be akarod kapcsolni:
    %     G_total = G_front + G_rear;
    %
    % Most:
    G_total = G_front;

    G_total = max(G_total, 0);

    % ---------------------------------------------------------------------
    % 5) Cellahomerseklet
    % ---------------------------------------------------------------------
    T_cell = Tamb_vec + (G_total / 800) * (NOCT - 20);

    % ---------------------------------------------------------------------
    % 6) Modul DC teljesitmeny MPP-ben
    % ---------------------------------------------------------------------
    P_dc_vec = (G_total / 1000) * P_stc .* ...
        (1 + gamma * (T_cell - 25));

    P_dc_vec(sunElev_vec <= 0 | G_total <= 0) = 0;
    P_dc_vec = max(0, P_dc_vec);

    % ---------------------------------------------------------------------
    % 7) Modul MPP feszultseg egyszerusitett szamitasa
    % ---------------------------------------------------------------------
    tempFactor = 1 + beta_vmp * (T_cell - 25);

    G_for_voltage = max(G_total, G_min_for_voltage);
    irrFactor = 1 + vmp_irr_log_coeff * log(G_for_voltage / G_ref);

    % Numerikus es fizikai vedelmi korlatok.
    irrFactor = min(max(irrFactor, 0.85), 1.05);
    tempFactor = max(tempFactor, 0.70);

    V_mpp_vec = V_mpp_stc .* tempFactor .* irrFactor;

    % Ha nincs termeles, akkor nincs ertelmezett MPP uzemi feszultseg sem
    % az energiaaramlasi modell szempontjabol.
    V_mpp_vec(P_dc_vec <= 0) = 0;

    % Sorvektoros kimenet
    P_dc_vec = P_dc_vec(:).';
    V_mpp_vec = V_mpp_vec(:).';
end