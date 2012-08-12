
	list p=12F675
	#include <p12F675.inc>

; Simulate a saw tooth overlayed on the signal which will
;   cause the LEDs to transition between states.
;   amplitude equivalent to 15mV on the 12V supply line for each step. 
; The saw tooth runs from NOISE_AMPLITUDE + OFFSET to 1 + OFFSET, so
; +2 to -2 in this case, or +-30mV
	#define NOISE_AMPLITUDE 5
	#define NOISE_OFFSET -3



	__CONFIG	_MCLRE_ON & _BODEN_OFF & _CP_OFF & _PWRTE_ON & _CPD_OFF & _WDT_OFF & _INTRC_OSC_NOCLKOUT

varsWorking		UDATA_SHR	 ; It only has shared memory.	
tmp				RES .1		; Temporary work variable
noise			RES .1		
ramTables		RES .18

BOOTVEC	CODE 0x00
	goto main

INTVEC	CODE 0x04
	; Use the interrupt to wake from sleep, but allow the main loop to process the event.
	retfie

codeMain	CODE
;--------------------------------------------------------------------------------
; Initialisation
;--------------------------------------------------------------------------------
main

	BCF		STATUS, RP0		; Bank 0
	movlw	b'10001101'		; Right justified, input AN3, enabled, stopped
	movwf	ADCON0

	movlw	b'00000111'		; Disable the comparator
	movwf	CMCON


; Set up GPIO - GP4(AN3) and MCLR are inputs. Rest are outputs 
	BSF		STATUS, RP0		; Bank 1
	movlw	b'10001111'
	movwf	OPTION_REG


; Using interrupts for the ADC module
;	movlw	b'11000000'		; Global and Peripheral interrupt enable
;	movwf	INTCON
	clrf	INTCON
	
	movlw	b'01000000'		; ADC interrupt enable to escape SLEEP
	movwf	PIE1

; Set up ADC to read AN3, use top 2 bits and bottom 8 bits.
; Use internal timer to allow operation in SLEEP.
	movlw	b'00111000'		; Internal clock, AN3 enabled
	movwf	ANSEL

	movlw	b'00011000'
	movwf	TRISIO

	BCF		STATUS, RP0		; Bank 0

;	DEBUG
	movlw	b'11011111' ;; blue
	movwf	GPIO


; Populate the tables 
	bsf 	STATUS, RP0		; Bank 1 for EEPROM access

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

	movlw NOISE_AMPLITUDE
	movwf noise

;--------------------------------------------------------------------------------
; Main Loop
;--------------------------------------------------------------------------------
mainLoop

	; DEBUG
;	movlw	b'11111110' ;; red
;	movwf	GPIO


; Trigger the ADC, go into sleep, then to be sure poll for completion. 
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

; Apply the saw tooth to the signal, preventing it wrapping
	addwf	noise, W
	addlw	NOISE_OFFSET
	xorwf	tmp, F		; This will leave the MSB 0 if the sign bit has not changed
	btfss	tmp, 7
		clrf	tmp		; The XOR after a CLR is equivalent to a MOVWF to save the value
	xorwf	tmp, F		; The XOR without the CLR undoes the previous XOR 

; Move the noise value ready for next time
	decfsz	noise, F
		goto testUpperBits
	movlw NOISE_AMPLITUDE
	movwf noise

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
	movf	INDF, W
	movwf	GPIO

	goto mainLoop

	END

