function plot_dc_coupled_diagnostic_day(diag, dayIndex, savePath)
% PLOT_DC_COUPLED_DIAGNOSTIC_DAY
%
% Detailed diagnostic plot for one day of the DC-coupled PV+BESS topology.
%
% Plotted groups:
%   1) Main energy flows
%   2) DC-link and BESS pack voltage
%   3) PV MPPT DC/DC operation
%   4) BESS buck-boost DC/DC operation
%   5) Inverter operation
%   6) BESS control requests
%   7) Losses and clipping
%   8) SoC and grid interaction

    S = diag.series;

    idx = S.dayIndex == dayIndex;

    if ~any(idx)
        return;
    end

    t = S.time_h(idx) - (dayIndex - 1) * 24;

    fig = figure( ...
        'Color', 'w', ...
        'Name', sprintf('DC-coupled diagnostic summary day %d', dayIndex), ...
        'Position', [50, 50, 1500, 1100]);

    tiledlayout(4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ---------------------------------------------------------------------
    % 1) Main energy flows
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_if_available(t, S, idx, 'P_load_kW', 'Load');
    local_plot_if_available(t, S, idx, 'P_pv_available_kW', 'PV MPP available');
    local_plot_if_available(t, S, idx, 'P_pv_after_mppt_dcdc_kW', 'PV after MPPT DC/DC');
    local_plot_if_available(t, S, idx, 'P_inv_ac_output_kW', 'Inverter AC output');

    ylabel('Power [kW]');
    title('Main energy flow levels');
    legend('Location', 'best');
    xlim([0 24]);

    % ---------------------------------------------------------------------
    % 2) DC-link and BESS voltage
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_if_available(t, S, idx, 'V_dc_link_V', 'DC-link voltage');
    local_plot_if_available(t, S, idx, 'V_pack_pre_V', 'Pack voltage before step');
    local_plot_if_available(t, S, idx, 'V_pack_actual_V', 'Pack voltage actual');

    ylabel('Voltage [V]');
    title('DC bus and BESS pack voltage');
    legend('Location', 'best');
    xlim([0 24]);

    % ---------------------------------------------------------------------
    % 3) PV MPPT DC/DC
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_percent_if_available(t, S, idx, 'eta_pv_mppt_dcdc', 'MPPT total eta');
    local_plot_percent_if_available(t, S, idx, 'mppt_etaLoad_mean', 'MPPT eta load');
    local_plot_percent_if_available(t, S, idx, 'mppt_etaVoltage_mean', 'MPPT eta voltage');

    ylabel('Efficiency [%]');
    title('PV MPPT DC/DC efficiencies');
    legend('Location', 'best');
    ylim([0 105]);
    xlim([0 24]);

    yyaxis right;
    local_plot_if_available(t, S, idx, 'mppt_voltageRatio_mean', 'MPPT Uin/Uout');
    ylabel('Voltage ratio [-]');

    % ---------------------------------------------------------------------
    % 4) BESS buck-boost DC/DC
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_percent_if_available(t, S, idx, 'eta_bess_dcdc', 'BESS DC/DC total eta');
    local_plot_percent_if_available(t, S, idx, 'bess_dcdc_etaLoad', 'BESS DC/DC eta load');
    local_plot_percent_if_available(t, S, idx, 'bess_dcdc_etaVoltage', 'BESS DC/DC eta voltage');

    ylabel('Efficiency [%]');
    title('BESS bidirectional buck-boost DC/DC efficiencies');
    legend('Location', 'best');
    ylim([0 105]);
    xlim([0 24]);

    yyaxis right;
    local_plot_if_available(t, S, idx, 'bess_dcdc_voltageRatio', 'BESS DC/DC Uin/Uout');
    ylabel('Voltage ratio [-]');

    % ---------------------------------------------------------------------
    % 5) Inverter
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_percent_if_available(t, S, idx, 'eta_inverter', 'Inverter eta');
    local_plot_percent_if_available(t, S, idx, 'inverter_loadFraction', 'Inverter load fraction');

    ylabel('[%]');
    title('Inverter efficiency and loading');
    legend('Location', 'best');
    ylim([0 105]);
    xlim([0 24]);

    % ---------------------------------------------------------------------
    % 6) Control requests
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_if_available(t, S, idx, 'P_bess_high_req_kW', 'BESS DC-link request');
    local_plot_if_available(t, S, idx, 'P_bess_high_actual_kW', 'BESS DC-link actual');
    local_plot_if_available(t, S, idx, 'P_pack_req_kW', 'Pack request');
    local_plot_if_available(t, S, idx, 'P_pack_actual_kW', 'Pack actual');

    yline(0, 'k-');
    ylabel('Power [kW]');
    title('BESS control and actual response');
    legend('Location', 'best');
    xlim([0 24]);

    % ---------------------------------------------------------------------
    % 7) Losses and clipping
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_if_available(t, S, idx, 'P_inv_conversion_loss_kW', 'Inverter conversion loss');
    local_plot_if_available(t, S, idx, 'P_pv_dcdc_conversion_loss_kW', 'PV DC/DC loss');
    local_plot_if_available(t, S, idx, 'P_bess_dcdc_conversion_loss_kW', 'BESS DC/DC loss');
    local_plot_if_available(t, S, idx, 'P_dcdc_power_clipped_kW', 'DC/DC clipped');
    local_plot_if_available(t, S, idx, 'P_inv_power_clipped_kW', 'Inverter clipped');

    ylabel('Power [kW]');
    title('Converter losses and clipping');
    legend('Location', 'best');
    xlim([0 24]);

    % ---------------------------------------------------------------------
    % 8) SoC and grid interaction
    % ---------------------------------------------------------------------
    nexttile;
    hold on;
    grid on;

    local_plot_percent_if_available(t, S, idx, 'SoC', 'SoC');

    ylabel('SoC [%]');
    ylim([0 105]);
    title('SoC and grid / curtailment');

    yyaxis right;
    local_plot_if_available(t, S, idx, 'P_grid_import_kW', 'Grid import');
    local_plot_if_available(t, S, idx, 'P_curtailment_kW', 'Curtailment');
    ylabel('Power [kW]');

    legend('Location', 'best');
    xlim([0 24]);
    xlabel('Time [h]');

    sgtitle(sprintf('DC-coupled PV+BESS diagnostic summary - day %d', dayIndex));

    if ~isfolder(savePath)
        mkdir(savePath);
    end

    fileName = sprintf('dc_coupled_diagnostic_summary_day_%04d.png', dayIndex);
    saveas(fig, fullfile(savePath, fileName));

    if isfield(diag, 'cfgSnapshot') && ...
            isfield(diag.cfgSnapshot, 'diagnostics') && ...
            isfield(diag.cfgSnapshot.diagnostics, 'saveFigFiles') && ...
            diag.cfgSnapshot.diagnostics.saveFigFiles

        fileNameFig = sprintf('dc_coupled_diagnostic_summary_day_%04d.fig', dayIndex);
        savefig(fig, fullfile(savePath, fileNameFig));
    end
end


function local_plot_if_available(t, S, idx, fieldName, displayName)

    if ~isfield(S, fieldName)
        return;
    end

    x = S.(fieldName)(idx);

    if isempty(x) || all(isnan(x))
        return;
    end

    plot(t, x, 'LineWidth', 1.2, 'DisplayName', displayName);
end


function local_plot_percent_if_available(t, S, idx, fieldName, displayName)

    if ~isfield(S, fieldName)
        return;
    end

    x = S.(fieldName)(idx);

    if isempty(x) || all(isnan(x))
        return;
    end

    plot(t, 100 * x, 'LineWidth', 1.2, 'DisplayName', displayName);
end