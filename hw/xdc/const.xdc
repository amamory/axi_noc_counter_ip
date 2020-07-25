
create_clock -period 20.000 -name clock -waveform {0.000 10.000} [get_ports clock]
#set_output_delay -clock [get_clocks *clock*] 6.000 [get_ports -filter { NAME =~  "*m_data_o*" && DIRECTION == "OUT" }]
#set_output_delay -clock [get_clocks *clock*] 6.000 [get_ports -filter { NAME =~  "*m_last_o*" && DIRECTION == "OUT" }]
#set_output_delay -clock [get_clocks *clock*] 6.000 [get_ports -filter { NAME =~  "*m_valid_o*" && DIRECTION == "OUT" }]
#set_output_delay -clock [get_clocks *clock*] 6.000 [get_ports -filter { NAME =~  "*s_ready_o*" && DIRECTION == "OUT" }]
