BatteryMonitor
==============

Battery monitor for lead acid batteries based on PIC12F675

The initial version is to monitor a lead acid leisure battery on holiday, and the smaller AGM battery I use for radio.

The requirements were:
----------------------

* Detect low voltage, show progress of discharge.
* Detect high voltage due to a possibly faulty charge. Monitor the charger's behaviour.

The device has 4 LEDs, a red,orange,green traffic light and a separate green LED to show external charge. (This is
identified as "blue" in the code. I didn't have a blue low current LED.)

Thresholds are:
---------------

The system can measure between 10V and 15V with 8 bit resolution. Accuracy depends on the precision of the supply voltage
regulator. Mine achieves 1%. There are quite precise units on the market. The supply voltage is divided by 3 using a
resistor chain of 3 10K resistors, with a small capacitor across the bottom resistor to reduce noise and satisfy the
PIC's requirement for lower ADC source impedance.

    >14.8V     BLUE, RED              Overcharge
    >14.5V     BLUE, ORANGE           14.7V Topping charge for AGM
    >13.9V     BLUE, GREEN, ORANGE    14.4V Topping charge for wet cell
    >13.0V     BLUE, GREEN            13.8V Float
    >12.4V     GREEN                  75% - 100%
    >12V       GREEN, ORANGE          50-75%
    >11.75V           ORANGE          
    >11.3V            ORANGE, RED
    <11.3V                    RED     10%

These thresholds may need revision as there is conflicting information online about lead acid discharge curves. They
are defined in the file "data.asm". 

Future Possibility?
-------------------

It would be nice to switch between battery profiles. I also have 13.2V NiMH packs I use for radio.

I'd hoped to connect a switch to GP3, the "MCLR" input. Unfortunately my programmer does not allow me to program a
device that has both this input enabled and internal clock set. I could use GP2 for the switch. This is currently the
red LED, but it makes sense for red to flash and the switch can be read whenever the red LED is off. The LED would
provide a "weak pull-up" for the switch circuit.

 