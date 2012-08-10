
	list p=12F675
	#include <p12F675.inc>

	__CONFIG	_MCLRE_ON & _CP_OFF & _WDT_OFF & _intRC_OSC

vars	UDATA_ACS
tmp				RES 1
ramTables			RES 18

BOOTVEC	CODE 0x00
	goto main

MAIN	CODE
;--------------------------------------------------------------------------------
; Initialisation
;--------------------------------------------------------------------------------
main

; Not using interrupts
	CLRF	INTCON
	movlw	b'10001111'
	movwf	OPTION

; Set up timer 1 for fairly infrequent polling  (1MHz / 8 / 256 / 256 = approx 2Hz)
	BANKSEL T1CON
	MOVLW b'00110101'  ; Enabled, Internal Clock, Prescale 8
	MOVWF T1CON
	CLRF	TMR1L
	CLRF	TMR1H

; Set up GPIO - Analog 0 and 4 outputs
	movlw	b'00001001'
	tris	GPIO

; Set up ADC to read GP0, use top 2 bits and bottom 8 bits.
; Use internal timer. Then I can change this code to spend most of its time in sleep!

; Populate the tables
	movlw	18
	movwf	tmp
	addlw	ramTables-1
	movwf	FSR
populateLoop
	movf	tmp, W
	addlw	-1
	call 	romTables	; Value now in W
	movwf	INDF
	decf	FSR
	decfsz	tmp
	goto populateLoop

;--------------------------------------------------------------------------------
; Main Loop
;--------------------------------------------------------------------------------
mainLoop

; Trigger the ADC and poll for completion. 
	BANKSEL ADCON0
	BSF		ADCON0	1		; GO
adcPoll
	BTFSC	ADCON0	1		; ¬DONE
	GOTO adcPoll

; Load the low bits of the ADC result into tmp
	BANKSEL ADRESL
	movf	ADRESL, W
	BANKSEL tmp
	movwf	tmp

; Test the upper bits.
; If the result was too low then we set tmp to 0 to trigger a hit on the first test
	BANKSEL ADRESH
	movlw	3
	subwf	ADRESH, W
	BANKSEL tmp
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
	incf FSR
	incf FSR
	goto subtractLoop	
resultWasFound
	incf FSR		; Advance to the value to use
	BANKSEL GPIO
	movf	INDF, W
	movwf	GPIO
	
; Sit polling timer 1. 
	BANKSEL PIR1
	BCF		PIR1
tmrPoll
	BTFSS	PIR1	0
	GOTO tmrPoll

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
romTables	ADDWF PCL
	RETLW 2
	RETLW	b'00110010'			; Less than 10%			          		    RED

	RETLW 31
	RETLW	b'00100010'			; Less than 30%		       		     ORANGE RED

	RETLW 17
	RETLW	b'00100000'			; Less than 50%		       	    	 ORANGE

	RETLW 17
	RETLW	b'00100100'			; Less than 75%		 		   GREEN ORANGE

	RETLW 31
	RETLW	b'00110100'			; Up to 100%		 		   GREEN

	RETLW 81
	RETLW	b'00010100'			; Float charge up to to 13.8V  GREEN             BLUE

	RETLW 41
	RETLW	b'00000000'			; Boost for wet cell to 14.4V        ORANGE      BLUE

	RETLW 21
	RETLW	b'00000010'			; Boost for AGM cell to 14.7V        ORANGE RED  BLUE

	RETLW 0		; Terminator
	RETLW	b'00010010'			; Overcharge								RED  BLUE

	END
