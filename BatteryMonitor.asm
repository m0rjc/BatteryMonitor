
	list p=12F675
	#include <p12F675.inc>

	__CONFIG	_MCLRE_ON & _BODEN_OFF & _CP_OFF & _PWRTE_ON & _CPD_OFF & _WDT_OFF & _INTRC_OSC_NOCLKOUT


;--------------------------------------------------------------------------------
; Constants for the 4 LED circuit.
;--------------------------------------------------------------------------------
; In the 4 LED circuit
; Simulate a saw tooth overlayed on the signal which will
;   cause the LEDs to transition between states.
;   amplitude equivalent to 15mV on the 12V supply line for each step. 
; The saw tooth runs from NOISE_AMPLITUDE + OFFSET to 1 + OFFSET, so
; +2 to -2 in this case, or +-30mV
	#define NOISE_AMPLITUDE 5
	#define NOISE_OFFSET -3

;--------------------------------------------------------------------------------
; Constants for the 4 LED circuit.
;--------------------------------------------------------------------------------
	#define PWM_MAX	8

;--------------------------------------------------------------------------------
; Program
;--------------------------------------------------------------------------------
varsWorking		UDATA_SHR	 ; It only has shared memory.
flags			RES .1		; System state flags
	#define FLAG_CIRCUIT_TYPE 0			; Low for bi-colour circuit, high for 4 LED circuit.
	
tmp				RES .1		; Temporary work variable
noise			RES .1		
ramTables		RES .18

BOOTVEC	CODE 0x00
	goto main

INTVEC	CODE 0x04
	retfie

codeMain	CODE
;--------------------------------------------------------------------------------
; Initialisation
;--------------------------------------------------------------------------------
main

	BCF		STATUS, RP0		; Bank 0

	clrf	flags

	movlw	b'00000111'		; Disable the comparator
	movwf	CMCON

	BSF		STATUS, RP0		; Bank 1

	movlw	b'10001111'
	movwf	OPTION_REG


; Not Using interrupts
; ADC interrupt to escape SLEEP didn't work on real hardware.
; I'm not using TMR1 to flash the LEDs.
	clrf	INTCON
	clrf	PIE1

; Set up ADC to read AN3, use top 2 bits and bottom 8 bits.
; System Clock for 4MHz is Fosc/8, (gives approx 11kS/s )
; AN3 enabled 
	movlw	b'00011000'	
	movwf	ANSEL

	movlw	b'00011010'
	movwf	TRISIO

	BCF		STATUS, RP0		; Bank 0

	movlw	b'10001101'		; Right justified, input AN3, enabled, stopped
	movwf	ADCON0

; Timer 1 with internal clock and 8 times prescaler. Approx 1.9 cycles per second
	movlw	b'00110001'
	movwf	T1CON

;------------------------------------------------------------------------------------------------
; Read GP1 to determine which circuit is in use.
;
; If it is high then it is connected to an LED that is pulled up to Vdd, so the 4 LED circuit
; for use with radios.
;
; If it is low then it is connected to an LED pair that has an additional resistor weak pulling
; it down, so the bi-colour LED circuit for use on the bicycle.
;------------------------------------------------------------------------------------------------
	btfsc	GPIO, GP1
		bsf	flags, FLAG_CIRCUIT_TYPE

	bsf 	STATUS, RP0		; Bank 1 for TRIS and EEPROM access

	movlw	b'00111111'		; Setup for the running system
	movwf	TRISIO

;------------------------------------------------------------------------------------------------
; Populate the tables from EEPROM. 
;------------------------------------------------------------------------------------------------

	movlw	.18
	movwf	tmp
	addlw	ramTables-1
	movwf	FSR
populateLoop
	movf	tmp, W
	addlw	-1
; Read EEPROM
	movwf 	EEADR
	bsf 	EECON1, RD
	movf	EEDATA, W

	movwf	INDF
	decf	FSR, F
	decfsz	tmp, F
	goto populateLoop

	bcf		STATUS, RP0		; Bank 0

;--------------------------------------------------------------------------------
; Set up the 'noise' or PWM variable depending on circuit type.
;--------------------------------------------------------------------------------

	movlw NOISE_AMPLITUDE
	btfss flags, FLAG_CIRCUIT_TYPE		; If it's the bi-colour circuit
		movlw PWM_MAX						;	then set the PWM initial value
		
	movwf noise


