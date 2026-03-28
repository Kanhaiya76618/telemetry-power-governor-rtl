## =============================================================================
## FILE: cora_z7_07s_pwr_gov_top.xdc
## PURPOSE: Full pin/timing constraints for pwr_gov_top on Cora Z7-07S Rev. B
## NOTE:
## - Based on Digilent Cora-Z7-07S-Master.xdc pin map.
## - Uses LVCMOS33 for all mapped PL I/O.
## - rst_n is mapped to btn[0] pin. If your button polarity is opposite,
##   invert/reset in RTL wrapper.
## =============================================================================

## Clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }]

## Reset
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]
set_property PULLUP true [get_ports { rst_n }]

## Inputs: Subsystem A/B telemetry and controls
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports { act_a }]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports { stall_a }]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { req_a[0] }]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports { req_a[1] }]

set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { temp_a[0] }]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { temp_a[1] }]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { temp_a[2] }]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { temp_a[3] }]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { temp_a[4] }]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports { temp_a[5] }]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { temp_a[6] }]

set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { act_b }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { stall_b }]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { req_b[0] }]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { req_b[1] }]

set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { temp_b[0] }]
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports { temp_b[1] }]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports { temp_b[2] }]
set_property -dict { PACKAGE_PIN N20 IOSTANDARD LVCMOS33 } [get_ports { temp_b[3] }]
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 } [get_ports { temp_b[4] }]
set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports { temp_b[5] }]
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { temp_b[6] }]

set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { ext_budget_in[0] }]
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports { ext_budget_in[1] }]
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports { ext_budget_in[2] }]
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports { use_ext_budget }]

## Outputs: Status and grants
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVCMOS33 } [get_ports { grant_a[0] }]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { grant_a[1] }]
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { grant_b[0] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { grant_b[1] }]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { clk_en_a }]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { clk_en_b }]

set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { current_budget[0] }]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { current_budget[1] }]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { current_budget[2] }]

set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { budget_headroom[0] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { budget_headroom[1] }]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { budget_headroom[2] }]

set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[0] }]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[1] }]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[2] }]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[3] }]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[4] }]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[5] }]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[6] }]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[7] }]
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[8] }]
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS33 } [get_ports { system_efficiency[9] }]

set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 } [get_ports { alarm_a }]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports { alarm_b }]

## Default idle biasing for open inputs (prevents floating behavior)
set_property PULLDOWN true [get_ports { act_a }]
set_property PULLDOWN true [get_ports { stall_a }]
set_property PULLDOWN true [get_ports { req_a[*] }]
set_property PULLDOWN true [get_ports { temp_a[*] }]

set_property PULLDOWN true [get_ports { act_b }]
set_property PULLDOWN true [get_ports { stall_b }]
set_property PULLDOWN true [get_ports { req_b[*] }]
set_property PULLDOWN true [get_ports { temp_b[*] }]

set_property PULLDOWN true [get_ports { ext_budget_in[*] }]
set_property PULLDOWN true [get_ports { use_ext_budget }]
