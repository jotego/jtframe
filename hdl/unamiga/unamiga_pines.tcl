
# pin & location assignments
# ==========================
# reloj principal de 50mhz
set_location_assignment PIN_E1 -to CLOCK_50

# BOTONES
set_location_assignment PIN_J16 -to BTN[0]
set_location_assignment PIN_J15 -to BTN[1]

# LEDS
set_location_assignment PIN_C2 -to LED

# RATON
#set_location_assignment PIN_T4 -to PS2_MCLK
#set_location_assignment PIN_R5 -to PS2_MDAT
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_MCLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_MDAT

# TECLADO
set_location_assignment PIN_E7 -to PS2_CLK
set_location_assignment PIN_F1 -to PS2_DATA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_DATA
# SONIDO
set_location_assignment PIN_J2 -to AUDIO_L
set_location_assignment PIN_J1 -to AUDIO_R

# JOYS
set_location_assignment PIN_P3 -to JOYA[0]
set_location_assignment PIN_N5 -to JOYA[1]
set_location_assignment PIN_R3 -to JOYA[2]
set_location_assignment PIN_R4 -to JOYA[3]
set_location_assignment PIN_N3 -to JOYA[4]
set_location_assignment PIN_T3 -to JOYA[5]
set_location_assignment PIN_N11 -to JOYB[0]
set_location_assignment PIN_T10 -to JOYB[1]
set_location_assignment PIN_P9 -to JOYB[2]
set_location_assignment PIN_N8 -to JOYB[3]
set_location_assignment PIN_P8 -to JOYB[4]
set_location_assignment PIN_P11 -to JOYB[5]
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to JOYA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to JOYB

# VGA 
set_location_assignment PIN_F8 -to VGA_R[0]
set_location_assignment PIN_G1 -to VGA_R[1]
set_location_assignment PIN_L3 -to VGA_R[2]
set_location_assignment PIN_E6 -to VGA_R[3]
set_location_assignment PIN_G5 -to VGA_R[4]
set_location_assignment PIN_L4 -to VGA_R[5]
#
set_location_assignment PIN_L8 -to VGA_B[0]
set_location_assignment PIN_K5 -to VGA_B[1]
set_location_assignment PIN_L1 -to VGA_B[2]
set_location_assignment PIN_N1 -to VGA_B[3]
set_location_assignment PIN_P1 -to VGA_B[4]
set_location_assignment PIN_R1 -to VGA_B[5]
#
set_location_assignment PIN_L7 -to VGA_G[0]
set_location_assignment PIN_M10 -to VGA_G[1]
set_location_assignment PIN_L2 -to VGA_G[2]
set_location_assignment PIN_N2 -to VGA_G[3]
set_location_assignment PIN_P2 -to VGA_G[4]
set_location_assignment PIN_T2 -to VGA_G[5]
#
set_location_assignment PIN_K1 -to VGA_HS
set_location_assignment PIN_K2 -to VGA_VS

# lector de MINI-SD
set_location_assignment PIN_F3 -to SD_CLK
set_location_assignment PIN_F2 -to SD_MOSI
set_location_assignment PIN_G2 -to SD_MISO
set_location_assignment PIN_D1 -to SD_CS_N
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_MISO

# SDRAM 
set_location_assignment PIN_B10 -to SDRAM_A[0]
set_location_assignment PIN_A11 -to SDRAM_A[1]
set_location_assignment PIN_B11 -to SDRAM_A[2]
set_location_assignment PIN_A12 -to SDRAM_A[3]
set_location_assignment PIN_D14 -to SDRAM_A[4]
set_location_assignment PIN_D12 -to SDRAM_A[5]
set_location_assignment PIN_D11 -to SDRAM_A[6]
set_location_assignment PIN_C14 -to SDRAM_A[7]
set_location_assignment PIN_C11 -to SDRAM_A[8]
set_location_assignment PIN_C9 -to SDRAM_A[9]
set_location_assignment PIN_A10 -to SDRAM_A[10]
set_location_assignment PIN_C8 -to SDRAM_A[11]
set_location_assignment PIN_C6 -to SDRAM_A[12]
#
set_location_assignment PIN_A2 -to SDRAM_DQ[0]
set_location_assignment PIN_B3 -to SDRAM_DQ[1]
set_location_assignment PIN_A3 -to SDRAM_DQ[2]
set_location_assignment PIN_B4 -to SDRAM_DQ[3]
set_location_assignment PIN_A4 -to SDRAM_DQ[4]
set_location_assignment PIN_B5 -to SDRAM_DQ[5]
set_location_assignment PIN_A5 -to SDRAM_DQ[6]
set_location_assignment PIN_B6 -to SDRAM_DQ[7]
set_location_assignment PIN_A14 -to SDRAM_DQ[8]
set_location_assignment PIN_B13 -to SDRAM_DQ[9]
set_location_assignment PIN_A13 -to SDRAM_DQ[10]
set_location_assignment PIN_B12 -to SDRAM_DQ[11]
set_location_assignment PIN_D6 -to SDRAM_DQ[12]
set_location_assignment PIN_D5 -to SDRAM_DQ[13]
set_location_assignment PIN_C3 -to SDRAM_DQ[14]
set_location_assignment PIN_D3 -to SDRAM_DQ[15]
#
set_location_assignment PIN_A15 -to SDRAM_CKE
set_location_assignment PIN_B14 -to SDRAM_CLK
set_location_assignment PIN_A7 -to SDRAM_nCAS
set_location_assignment PIN_D8 -to SDRAM_nRAS
set_location_assignment PIN_B7 -to SDRAM_nWE
set_location_assignment PIN_E8 -to SDRAM_nCS
#
set_location_assignment PIN_E9 -to SDRAM_BA[0]
set_location_assignment PIN_D9 -to SDRAM_BA[1]
set_location_assignment PIN_A6 -to SDRAM_DQML
set_location_assignment PIN_E11 -to SDRAM_DQMH
