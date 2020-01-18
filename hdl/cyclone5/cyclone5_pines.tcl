# pin & location assignments
# ==========================
# reloj principal de 50mhz
set_location_assignment PIN_M9 -to CLOCK_50

# BOTONES
set_location_assignment PIN_AB13 -to BTN[0]
set_location_assignment PIN_V18 -to BTN[1]

# LEDS
set_location_assignment PIN_D17 -to LED

# RATON
set_location_assignment PIN_K22 -to PS2_MCLK
set_location_assignment PIN_K21 -to PS2_MDAT
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_MCLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_MDAT

# TECLADO
set_location_assignment PIN_N16 -to PS2_CLK
set_location_assignment PIN_M16 -to PS2_DATA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_DATA
# SONIDO
set_location_assignment PIN_E7 -to AUDIO_L
set_location_assignment PIN_D6 -to AUDIO_R

# JOYS
set_location_assignment PIN_C16 -to JOY_CLK
set_location_assignment PIN_B16 -to JOY_LOAD
set_location_assignment PIN_B15 -to JOY_DATA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to JOY_DATA

# VGA 
set_location_assignment PIN_G8 -to VGA_R[0]
set_location_assignment PIN_G6 -to VGA_R[1]
set_location_assignment PIN_H6 -to VGA_R[2]
set_location_assignment PIN_C1 -to VGA_R[3]
set_location_assignment PIN_C2 -to VGA_R[4]
set_location_assignment PIN_E2 -to VGA_R[5]
#
set_location_assignment PIN_G1 -to VGA_B[0]
set_location_assignment PIN_L1 -to VGA_B[1]
set_location_assignment PIN_N1 -to VGA_B[2]
set_location_assignment PIN_U1 -to VGA_B[3]
set_location_assignment PIN_Y3 -to VGA_B[4]
set_location_assignment PIN_AA2 -to VGA_B[5]
#
set_location_assignment PIN_D3 -to VGA_G[0]
set_location_assignment PIN_G2 -to VGA_G[1]
set_location_assignment PIN_L2 -to VGA_G[2]
set_location_assignment PIN_N2 -to VGA_G[3]
set_location_assignment PIN_U2 -to VGA_G[4]
set_location_assignment PIN_W2 -to VGA_G[5]
#
set_location_assignment PIN_F7 -to VGA_HS
set_location_assignment PIN_H8 -to VGA_VS

# lector de MINI-SD
set_location_assignment PIN_M22 -to SD_CLK
set_location_assignment PIN_K17 -to SD_MOSI
set_location_assignment PIN_L22 -to SD_MISO
set_location_assignment PIN_L17 -to SD_CS_N
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_MISO

# SDRAM 
set_location_assignment PIN_P8 -to SDRAM_A[0]
set_location_assignment PIN_P7 -to SDRAM_A[1]
set_location_assignment PIN_N8 -to SDRAM_A[2]
set_location_assignment PIN_N6 -to SDRAM_A[3]
set_location_assignment PIN_U6 -to SDRAM_A[4]
set_location_assignment PIN_U7 -to SDRAM_A[5]
set_location_assignment PIN_V6 -to SDRAM_A[6]
set_location_assignment PIN_U8 -to SDRAM_A[7]
set_location_assignment PIN_T8 -to SDRAM_A[8]
set_location_assignment PIN_W8 -to SDRAM_A[9]
set_location_assignment PIN_R6 -to SDRAM_A[10]
set_location_assignment PIN_T9 -to SDRAM_A[11]
set_location_assignment PIN_Y9 -to SDRAM_A[12]
#
set_location_assignment PIN_AA12 -to SDRAM_DQ[0]
set_location_assignment PIN_Y11 -to SDRAM_DQ[1]
set_location_assignment PIN_AA10 -to SDRAM_DQ[2]
set_location_assignment PIN_AB10 -to SDRAM_DQ[3]
set_location_assignment PIN_Y10 -to SDRAM_DQ[4]
set_location_assignment PIN_AA9 -to SDRAM_DQ[5]
set_location_assignment PIN_AB8 -to SDRAM_DQ[6]
set_location_assignment PIN_AA8 -to SDRAM_DQ[7]
set_location_assignment PIN_U10 -to SDRAM_DQ[8]
set_location_assignment PIN_T10 -to SDRAM_DQ[9]
set_location_assignment PIN_U11 -to SDRAM_DQ[10]
set_location_assignment PIN_R10 -to SDRAM_DQ[11]
set_location_assignment PIN_R11 -to SDRAM_DQ[12]
set_location_assignment PIN_U12 -to SDRAM_DQ[13]
set_location_assignment PIN_R12 -to SDRAM_DQ[14]
set_location_assignment PIN_P12 -to SDRAM_DQ[15]
#
set_location_assignment PIN_V9 -to SDRAM_CKE
set_location_assignment PIN_AB11 -to SDRAM_CLK
set_location_assignment PIN_AA7 -to SDRAM_nCAS
set_location_assignment PIN_AB6 -to SDRAM_nRAS
set_location_assignment PIN_W9 -to SDRAM_nWE
set_location_assignment PIN_AB5 -to SDRAM_nCS
#
set_location_assignment PIN_T7 -to SDRAM_BA[0]
set_location_assignment PIN_P9 -to SDRAM_BA[1]
set_location_assignment PIN_AB7 -to SDRAM_DQML
set_location_assignment PIN_V10 -to SDRAM_DQMH
