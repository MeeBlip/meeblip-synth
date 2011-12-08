MeeBlip README - 2011.12.01
---------------------------

MeeBlip, the hackable digital synthesizer lives at meeblip.com


The Meeblip project is split into three repositories:

meeblip-synth: 		Source code and hex files for programming all Meeblips
meeblip-circuits:	Schematics and board layout
meeblip-design:		Panel overlay artwork and dimensional drawings


Within meeblip-synth, you'll find files for three different types of Meeblip:

1. meeblip-se: 		Source code and firmware for Version 1 hardware (no save/load/midi buttons). 
					This build does not include patch memories and uses the MIDI DIP switch on the
					front panel to set the MIDI IN channel. 
					
2. meeblip-se-v2:	Source code and firmware for Version 2 hardware. This build includes 16 patch memories
					and programmable MIDI channel select (channels 1-15, plus omni mode if you select Ch 16).
					Patches are saved/loaded by tapping the save/load button and releasing. The power LED
					will blink. flip up/down the appropriate patch switch to save/load. The power LED will
					stop blinking. MIDI channel select works in the same manner. The save/load process will
					time out about 5 seconds after pressing the button if you don't select a patch, and 
					the LED will stop blinking. 
					
3. meeblip-micro:	Source code and firmware for the micro board. This build includes 8 optional analog inputs
					and 8 digital "on/off" switches. It automatically loads Patch 0 from eeprom. 

					
Other files in meeblip-synth:
-----------------------------

make-se:			Batch file for avrdude that loads the se firmware, sets the microcontroller's internal fuses and
					loads a default eeprom bank for Version 1 hardware. meeblip1hardware.eep contains default knob 
					settings to avoid powering up with a blank patch. These are retained in eeprom.
					
make-se:			Same for V2 hardware. Loads patches into eeprom from meeblip.eep

make-micro:			Samve for micro hardware. Loads patches into eeprom from meeblip.eep					
					
					
					