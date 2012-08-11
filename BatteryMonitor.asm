
	list p=12F675
	#include <p12F675.inc>

; Simulate a saw tooth overlayed on the signal which will
;   cause the LEDs to transition between states.
;   amplitude equivalent to 15mV on the 12V supply line for each step. 
; The saw tooth runs from NOISE_AMPLITUDE + OFFSET to 1 + OFFSET, so
; +2 to -2 in this case, or +-30mV
	#define NOISE_AMPLITUDE 5
	#define NOISE_OFFSET -3

	__CONFIG	_MCLRE_OFF & _BODEN_OFF & _CP_OFF & _PWRTE_ON & _CPD_OFF & _WDT_OFF & _INTRC_OSC_NOCLKOUT

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

; Set up GPIO - Analog 0 and 4 outputs 
	BSF		STATUS, RP0		; Bank 1
	movlw	b'10001111'
	movwf	OPTION_REG

	movlw	b'00001001'
	movwf	TRISIO

; Using interrupts for the ADC module
;	movlw	b'11000000'		; Global and Peripheral interrupt enable
;	movwf	INTCON
	clrf	INTCON
	
	movlw	b'01000000'		; ADC interrupt enable to escape SLEEP
	movwf	PIE1

; Set up ADC to read GP0, use top 2 bits and bottom 8 bits.
; Use internal timer to allow operation in SLEEP.
	movlw	b'00110001'		; Internal clock, AN0 enabled
	movwf	ANSEL

	BCF		STATUS, RP0		; Bank 0
	movlw	b'10000001'		; Right justified, input AN0, enabled, stop
	movwf	ADCON0

	movlw	b'00000111'		; Disable the comparator
	movwf	CMCON

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

; Trigger the ADC, go into sleep, then to be sure poll for completion. 
	BCF 	STATUS, RP0		; Bank 0. Optional in current code.
	BSF		ADCON0,	1		; GO
	SLEEP
	NOP
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


;--------------------------------------------------------------------------------
; Data
;
; Two tables of 9 bytes interleaved:
;
;    8 bytes of amount to subtract for each test, then a zero terminator
;	 8 bytes of the LED outputs if that test takes the level below zero, then one more
;      should no tests take it below zero.
;--------------------------------------------------------------------------------
progData	CODE

; With a 1/3 divider from the supply voltage we get
;
;	Threshold	Input to ADC	Top 2 bits	Bottom 8 bits	Subtract
;	infinite	>4.93										terminator	Overcharge															
;	14.8		4.93				3			241			21		   	Topping charge AGM (14.7)										
;	14.5		4.83				3			220			41		   	Topping charge (14.4)
;	13.9		4.63				3			179			81		   	Float (should be 13.8)  													
;	12.7		4.23				3			98			31		   	100%												
;	12.25		4.08				3			67			17			 75%												
;	12	    	4.00				3			50			17			 50%												
;	11.75		3.92				3			33			31		 	 30%													
;	11.3		3.77				3			2			2			 10%
;
; ADC Input resolution is about 5mV, so system resolution about 15mV, 
; but errors in Vref will likely swamp that. 														
;
; Output Wiring as follows:
;
; GP1	Red, ¬Green
; GP2	¬Red, Green
; GP4	¬Orange
; GP5	¬Blue
romTables	
	de .2
	de	b'00110010'			; Less than 10%			          		    RED

	de .31
	de	b'00100010'			; Less than 30%		       		     ORANGE RED

	de .17
	de	b'00100000'			; Less than 50%		       	    	 ORANGE

	de .17
	de	b'00100100'			; Less than 75%		 		   GREEN ORANGE

	de .31
	de	b'00110100'			; Up to 100%		 		   GREEN

	de .81
	de	b'00010100'			; Float charge up to to 13.8V  GREEN             BLUE

	de .41
	de	b'00000000'			; Boost for wet cell to 14.4V        ORANGE      BLUE

	de .21
	de	b'00000010'			; Boost for AGM cell to 14.7V        ORANGE RED  BLUE

	de  0		; Terminator
	de	b'00010010'			; Overcharge								RED  BLUE

	END
