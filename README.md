BatteryMonitor
==============

Battery monitor for lead acid batteries based on PIC12F675

The initial version is to monitor a lead acid leisure battery on holiday, and the smaller AGM battery I use for radio.
If I could make it small enough maybe it could fit into the end of a RAYNET connector.

But where, if anywhere, to take it next? The design has a spare input pin. 
I'd thought of making a simple serial interface to allow in-field setup - a resistor, two diodes (unless the port has
somr built in - it's the Vpgm port so maybe not), differential encoding so it doesn't matter what polarity you give it.

An alternative could be to have a couple of pre-programmed profiles. I also use NiMH battery packs by Lumicycle which
have different working voltages to lead acid, so switching at the press of a button could work well.
