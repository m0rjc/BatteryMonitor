
	list p=12F675
	#include <p12F675.inc>


; Pin assignments - bring a pin low to light an LED
; AND these constants together to produde a lighting state.
	#define RED        b'11111110'			; GP0
	#define ORANGE     b'11111101'			; GP1
	#define GREEN      b'11111011'			; GP2
	#define BLUE	   b'11011111'			; GP5


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
romTables	
	de .2,  RED								; Up to 10%
	de .31, RED & ORANGE					; Up to 30%
	de .17, ORANGE							; Up to 50%
	de .27, ORANGE & GREEN					; Up to 75%
	de .41, GREEN							; Up to 100%
	de .61, GREEN & BLUE					; Float Charge
	de .41, ORANGE & BLUE					; Topping Charge
	de .21, ORANGE & RED & BLUE				; Topping Charge for AGM
	de  0,  RED & BLUE						; (Terminator) Overcharge/Reconditioning

	END
