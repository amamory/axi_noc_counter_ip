# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "INC_VALUE" -parent ${Page_0}


}

proc update_PARAM_VALUE.INC_VALUE { PARAM_VALUE.INC_VALUE } {
	# Procedure called to update INC_VALUE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INC_VALUE { PARAM_VALUE.INC_VALUE } {
	# Procedure called to validate INC_VALUE
	return true
}


proc update_MODELPARAM_VALUE.INC_VALUE { MODELPARAM_VALUE.INC_VALUE PARAM_VALUE.INC_VALUE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INC_VALUE}] ${MODELPARAM_VALUE.INC_VALUE}
}