;--------------------------------------------------------------------------------
; Main Loop
;--------------------------------------------------------------------------------
mainLoop
; Trigger the ADC, then poll for completion. 
	BCF 	STATUS, RP0		; Bank 0. Optional in current code.
	BSF		ADCON0,	1		; GO
;	SLEEP
;	NOP
adcPoll
	BTFSC	ADCON0,	1		; ¬DONE
	GOTO adcPoll

; Load the low bits of the ADC result into tmp
	BSF		STATUS, RP0
	movf	ADRESL, W
	BCF		STATUS, RP0
	movwf	tmp

; If it's the bi-colour circuit don't add the saw-tooth to the input.
; This will interfere with the bi-colour's PWM output.
	btfss flags, FLAG_CIRCUIT_TYPE
		goto skipNoise


; Apply the saw tooth to the signal, preventing it wrapping
	addwf	noise, W
	addlw	NOISE_OFFSET
	xorwf	tmp, F		; This will leave the MSB 0 if the sign bit has not changed
	btfss	tmp, 7
		clrf	tmp		; The XOR after a CLR is equivalent to a MOVWF to save the value
	xorwf	tmp, F		; The XOR without the CLR undoes the previous XOR 

; Move the noise value ready for next time
	decfsz	noise, F
		goto skipNoise
	movlw NOISE_AMPLITUDE
	movwf noise

skipNoise

; Test the upper bits.
; If the result was too low then we set tmp to 0 to trigger a hit on the first test
testUpperBits
	movlw	3
	subwf	ADRESH, W
	btfss	STATUS, C
	clrf	tmp

; Loop through the tables.
	movlw	ramTables
	movwf	FSR
subtractLoop
	movf	INDF, W		; Reads the subtract value
	btfsc	STATUS, Z	; Check for the terminator
		goto resultFound	; Terminator means use that result
	subwf	tmp, F
	btfss	STATUS, C
		goto resultFound
	incf FSR, F
	incf FSR, F
	goto subtractLoop	
resultFound
	incf FSR, F		; Advance to the value to use
	call display

	goto mainLoop

;--------------------------------------------------------------------------------
; Display function switcher.
; INDF has the display value.
;--------------------------------------------------------------------------------
display
	btfss flags, FLAG_CIRCUIT_TYPE
		goto displayBicolour

;--------------------------------------------------------------------------------
; Display function for the 4 LED circuit.
; INDF has the display value.
;--------------------------------------------------------------------------------
display4Led

	; The LEDs are in the top nibble of INDF
	; Apart from the blue LED which needs placing on GP5
	swapf	INDF, W
	iorlw	b'00100000'		; Turn off Blue LED
	btfss	INDF, 7			; If the bit in the table is clear then...
		andlw b'11011111'		; Turn on Blue LED by clearing its bit in GPIO

	; Flash the red LED if it's on by looking at TMR1H's top bit
	btfsc TMR1H, 7
		iorlw b'00000100'	; Red is on GP2

	; If an LED is off then set it to high impedance so it can
	; be used as an input.
	BSF 	STATUS, RP0		; Bank 1
	andlw b'0100111'
	iorwf TRISIO, F
	iorlw b'1011000'
	andwf TRISIO, F

	; Write the output
	BCF 	STATUS, RP0		; Bank 0
	movf	INDF, W
	movwf	GPIO

	return


;--------------------------------------------------------------------------------
; Display function for the Bi-Colour LED circuit.
; INDF has the display value.
;--------------------------------------------------------------------------------
displayBicolour

	; The value is in the bottom nibble of INDF. Range1 0 to 8
	; The 'noise' variable is used to hold the PWM counter, range 1 to 8
	; 
	; Calculate noise - (INDF + 1) and check "Digit Carry".
	; If the result went negative then show green  (DC=0)
	; 
	movf INDF, W
	addlw 1
	subwf noise, W	

	movlw	b'11111110'		; Red
	btfss STATUS, DC
		movlw b'11111101'	; Green
	
	; Show blue if the top bit of INDF is clear.
	btfss	INDF, 7
		andlw b'11011111'	; GP5 low to show BLUE

	; Flash the LED if bit 6 of INDF is clear.
	btfsc	INDF, 6
		goto bicolourNoFlash
	btfsc	TMR1H, 7
		andlw	b'11111100'	; Take both low to turn off the LED.

bicolourNoFlash

	movwf	GPIO

	; Decrement PWM and reset to 9 on hitting 0.
	decfsz	noise, F
		return
	movlw PWM_MAX
	movwf noise

	return




	END

