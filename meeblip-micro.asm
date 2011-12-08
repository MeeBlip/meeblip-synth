;-------------------------------------------------------------------------------------------------------------------
;                     _     _  _                     
;                    | |   | |(_)                    
;   ____  _____ _____| |__ | | _ ____      ___ _____ 
;  |    \| ___ | ___ |  _ \| || |  _ \    /___) ___ |
;  | | | | ____| ____| |_) ) || | |_| |  |___ | ____|
;  |_|_|_|_____)_____)____/ \_)_|  __/   (___/|_____)
;                             |_|                  
;
;   meeblip se micro - the hackable digital synthesiser
;
;	For meeblip micro hardware
;
;-------------------------------------------------------------------------------------------------------------------
;
;					Changelog
;V2.01 2011.12.01 - Added inverse sawtooth waveform
;				  - Fixed wavetable overflow in variable pulse calculation 
;				   - Assign individual switches instead of switch matrix	
;				  - Synthesis engine defaults to MIDI channel 1  
;				  - Enable patch load/save and MIDI save functions (careful with V1 hardware - you have to use the DIP switches)
;				  - Increase Portamento rate
;				  - Debugged MIDI CC switch loading routine
;				  - Removed unnecessary opcodes throughout code
;V2.00 2011.11.23 - Bandlimited pulse and PWM wave built from out-of-phase ramps
;				  - Bandlimited square, saw and triangle oscillators
;				  - Patch state engine (independent of front panel controls)
;				  - New knob scan routine (scans only the most recently converted analog channel)			
;				  - Dual ADSD envelopes
;				  - PWM sweep switch and PWM rate knob (limited between 0-50% pulse duty cycle)
;				  - Filter envelop amount knob added
;				  - MIDI control of all parameters
;				  - Reorganized front panel
;				  - MIDI knob and switch CC control
;				  - DCA gate, LFO sync, modulation wheel and filter key track now always on
;				  - LFO enable switch added
;				  - anti-alias switch added - off uses bandlimited wave 0, on uses bandlimited wavetable 0..15, based on note
;				  - Added variable names for switches instead of using bit ops - allows easier reorganization of panel
;				  - FM switch - off or 100%
;				  - New sample rate - 36363.63636 Hz, approximately 440 instructions per sample 
;V1.05 2011.02.04 - Save dual parameter knob values to eeprom and reload on power up.
;V1.04 2011.01.19 - MIDI CC RAM table added.
;		 		  - PWM waveform with dedicated fixed sweep LFO
; 	     		  - 8-bit multiplies optimized in main loop
;				  - LFO Sync switch now retriggers LFO on each keypress
;				  - Initialize FM Depth to zero on power up
;V1.03	 		  - VCA and VCF level tables extended to reduce stairstepping
;V1.02	 		  - Flip DAC write line high immediately after outputting sample
;V1.01	 		  - Optimized DCOA+DCOB summer, outputs signed value
;V1.00   		  - Power/MIDI status LED remains on unless receiving MIDI
;        		  - Sustain level of ADSR envelope is exponentially scaled
;        		  - Non-resonant highpass filter implemented
;        		  - Filter Q level compensation moved outside audio sample calc interrupt
;        		  - Filter calculations increased to 16x8-bit to reduce noise floor
;        		  - DCA output level calculations are rounded
;        		  - Mod wheel no longer overrides LFO level knob when less than knob value
;V0.90   		  - Initial release 
;
;-------------------------------------------------------------------------------------------------------------------
;
;	MeeBlip Contributors
;
;	Jarek Ziembicki	- Created the original AVRsynth, upon which this project is based.
; 	Laurie Biddulph	- Worked with Jarek to translate his comments into English, ported to Atmega16
;	Daniel Kruszyna	- Extended AVRsynth (several of his ideas are incorporated in MeeBlip)
;  	Julian Schmidt	- Original filter algorithm
;	James Grahame 	- Ported and extended the AVRsynth code to MeeBlip hardware.
;
;-------------------------------------------------------------------------------------------------------------------
;
;	Port Mapping
;
;	PA0..7		8 potentiometers
;	PB0-PB4		Control Panel Switches - ROWS
;	PB5-PB7		ISP programming header
;	PB7			DAC LDAC signal (load both DAC ports synchronously)
;	PC0-PC7		DATA port for DAC
;	PD0		    RxD (MIDI IN)
;	PD1		    Power ON/MIDI LED
;	PD2		    Select DAC port A or B
;	PD3		    DAC Write line
;	PD4-PD7		Control Panel Switches - COLUMNS
;
;	Timers	
;
;	Timer0		not used
;	Timer1		Time counter: CK/400      --> TCNT1 
;	Timer2		Sample timer: (CK/8) / 32 --> 36363.63636 Hz
;
;-------------------------------------------------------------------------------------------------------------------

                    .NOLIST
                   ; .INCLUDE "m32def.inc"
                    .LIST
                    .LISTMAC

                    .SET cpu_frequency = 16000000
                    .SET baud_rate     = 31250
		            .SET KBDSCAN       = 6250	
;
;-------------------------------------------------------------------------------------------------------------------
;			V A R I A B L E S   &  D E F I N I T I O N S
;-------------------------------------------------------------------------------------------------------------------
;registers:

;current phase of DCO A:
.DEF PHASEA_0	    = 	r2
.DEF PHASEA_1	    = 	r3
.DEF PHASEA_2	    = 	r4

;current phase of DCO B:
.DEF PHASEB_0	    = 	r5
.DEF PHASEB_1	    = 	r6
.DEF PHASEB_2	    = 	r7

.DEF ZERO           =   r8

;DCF:

.def a_L 			= r9
.def a_H 			= r10
.def temp_SREG		= r11
.def z_L 			= r18
.def z_H 			= r19
.def temp	 		= r30
.def temp2			= r31

.DEF OSC_OUT_L  = 	r14 ; pre-filter audio
.DEF OSC_OUT_H  = 	r15 

.def LDAC			= r16
.def HDAC			= r17

;RAM (0060h...025Fh):

                    .DSEG
;MIDI:
MIDIPHASE:          .BYTE 1
MIDICHANNEL:        .BYTE 1
MIDIDATA0:	        .BYTE 1
MIDIVELOCITY:	    .BYTE 1
MIDINOTE:	        .BYTE 1
MIDINOTEPREV:	    .BYTE 1		        ; buffer for MIDI note
MIDIPBEND_L:        .BYTE 1		        ;\
MIDIPBEND_H:        .BYTE 1		        ;/ -32768..+32766

;current sound parameters:
LFOLEVEL:	        .BYTE 1	            ; 0..255
KNOB_SHIFT:			.BYTE 1				; 0= unchanged 255= changed state  
POWER_UP:			.BYTE 1				; 255 = Synth just turned on, 0 = normal operation
KNOB0_STATUS:		.BYTE 1				; Each byte corresponds to a panel knob.
KNOB1_STATUS:		.BYTE 1				; 0 = pot not updated since Knob Shift switch change
KNOB2_STATUS:		.BYTE 1				; 1 = pot has been updated. 
KNOB3_STATUS:		.BYTE 1
KNOB4_STATUS:		.BYTE 1
KNOB5_STATUS:		.BYTE 1
KNOB6_STATUS:		.BYTE 1
KNOB7_STATUS:		.BYTE 1

SWITCH1:	        .BYTE 1	            
SWITCH2:	        .BYTE 1	            
OLD_SWITCH1:		.BYTE 1				; Previous switch values (used to flag switch changes)
OLD_SWITCH2:		.BYTE 1

										
										; Switch value currently used (from front panel, MIDI or last loaded patch)
PATCH_SWITCH1:		.BYTE 1				
  .equ SW_KNOB_SHIFT	= 0
  .equ SW_OSC_FM		= 1
  .equ SW_LFO_RANDOM	= 2
  .equ SW_LFO_WAVE		= 3
  .equ SW_FILTER_MODE	= 4
  .equ SW_DISTORTION	= 5
  .equ SW_LFO_ENABLE	= 6
  .equ SW_LFO_DEST		= 7

PATCH_SWITCH2:		.BYTE 1
  .equ SW_ANTI_ALIAS	= 0
  .equ SW_OSCB_OCT		= 1
  .equ SW_OSCB_ENABLE	= 2
  .equ SW_OSCB_WAVE		= 3
  .equ SW_SUSTAIN		= 4
  .equ SW_OSCA_NOISE	= 5
  .equ SW_PWM_SWEEP		= 6
  .equ SW_OSCA_WAVE		= 7


SWITCH3:	        .BYTE 1		    	; b0: MIDI SWITCH 1
					                    ; b1: MIDI SWITCH 2
					                    ; b2: MIDI SWITCH 3
					                    ; b3: MIDI SWITCH 4

SETMIDICHANNEL:	    .BYTE 1             ; selected MIDI channel: 0 for OMNI or 1..15
DETUNEB_FRAC:	    .BYTE 1	            ;\
DETUNEB_INTG:	    .BYTE 1	            ;/ -128,000..+127,996
ATTACKTIME:	        .BYTE 1	            ; 0..255
DECAYTIME:			.BYTE 1				; 0..255
SUSTAINLEVEL:		.BYTE 1				; 0/255
RELEASETIME:        .BYTE 1	            ; 0..255
ATTACKTIME2:	    .BYTE 1				; 0..255
DECAYTIME2:			.BYTE 1				; 0..255
SUSTAINLEVEL2:		.BYTE 1				; 0/255
RELEASETIME2:        .BYTE 1	        ; 0..255
NOTE_L:		        .BYTE 1
NOTE_H:		        .BYTE 1
NOTE_INTG:	        .BYTE 1
PORTACNT:	        .BYTE 1		        ; 2 / 1 / 0
LPF_I:		        .BYTE 1
HPF_I:				.BYTE 1
LEVEL:		        .BYTE 1		        ; 0..255
PITCH:		        .BYTE 1		        ; 0..96
ADC_CHAN:	        .BYTE 1		        ; 0..7
PREV_ADC_CHAN:		.BYTE 1				; 0..7
ADC_0:		        .BYTE 1				; Panel knob values.
ADC_1:		        .BYTE 1
ADC_2:		        .BYTE 1
ADC_3:		        .BYTE 1
ADC_4:		        .BYTE 1
ADC_5:		        .BYTE 1
ADC_6:		        .BYTE 1
ADC_7:		        .BYTE 1
OLD_ADC_0:			.BYTE 1				; Previous panel knob value
OLD_ADC_1:			.BYTE 1
OLD_ADC_2:			.BYTE 1
OLD_ADC_3:			.BYTE 1
OLD_ADC_4:			.BYTE 1
OLD_ADC_5:			.BYTE 1
OLD_ADC_6:			.BYTE 1
OLD_ADC_7:			.BYTE 1
GATE:		        .BYTE 1		        ; 0 / 1
GATEEDGE:	        .BYTE 1		        ; 0 / 1
TPREV_KBD_L:	    .BYTE 1
TPREV_KBD_H:	    .BYTE 1
TPREV_L:	        .BYTE 1
TPREV_H:	        .BYTE 1
DELTAT_L:	        .BYTE 1		        ;\ Time from former course
DELTAT_H:	        .BYTE 1		        ;/ of the main loop (1 bit = 32 µs)
ENVPHASE:	        .BYTE 1		        ; 0=stop 1=attack 2=decay 3=sustain 4=release
ENV_FRAC_L:	        .BYTE 1
ENV_FRAC_H:	        .BYTE 1
ENV_INTEGR:	        .BYTE 1
ENVPHASE2:	        .BYTE 1		        ; 0=stop 1=attack 2=decay 3=sustain 4=release
ENV_FRAC_L2:	    .BYTE 1
ENV_FRAC_H2:	    .BYTE 1
ENV_INTEGr2:	    .BYTE 1

LFOPHASE:	        .BYTE 1		        ; 0=up 1=down
LFO_FRAC_L:	        .BYTE 1		        ;\
LFO_FRAC_H:	        .BYTE 1		        ; > -128,000..+127,999
LFO_INTEGR:	        .BYTE 1		        ;/
LFOVALUE:	        .BYTE 1		        ; -128..+127
LFO2PHASE:	        .BYTE 1		        ; 0=up 1=down
LFO2_FRAC_L:	    .BYTE 1		        ;\
LFO2_FRAC_H:	    .BYTE 1		        ; > -128,000..+127,999
LFO2_INTEGR:	    .BYTE 1		        ;/
LFO2VALUE:	        .BYTE 1		        ; -128..+127
OLDWAVEA:	        .BYTE 1
OLDWAVEB:	        .BYTE 1
SHIFTREG_0:	        .BYTE 1		        ;\
SHIFTREG_1:	        .BYTE 1		        ; > shift register for
SHIFTREG_2:	        .BYTE 1		        ;/  pseudo-random generator
LFOBOTTOM_0:        .BYTE 1		        ;\
LFOBOTTOM_1:        .BYTE 1		        ; > bottom level of LFO
LFOBOTTOM_2:        .BYTE 1		        ;/
LFOTOP_0:	        .BYTE 1		        ;\
LFOTOP_1:	        .BYTE 1		        ; > top level of LFO
LFOTOP_2:	        .BYTE 1		        ;/
LFO2BOTTOM_0:       .BYTE 1		        ;\
LFO2BOTTOM_1:       .BYTE 1		        ; > bottom level of LFO2
LFO2BOTTOM_2:       .BYTE 1		        ;/
LFO2TOP_0:	        .BYTE 1		        ;\
LFO2TOP_1:	        .BYTE 1		        ; > top level of LFO2
LFO2TOP_2:	        .BYTE 1		        ;/
DCOA_LEVEL:			.BYTE 1	
DCOB_LEVEL:			.BYTE 1	
KNOB_DEADZONE:		.BYTE 1

; increase phase for DCO A
DELTAA_0: .byte 1
DELTAA_1: .byte 1
DELTAA_2: .byte 1

; increase phase for DCO B
DELTAB_0: .byte 1
DELTAB_1: .byte 1
DELTAB_2: .byte 1

; Wavetable select
WAVETABLE:			.byte 1			; Bandlimited wavetable 0..16

; oscillator pulse width
PULSE_WIDTH:		.byte 1
PULSE_KNOB_LIMITED:	.byte 1

; fm
WAVEB:	  .byte 1
FMDEPTH:  .byte 1

; eeprom 
WRITE_MODE:			.byte 1
WRITE_OFFSET:		.byte 1		; byte 0..15 of the patch
WRITE_PATCH_OFFSET:	.byte 1		; start of patch in eeprom

; filter
SCALED_RESONANCE: .byte 1
b_L:		.byte 1
b_H:		.byte 1

;-------------------------------------------------------------------------------------------------------------------
; MIDI Control Change parameter table
;-------------------------------------------------------------------------------------------------------------------
;
; MIDI CC parameters with an offset from MIDICC. They are automatically
; stored for use, just use the variable name to access their value. 
 

MIDICC:         	.byte $80 
  .equ MIDIMODWHEEL		= MIDICC + $01

    ; Unshifted knobs (potentiometer 0 through 7)
  .equ RESONANCE 		= MIDICC + $30 
  .equ CUTOFF 			= MIDICC + $31
  .equ LFOFREQ 			= MIDICC + $32
  .equ PANEL_LFOLEVEL 	= MIDICC + $33
  .equ VCFENVMOD 		= MIDICC + $34
  .equ PORTAMENTO 		= MIDICC + $35
  .equ PULSE_KNOB 		= MIDICC + $36
  .equ OSC_DETUNE 		= MIDICC + $37 

  ; Shifted knobs (potentiometer 0 through 7)
  ;.equ X 				= MIDICC + $38  
  ;.equ X 				= MIDICC + $39  
  .equ KNOB_DCF_DECAY 	= MIDICC + $3A	
  .equ KNOB_DCF_ATTACK 	= MIDICC + $3B
  .equ KNOB_AMP_DECAY 	= MIDICC + $3C
  .equ KNOB_AMP_ATTACK 	= MIDICC + $3D
  .equ SW1 				= MIDICC + $3E ; Reserved
  .equ SW2 				= MIDICC + $3F ; Reserved 

  ; Panel switches 0..15
  ; Switches 2
  .equ S_KNOB_SHIFT		= MIDICC + $40
  .equ S_OSC_FM			= MIDICC + $41
  .equ S_LFO_RANDOM		= MIDICC + $42
  .equ S_LFO_WAVE		= MIDICC + $43
  .equ S_FILTER_MODE	= MIDICC + $44
  .equ S_DISTORTION		= MIDICC + $45
  .equ S_LFO_ENABLE		= MIDICC + $46
  .equ S_LFO_DEST		= MIDICC + $47
  ; Switches 1
  .equ S_ANTI_ALIAS		= MIDICC + $48
  .equ S_OSCB_OCT		= MIDICC + $49
  .equ S_OSCB_ENABLE	= MIDICC + $4A
  .equ S_OSCB_WAVE		= MIDICC + $4B
  .equ S_SUSTAIN		= MIDICC + $4C
  .equ S_OSCA_NOISE		= MIDICC + $4D
  .equ S_PWM_SWEEP		= MIDICC + $4E
  .equ S_OSCA_WAVE		= MIDICC + $4F

  
; Patch save/load and MIDI channel set
LED_STATUS:		.byte 1				; off/on status of front panel LED
LED_TIMER:		.byte 1				; number of blinks before reset
BUTTON_STATUS:	.byte 1				; MIDI=1, SAVE=3, LOAD=7, CLEAR=0
CONTROL_SWITCH:	.byte 1				; Last panel switch moved: 1..16, where zero indicates no movement.

;-------------------------------------------------------------------------------------------------------------------



;stack: 0x0A3..0x25F
            .ESEG

;-------------------------------------------------------------------------------------------------------------------
;			V E C T O R   T A B L E
;-------------------------------------------------------------------------------------------------------------------
            .CSEG

		    jmp	RESET		            ; RESET

		    jmp	IRQ_NONE	            ; INT0
		    jmp	IRQ_NONE	            ; INT1
		    jmp	IRQ_NONE	            ; INT2

		    jmp	TIM2_CMP	            ; TIMEr2 COMP
		    jmp	IRQ_NONE	            ; TIMEr2 OVF

		    jmp	IRQ_NONE	            ; TIMEr1 CAPT
		    jmp	IRQ_NONE	            ; TIMEr1 COMPA
		    jmp	IRQ_NONE	            ; TIMEr1 COMPB
    		jmp	IRQ_NONE	            ; TIMEr1 OVF

		    jmp	IRQ_NONE	            ; TIMEr0 COMPA
		    jmp	IRQ_NONE	            ; TIMEr0 OVF

		    jmp	IRQ_NONE	            ; SPI,STC

		    jmp	UART_RXC	            ; UART, RX COMPLETE
		    jmp	IRQ_NONE	            ; UART,UDRE
		    jmp	IRQ_NONE	            ; UART, TX COMPLETE

		    jmp	IRQ_NONE	            ; ADC CONVERSION COMPLETE

		    jmp	IRQ_NONE	            ; EEPROM READY

		    jmp	IRQ_NONE	            ; ANALOG COMPARATOR

            jmp IRQ_NONE                ; 2-Wire Serial Interface

            jmp IRQ_NONE                ; STORE PROGRAM MEMORY READY

IRQ_NONE:
            reti
;-------------------------------------------------------------------------------------------------------------------
;			R O M   T A B L E S
;-------------------------------------------------------------------------------------------------------------------
;
; Phase Deltas at 36363.63636 Hz sample rate
;
;  				NOTE PHASE DELTA = 2 ^ 24 * Freq / SamplingFreq
;   	So... 	Note zero calc: 2 ^ 24 * 8.175799 / 36363.63636 = 3772.09651 (stored as 00 0E BC.19)
;
;-------------------------------------------------------------------------------------------------------------------

DELTA_C:
            .DW	0xBC19		            ;\
		    .DW	0x000E		            ;/ note  0 ( 8.175799 Hz) 
DELTA_CIS:
            .DW	0x9C66		            ;\
		    .DW	0x000F		            ;/ note  1 ( 8.661957 Hz) 
DELTA_D:
            .DW	0x8A09		            ;\
		    .DW	0x0010		            ;/ note  2 ( 9.177024 Hz) 
DELTA_DIS:
            .DW	0x85CE		            ;\
		    .DW	0x0011		            ;/ note  3 ( 9.722718 Hz) 
DELTA_E:
            .DW	0x908B		            ;\
		    .DW	0x0012		            ;/ note  4 (10.300861 Hz) 
DELTA_F:
            .DW	0xAB25		            ;\
		    .DW	0x0013		            ;/ note  5 (10.913382 Hz) 
DELTA_FIS:
            .DW	0xD68D		            ;\
		    .DW	0x0014		            ;/ note  6 (11.562326 Hz) 
DELTA_G:
            .DW	0x13C2		            ;\
		    .DW	0x0016		            ;/ note  7 (12.249857 Hz) 
DELTA_GIS:
            .DW	0x63D4		            ;\
		    .DW	0x0017		            ;/ note  8 (12.978272 Hz) 
DELTA_A:
            .DW	0xC7E3		            ;\
		    .DW	0x0018		            ;/ note  9 (13.750000 Hz) 
DELTA_AIS:
            .DW	0x411D		            ;\
		    .DW	0x001A		            ;/ note 10 (14.567618 Hz) 
DELTA_H:
            .DW	0xD0C5		            ;\
		    .DW	0x001B		            ;/ note 11 (15.433853 Hz) 
DELTA_C1:
            .DW	0x7831		            ;\
		    .DW	0x001D		            ;/ note 12 (16.351598 Hz) 

;-----------------------------------------------------------------------------
;
; Lookup Tables
;
; VCF filter cutoff - 128 bytes
; Time to Rate table for calculating amplitude envelopes - 64 bytes
; VCA non-linear level conversion - 256 bytes
;
;-----------------------------------------------------------------------------
; VCF Filter Cutoff
;
; Log table for calculating filter cutoff levels so they sound linear
; to our non-linear ears. 


TAB_VCF:
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0403
     .DW 0x0404
     .DW 0x0404
     .DW 0x0505
     .DW 0x0505
     .DW 0x0606
     .DW 0x0606
     .DW 0x0606
     .DW 0x0807
     .DW 0x0808
     .DW 0x0909
     .DW 0x0A0A
     .DW 0x0A0A
     .DW 0x0C0B
     .DW 0x0C0C
     .DW 0x0D0C
     .DW 0x0F0E
     .DW 0x1110
     .DW 0x1212
     .DW 0x1413
     .DW 0x1615
     .DW 0x1817
     .DW 0x1A19
     .DW 0x1C1B
     .DW 0x201E
     .DW 0x2221
     .DW 0x2423
     .DW 0x2826
     .DW 0x2C2A
     .DW 0x302E
     .DW 0x3432
     .DW 0x3836
     .DW 0x403A
     .DW 0x4442
     .DW 0x4C48
     .DW 0x524F
     .DW 0x5855
     .DW 0x615D
     .DW 0x6865
     .DW 0x706C
     .DW 0x7E76
     .DW 0x8A85
     .DW 0x9690
     .DW 0xA49D
     .DW 0xB0AB
     .DW 0xC4BA
     .DW 0xD8CE
     .DW 0xE8E0
     .DW 0xFFF4

;-----------------------------------------------------------------------------
;Time to Rate conversion table for envelope timing.

TIMETORATE:
		    .DW	50957		            ; 10.54 mS
		    .DW	39621		            ; 13.55 mS
		    .DW	30807		            ; 17.43 mS
		    .DW	23953		            ; 22.41 mS
		    .DW	18625		            ; 28.83 mS
		    .DW	14481		            ; 37.07 mS
		    .DW	11260		            ; 47.68 mS
		    .DW	 8755		            ; 61.32 mS
    		.DW	 6807		            ; 78.87 mS
		    .DW	 5293		            ; 101.4 mS
		    .DW	 4115		            ; 130.5 mS
		    .DW	 3200		            ; 167.8 mS
		    .DW	 2488		            ; 215.8 mS
		    .DW	 1935		            ; 277.5 mS
    		.DW	 1504		            ; 356.9 mS
		    .DW	 1170		            ; 459.0 mS
		    .DW	  909		            ; 590.4 mS
		    .DW	  707		            ; 759.3 mS
		    .DW	  550		            ; 976.5 mS
		    .DW	  427		            ; 1.256 S
    		.DW	  332		            ; 1.615 S
    		.DW   258		            ; 2.077 S
		    .DW	  201		            ; 2.672 S
		    .DW	  156		            ; 3.436 S
		    .DW	  121		            ; 4.419 S
		    .DW	   94		            ; 5.684 S
		    .DW	   73		            ; 7.310 S
		    .DW	   57		            ; 9.401 S
		    .DW	   44		            ; 12.09 S
		    .DW	   35		            ; 15.55 S
		    .DW	   27		            ; 20.00 S
			.DW	   19

;-----------------------------------------------------------------------------
;
; VCA non-linear level conversion 
;
; Amplitude level lookup table. Envelopes levels are calculated as linear 
; and then converted to approximate an exponential saturation curve.

TAB_VCA:
     .DW 0x0000
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0101
     .DW 0x0202
     .DW 0x0202
     .DW 0x0202
     .DW 0x0302
     .DW 0x0303
     .DW 0x0303
     .DW 0x0404
     .DW 0x0404
     .DW 0x0404
     .DW 0x0505
     .DW 0x0505
     .DW 0x0606
     .DW 0x0606
     .DW 0x0606
     .DW 0x0707
     .DW 0x0707
     .DW 0x0707
     .DW 0x0808
     .DW 0x0808
     .DW 0x0808
     .DW 0x0909
     .DW 0x0909
     .DW 0x0909
     .DW 0x0A0A
     .DW 0x0B0B
     .DW 0x0C0C
     .DW 0x0C0C
     .DW 0x0D0D
     .DW 0x0E0E
     .DW 0x0F0F
     .DW 0x1010
     .DW 0x1111
     .DW 0x1212
     .DW 0x1313
     .DW 0x1414
     .DW 0x1515
     .DW 0x1716
     .DW 0x1818
     .DW 0x1A19
     .DW 0x1C1B
     .DW 0x1D1D
     .DW 0x1F1E
     .DW 0x2020
     .DW 0x2121
     .DW 0x2222
     .DW 0x2423
     .DW 0x2525
     .DW 0x2726
     .DW 0x2828
     .DW 0x2A29
     .DW 0x2C2B
     .DW 0x2D2D
     .DW 0x2F2E
     .DW 0x3030
     .DW 0x3131
     .DW 0x3232
     .DW 0x3433
     .DW 0x3535
     .DW 0x3736
     .DW 0x3838
     .DW 0x3939
     .DW 0x3B3A
     .DW 0x3C3C
     .DW 0x3E3D
     .DW 0x403F
     .DW 0x4342
     .DW 0x4444
     .DW 0x4645
     .DW 0x4747
     .DW 0x4948
     .DW 0x4A4A
     .DW 0x4C4B
     .DW 0x4E4D
     .DW 0x504F
     .DW 0x5251
     .DW 0x5453
     .DW 0X5655
     .DW 0x5857
     .DW 0x5A59
     .DW 0x5C5B
     .DW 0x5F5E
     .DW 0x6160
     .DW 0x6462
     .DW 0x6564
     .DW 0x6766
     .DW 0x6A68
     .DW 0x6D6B
     .DW 0x6F6E
     .DW 0x7370
     .DW 0x7573
     .DW 0x7877
     .DW 0x7B7A
     .DW 0x7E7D
     .DW 0x807F
     .DW 0x8382
     .DW 0x8785
     .DW 0x8988
     .DW 0x8E8C
     .DW 0x9190
     .DW 0x9493
     .DW 0x9896
     .DW 0x9C9A
     .DW 0xA09E
     .DW 0xA4A2
     .DW 0xA8A6
     .DW 0xAEAB
     .DW 0xB3B1
     .DW 0xB8B6
     .DW 0xBBBA
     .DW 0xBFBD
     .DW 0xC3C1
     .DW 0xC9C6
     .DW 0xCECC
     .DW 0xD3D1
     .DW 0xD9D6
     .DW 0xE0DD
     .DW 0xE5E3
     .DW 0xEBE8
     .DW 0xF0EE
     .DW 0xF4F2
     .DW 0xF9F6
     .DW 0xFFFC

;-------------------------------------------------------------------------------------------------------------------
;		I N T E R R U P T   S U B R O U T I N E S
;-------------------------------------------------------------------------------------------------------------------
; Timer 2 compare interrupt (sampling)
;
; This is where sound is generated. This interrupt is called 36,363 times per second 
; to calculate a single 16-bit value for audio output. There are ~440 instruction cycles 
; (16MHZ/36,363) between samples, and these have to be shared between this routine and the 
; main program loop that scans controls, receives MIDI commands and calculates envelope, 
; LFO, and DCA/DCF levels.
;
; If you use too many clock cycles here there won't be sufficient time left over for
; general housekeeping tasks. The result will be sluggish and lost notes, weird timing and sadness.
;-------------------------------------------------------------------------------------------------------------------

; Push contents of registers onto the stack
;
TIM2_CMP:
		    push	r16
		    in	    r16, SREG		    ;\
    		push	r16			        ;/ push SREG
		    push	r17
			push    r18
			push	r19
			push 	r20
			push    r21
			push	r22
			push	r23
			push	r30
			push	r31
  			push r0
  			push r1

		    lds	r21, PATCH_SWITCH1		; Load the mode flag settings so we can check the selected waveform,
			lds	r23, PATCH_SWITCH2		; noise and distortion settings.


;-------------------------------------------------------------------------------------------------------------------
;
; Oscillator A & B 
;
; This design uses direct frequency synthesis to generate a ramp wave. A three-byte counter (= phase) is being
; incremented by a value which is proportional to the sound frequency (= phase delta). The
; increment takes place every sampling period. The most significant byte of the counter is a sawtooth ramp. 
; This is either used as a pointer to a 256 byte wavetable or for direct waveform synthesis.
; Each oscillator has its own phase and phase delta registers. The contents of each phase delta 
; register depends on the frequency being generated:
;
;                   PHASE DELTA = 2 ^ 24 * Freq / SamplingFreq
;
; where:
;       SamplingFreq = 40000 Hz
;       Freq = 440 * 2 ^ ((n - 69 + d) / 12)
;       where in turn:
;           n = MIDI note number. Range limited to 36 to 96 (5 octaves)
;           d = transpose/detune (in halftones)
;
;-------------------------------------------------------------------------------------------------------------------


;Calculate DCO A							
												; If Noise switch is on, use pseudo-random shift register value
			sbrs r23, SW_OSCA_NOISE 			; Use noise if bit set, otherwise jump to calculate DCO.
			rjmp CALC_DCOA 		
			lds  r17, SHIFTREG_2
  			sbrc PHASEA_2,3
			com r17
			sbrc PHASEA_2,4
			com r17
			sbrc PHASEA_2,6
			com r17
			sbrc PHASEA_2,7
			com r17
			lsl r17
			rjmp CALC_DCOB						; skip sample calc for DCO A if noise bit set


CALC_DCOA:
		    mov	    r17, PHASEA_2				; sawtooth ramp for OSCA
			sbrs	r23, SW_OSCA_WAVE			; 0/1 (DCO A = saw/pwm)
			rjmp	DCOA_SAW

;Pulse wave generated by subtracting two bandlimited sawtooths, between 0 and 180 degrees out of phase

			sbrs	r23, SW_PWM_SWEEP
			lds		r20, PULSE_KNOB_LIMITED		; PWM Sweep switch is off, so load the knob value as PWM width	
			sbrc	r23, SW_PWM_SWEEP
			lds		r20, PULSE_WIDTH			; PWM Sweep switch is on, load pulse width from LF02
			sbrs	r23, SW_ANTI_ALIAS
			rjmp	RAW_PULSE					; Calculate raw pulse/PWM when anti-alias switch is off

			lds		r22, WAVETABLE				; Offset to the correct wavetable, based on note number (0..15)

			; get sample a into r17
			ldi		ZL, low (2*INV_SAW0)		; Load low part of byte address into ZL
			ldi		ZH, high(2*INV_SAW0)		; Load high part of byte address into ZH
			add		ZL, r17						; Offset the wavetable by the ramp phase (i)
			adc		ZH, r22						; Wavetable 0..15
			lpm									; Load wave(i) into r0

			; get sample b (inverse ramp) out of phase into r18
			mov		r16, r20					; Grab a copy of the pulse width 
			add		r16, r17					; Add phase offset for second table (pulse width + original sample)
			mov		r17, r0						; store previous sample in r17
			ldi		ZL, low (2*SAW_LIMIT0)		; Load low part of byte address into ZL
			ldi		ZH, high(2*SAW_LIMIT0)		; Load high part of byte address into ZH
			add		ZL, r16						; Add phase offset for second table.
			adc		ZH, r22						; Wavetable 0..15
			lpm									; Load wave(i) into r0 
			
			; xyzzy 16-bit result when calculating wave a+b to ensure that we don't overflow 
			clr		r16
			add		r17, r0					; wave a+b, store in r16:r17		
			adc		r16, ZERO
			add		r17, r20					; offset the sample amplitude by wave b offset to counter amplitude shift 
			adc		r16, ZERO
			; Subtract offset
			subi	r17, $FF					; remove byte offset to bring the value back to single byte range
			sbc		r16, ZERO
			brcc	PULSE_BOUND_CHECK			; non-negative result, so no need to limit the value
			ldi		r17, 0
			ldi		r16, 0						; value was negative, so force to zero
PULSE_BOUND_CHECK:
			tst		r16							; Check if we're larger than 255
			breq	PWM_EXIT					; no need to limit upper bound
			ldi		r17, $FF	
PWM_EXIT:
			subi	r17, $80					; sign the result
			rjmp	CALC_DCOB

; Raw Pulse wave generated on the fly. Aliases like crazy (calc'd only when anti-alias switch is OFF)
RAW_PULSE:
			cp		r17, r20			
			brlo	PULSE_ZERO	
			ldi		r17, 255
			subi    r17, $80					; Sign the sample
			rjmp	CALC_DCOB
PULSE_ZERO:
			ldi		r17, 0
			subi    r17, $80					; Sign the sample
			rjmp	CALC_DCOB

; Calculate DCOA sawtooth
DCOA_SAW:
		    mov	    r17, PHASEA_2	    
			sbrs	r23, SW_ANTI_ALIAS
			rjmp	DCOA_SAW_SIGN	
			lds		r22, WAVETABLE				; Offset to the correct wavetable, based on note number (0..15)
			ldi		ZL, low (2*INV_SAW0)		; Load low part of byte address into ZL
			ldi		ZH, high(2*INV_SAW0)		; Load high part of byte address into ZH
			add		ZL, r17						; Offset the wavetable by the ramp phase (i)
			adc		ZH, r22						; Wavetable 0..15
			lpm									;	Load wave(i) into r0
			mov		r17, r0						;	Copy into DCO B
DCOA_SAW_SIGN:
			subi    r17, $80					; -127..127 Sign oscillator

;Calculate DCO B
CALC_DCOB:
			lds		r22, WAVETABLE				; Offset to the correct wavetable, based on note number (0..15)
			sbrs	r23, SW_ANTI_ALIAS
			ldi		r22, 0						; Use wavetable 0 when anti-alias switch off
				
			mov	    r16, PHASEB_2				; Use ramp value as offset when scanning wavetable
		    sbrs	r23, SW_OSCB_WAVE			; 0/1 (DCO B = saw/squ)
			rjmp	LIMITED_TRIB

LIMITED_SQB:									; Square wave lookup
			ldi		ZL, low(2*SQ_LIMIT0)		; Load low part of byte address into ZL
			ldi		ZH, high(2*SQ_LIMIT0)		; Load high part of byte address into ZH
			add		ZL, r16						; Offset the wavetable by the ramp phase (i)
			adc		ZH, r22						; Wavetable 0..15
			lpm									; Load wave(i) into r0
			mov		r16, r0						; Copy into DCO B
			rjmp	CALC_DIST

LIMITED_TRIB:									; Triangle wave lookup
			ldi		ZL, low(2*TRI_LIMIT0)		; Load low part of byte address into ZL
			ldi		ZH, high(2*TRI_LIMIT0)		; Load high part of byte address into ZH
			add		ZL, r16						; Offset the wavetable by the ramp phase (i)
			adc		ZH, r22						; Wavetable 0..15
			lpm									; Load wave(i) into r0
			mov		r16, r0						; Copy into DCO B

CALC_DIST:
			subi    r16, $80			; -127..127 Sign Oscillator B waveform

			sbrc	r21, SW_DISTORTION  ; 0/1 (OSC DIST = off/on)
    		eor	    r17, r16 

			; Turn off OSCB if not enabled
			sbrs	r23, SW_OSCB_ENABLE	
			ldi		r16, $80				; Zero OSCB. Oscillator is signed				


;-------------------------------------------------------------------------------------------------------------------
; Sum Oscillators
;
; Combines DCOA (in r17) and DCOB (in r16) waves to produce a 16-bit signed result in HDAC:LDAC (r17:r16)
; 

			ldi		r22, $80	    
			mulsu	r17, r22			; signed DCO A wave * level
			movw	r30, r0				; store value in temp register
			ldi		r22, $80
			mulsu	r16, r22			; signed DCO B wave * level
			add		r30, r0
			adc 	r31, r1				; sum scaled waves
  			sts 	WAVEB,r16			; store signed DCO B wave for fm 
			movw	r16, r30			; place signed output in HDAC:LDAC
			movw	OSC_OUT_L, r16		; keep a copy for highpass filter

			
			
			; rotate right a couple of times to make a couple of bits of headroom for resonance.  

            asr	    r17		            ;\
		    ror	    r16		            ;/ r17:r16 = r17:r16 asr 1
			asr	    r17		            ;\
		    ror	    r16		            ;/ r17:r16 = r17:r16 asr 1

;DCF:

;-------------------------------------------------------------------------------------------------------------------
; Digitally Controlled Filter
;
; A 2-pole resonant low pass filter:
;
; a += f * ((in - a) + q * (a - b));
; b += f * (a - b); 
;
; Input 16-Bit signed HDAC:LDAC (r17:r16), already scaled to minimize clipping (reduced to 25% of full code).
;-------------------------------------------------------------------------------------------------------------------

                            		;calc (in - a) ; both signed
		sub     LDAC, a_L
        sbc     HDAC, a_H
                            		;check for overflow / do hard clipping
        brvc OVERFLOW_1     		;if overflow bit is clear jump to OVERFLOW_1

        							;sub overflow happened -> set to min
                            		;b1000.0000 b0000.0001 -> min
                            		;0b0111.1111 0b1111.1111 -> max

        ldi    	LDAC, 0b00000001 	
        ldi 	HDAC, 0b10000000	

OVERFLOW_1: 						;when overflow is clear

        							;(in-a) is now in HDAC:LDAC as signed
        							;now calc q*(a-b)

        ; Scale resonance based on filter cutoff
		lds    r22, RESONANCE
		lds    r20, LPF_I    		;load 'F' value
        ldi    r21, 0xff

        sub r21, r20 ; 1-F
        lsr r21
		ldi r18, 32
        add r21, r18

        sub    r22, r21     		; Q-(1-f)
        brcc OVERFLOW_2        		; if no overflow occured
        ldi    r22, 0x00    		;0x00 because of unsigned
        

OVERFLOW_2:
        
        mov    r20, a_L        	  	;\
        mov    r21, a_H            	;/ load 'a' , signed

        lds    z_H, b_H            	;\
        lds    z_L, b_L            	;/ load 'b', signed

        sub    r20, z_L            	;\
        sbc    r21, z_H            	;/ (a-b) signed

        brvc OVERFLOW_3            	;if overflow is clear jump to OVERFLOW_3
        
        							;b1000.0000 b0000.0001 -> min
        							;0b0111.1111 0b1111.1111 -> max

        ldi   r20, 0b00000001
        ldi   r21, 0b10000000

OVERFLOW_3:
        
		lds		r18, PATCH_SWITCH1	; Check Low Pass/High Pass panel switch. 
		sbrs 	r18, SW_FILTER_MODE				
		rjmp	CALC_LOWPASS						
		movw    z_L,r20				; High Pass selected, so just load r21:r20 into z_H:z_L to disable Q 
		rjmp	DCF_ADD				; Skip lowpass calc

CALC_LOWPASS:
									; mul signed:unsigned -> (a-b) * Q
									; 16x8 into 16-bit
									; r19:r18 = r21:r20 (ah:al)	* r22 (b)
		
		mulsu	r21, r22			; (signed)ah * b
		movw	r18, r0
		mul 	r20, r22			; al * b
		add		r18, r1	
		adc		r19, ZERO
		rol 	r0					; r0.7 --> Cy
		brcc	NO_ROUND			; LSByte < $80, so don't round up
		inc 	r18			
NO_ROUND:
        clc
        lsl     r18
        rol     r19
        clc
        lsl     r18
        rol     r19
		movw    z_L,r18        		;Q*(a-b) in z_H:z_L as signed

        ;add both
        ;both signed
        ;((in-a)+q*(a-b))
        ;=> HDAC:LDAC + z_H:z_L
 
 DCF_ADD: 
                
        add     LDAC, z_L
        adc     HDAC, z_H

        brvc OVERFLOW_4            	;if overflow is clear
        						   	;b1000.0000 b0000.0001 -> min 
								   	;0b0111.1111 0b1111.1111 -> max

        ldi    LDAC, 0b11111111
        ldi    HDAC, 0b01111111

OVERFLOW_4:

        							;Result is a signed value in HDAC:LDAC
        							;calc * f 
        							;((in-a)+q*(a-b))*f

        lds    r20, LPF_I         	;load lowpass 'F' value
		lds	   r18, PATCH_SWITCH1		 
		sbrc   r18, SW_FILTER_MODE	; Check LP/HP switch.
		lds    r20, HPF_I			; Switch set, so load 'F' for HP

									; mul signed unsigned HDAC*F
									; 16x8 into 16-bit
									; r19:r18 = HDAC:LDAC (ah:al) * r20 (b)

		mulsu	HDAC, r20			; (signed)ah * b
		movw	r18, r0
		mul 	LDAC, r20			; al * b
		add		r18, r1				; signed result in r19:r18
		adc		r19, ZERO
		rol 	r0					; r0.7 --> Cy
		brcc	NO_ROUND2			; LSByte < $80, so don't round up
		inc 	r18			
NO_ROUND2:
        							;Add result to 'a'
        							;a+=f*((in-a)+q*(a-b))

        add        a_L, r18
        adc        a_H, r19
        brvc OVERFLOW_5           	;if overflow is clear
                                	;b1000.0000 b0000.0001 -> min 
                                	;0b0111.1111 0b1111.1111 -> max

        ldi z_H, 0b11111111
        ldi z_L, 0b01111111
        mov    a_L, z_H
        mov    a_H, z_L

OVERFLOW_5:

        							;calculated a+=f*((in-a)+q*(a-b)) as signed value and saved in a_H:a_L
        							;calc 'b' 
        							;b += f * (a*0.5 - b);  

		mov	z_H, a_H				;\
        mov z_L, a_L         		;/ load 'a' as signed

        lds temp, b_L        		;\
        lds temp2, b_H        		;/ load b as signed

        sub z_L, temp        		;\    			
        sbc z_H, temp2				;/ (a - b) signed

        brvc OVERFLOW_6    			;if overflow is clear
                         			;b1000.0000 b0000.0001 -> min 
						 			;0b0111.1111 0b1111.1111 -> max

        ldi z_L, 0b00000001
        ldi z_H, 0b10000000

OVERFLOW_6:

        lds    r20, LPF_I         	;load lowpass 'F' value
		lds	   r18, PATCH_SWITCH1		 
		sbrc   r18, SW_FILTER_MODE	; Check LP/HP switch.
		lds    r20, HPF_I			; Switch set to HP, so load 'F' for HP

		;mulsu  z_H, r20 			;mul signed unsigned (a-b) * F

								    ; mul signed unsigned (a-b) * F
								    ; 16x8 into 16-bit
								    ; r19:r18 = z_H:z_L (ah:al) * r20 (b)
		mulsu	z_H, r20		    ; (signed)ah * b
		movw	r18, r0
		mul 	z_L, r20		    ; al * b
		add		r18, r1			    ; signed result in r19:r18
		adc		r19, ZERO
                                 	
        
        add temp,  r18          	;\ add result to 'b' , signed
        adc temp2, r19         		;/ b +=(a-b)*f

        brvc OVERFLOW_7          	;if overflow is clear
                
							   		;b1000.0000 b0000.0001 -> min                      
							   		;0b0111.1111 0b1111.1111 -> max

        ldi temp,  0b11111111
        ldi temp2, 0b01111111

OVERFLOW_7:

		sts b_L, temp         		;\
        sts b_H, temp2        		;/ save value of 'b' 

									
        mov LDAC, temp				;B now contains the filtered signal in HDAC:LDAC
        mov HDAC, temp2


		; If in HP filter mode, just use (filter input - filter output)
			
		lds		r18, PATCH_SWITCH1	; Check if LP or HP filter
		sbrs 	r18, SW_FILTER_MODE				
		rjmp	DCA					; LP, so jump to DCA
		sub		OSC_OUT_L, LDAC		; HP filter, so output = filter input - output
		sbc		OSC_OUT_H, HDAC
		movw	LDAC, OSC_OUT_L

									
;-------------------------------------------------------------------------------------------------------------------
; Digitally Controlled Amplifier
;
; Multiply the output waveform by the 8-bit value in LEVEL.
;-------------------------------------------------------------------------------------------------------------------
;

DCA:
		    ldi	    r30, 0
		    ldi	    r31, 0
		    lds	    r18, LEVEL
		    cpi	    r18, 255
		    brne	T2_ACHECK		    ; multiply when LEVEL!=255
		    mov	    r30, r16
		    mov	    r31, r17
		    rjmp	T2_AEXIT

T2_ALOOP:
            asr	    r17		            ;\
		    ror	    r16		            ;/ r17:r16 = r17:r16 asr 1
		    lsl	    r18		            ; Cy <-- r31 <-- 0
		    brcc	T2_ACHECK
    		add	    r30, r16
		    adc	    r31, r17

T2_ACHECK:
            tst	    r18
		    brne	T2_ALOOP

T2_AEXIT:

;-------------------------------------------------------------------------------------------------------------------
; Output Sample
;
; Write the 16-bit signed output of the DCA to the DAC.
;-------------------------------------------------------------------------------------------------------------------
;


;write sample (r31:r30) to DAC:

			sbi		PORTD, 3			; Set WR high
		    subi	r31, 128		    ; U2 --> PB
			cbi		PORTD, 2			; Select DAC port A
			out	    PORTC, r31	        ; output most significant byte
			cbi		PORTD, 3			; Pull WR low to load buffer A
			sbi		PORTD, 3			; Set WR high
			sbi		PORTD, 2			; Select DAC port B
			out	    PORTC, r30	        ; output least significant byte
			cbi		PORTD, 3			; Pull WR low to load buffer B
			sbi		PORTD, 3			; Set WR high again

; Increment Oscillator A & B phase

  			ldi 	r30, low(DELTAA_0)
  			ldi 	r31, high(DELTAA_0)
  			ld 		r16, z+
  			add 	PHASEA_0, r16
  			ld 		r16,z+
  			adc 	PHASEA_1, r16
  			ld 		r16,z+
  			adc 	PHASEA_2, r16
  			ld 		r16,z+
  			add 	PHASEB_0, r16
  			ld 		r16,z+
  			adc 	PHASEB_1, r16
  			ld 		r16, z+
  			adc 	PHASEB_2,r16

;-------------------------------------------------------------------------------------------------------------------
; Frequency Modulation
;-------------------------------------------------------------------------------------------------------------------
; 

dco_fm:

		    lds		r30, PATCH_SWITCH2
			sbrc 	r30, SW_OSCA_NOISE 		;  
			rjmp 	END_SAMPLE_LOOP 		; If DCOA waveform is set to Noise, skip FM
			sbrs	r30, SW_OSCB_ENABLE		; Skip FM is OSCB is turned off
			rjmp	END_SAMPLE_LOOP

			lds	    r30, PATCH_SWITCH1		; Get FM switch value
			sbrs	r30, SW_OSC_FM	
			ldi		r17, 0					; Set FM depth to 0 if switch is off
			sbrc	r30, SW_OSC_FM
			ldi		r17, 255				; Set FM depth to 255 if switch is on

			; mod * depth
			tst 	r17 					; skip if FM depth is zero
			breq	END_SAMPLE_LOOP		
			lds 	r16, WAVEB     

			mulsu 	r16, r17
			movw 	r18, r0

			; delta * mod * depth
			lds 	r16, DELTAA_0
			clr 	r17
			mulsu 	r19, r16
			sbc 	r17, r17
			add 	PHASEA_0, r1
			adc 	PHASEA_1, r17
			adc 	PHASEA_2, r17

			lds 	r16, DELTAA_1
			mulsu 	r19, r16
			add 	PHASEA_0, r0
			adc 	PHASEA_1, r1
			adc 	PHASEA_2, r17

			lds 	r16, DELTAA_2
			mulsu 	r19, r16
			add 	PHASEA_1, r0
			adc 	PHASEA_2, r1

;-------------------------------------------------------------------------------------------------------------------
; End of Sample Interrupt
;
; Pop register values off stack and return to our regularly scheduled programming.
;-------------------------------------------------------------------------------------------------------------------
; 

END_SAMPLE_LOOP:

			pop 	r1
  			pop 	r0
			pop		r31
			pop		r30
			pop		r23
			pop		r22
			pop		r21
			pop		r20
			pop		r19
			pop     r18 
		    pop	    r17
		    pop	    r16		            ;\
		    out	    SREG, r16	        ;/ pop SREG
		    pop	    r16
		    reti

;------------------------
; UART receiver (MIDI IN)
;------------------------
UART_RXC:

            push	r16
		    in	    r16, SREG	        ;\
		    push	r16			        ;/ push SREG

		    in	    r16, UDR	        ; read received byte in r16
		    cbi	    UCR, 7		        ; RXCIE=0 (disable UART interrupts)
		    sei				            ; enable other interrupts
		    push	r17

		    tst	    r16		            ;\ jump when
		    brpl	INTRX_DATA		    ;/ r16.7 == 0 (MIDI data byte)

;MIDI status byte (1xxxxxxx):
		    mov	    r17, r16
		    andi	r17, 0xF0
		    cpi	    r17, 0x80
		    breq	INTRX_ACCEPT	    ; 8x note off
		    cpi	    r17, 0x90
		    breq	INTRX_ACCEPT	    ; 9x note on
		    cpi	    r17, 0xB0
		    breq	INTRX_ACCEPT	    ; Bx control change
		    cpi	    r17, 0xE0
		    breq	INTRX_ACCEPT	    ; Ex pitch bend
		    ldi	    r17, 0		        ;\
		    sts	    MIDIPHASE, r17	    ;/ MIDIPHASE = 0
		    rjmp	INTRX_EXIT		    ; Ax polyphonic aftertouch
						                ; Cx program change
						                ; Dx channel aftertouch
						                ; Fx system

INTRX_ACCEPT:
            sts	    MIDIPHASE, r17	    ; phase = 80 90 B0 E0
		    andi	r16, 0x0F		    ;\
		    inc	    r16			        ; > store MIDI channel 1..16
		    sts	    MIDICHANNEL, r16	;/
		    lds	    r17, SETMIDICHANNEL	;0 for OMNI or 1..15
		    tst	    r17
		    breq	INTRX_ACPT_X		; end when OMNI
		    cp	    r17, r16			; compare set channel to the incoming channel
		    breq	INTRX_ACPT_X		; end when right channel
		    ldi	    r17, 0			    ;\ otherwise:
		    sts	    MIDIPHASE, r17		;/ MIDIPHASE = 0 (no data service)

INTRX_ACPT_X:
            rjmp	INTRX_EXIT

;MIDI data byte (0xxxxxxx):
INTRX_DATA:
            lds	    r17, MIDIPHASE
		    cpi	    r17, 0x80		    ;\
		    breq	INTRX_NOFF1		    ; \
		    cpi	    r17, 0x81		    ; / note off
		    breq	INTRX_NOFF2		    ;/
		    rjmp	INTRX_NOTEON

INTRX_NOFF1:
            inc	    r17			        ;\
		    sts	    MIDIPHASE, r17	    ;/ MIDIPHASE = 0x81
		    sts	    MIDIDATA0, r16	    ; MIDIDATA0 = d
		    rjmp	INTRX_EXIT

INTRX_NOFF2:
            dec	    r17			        ;\
		    sts	    MIDIPHASE, r17	    ;/ MIDIPHASE = 0x80
		    rjmp	INTRXNON2_OFF

;9x note on:
INTRX_NOTEON:
            cpi	    r17, 0x90		    ;\
		    breq	INTRX_NON1		    ; \
		    cpi	    r17, 0x91		    ; / note on
		    breq	INTRX_NON2		    ;/
		    rjmp	INTRX_CTRL

INTRX_NON1:
            inc     r17			        ;\
		    sts	    MIDIPHASE, r17	    ;/ MIDIPHASE = 0x91
		    sts	    MIDIDATA0, r16	    ; MIDIDATA0 = d
		    rjmp	INTRX_EXIT

INTRX_NON2:
            dec	    r17			        ;\
		    sts	    MIDIPHASE, r17	    ;/ MIDIPHASE = 0x90
		    tst	    r16			        ;\
		    brne	INTRXNON2_ON	    ;/ jump when velocity != 0

;turn note off:
INTRXNON2_OFF:
            lds	    r16, MIDIDATA0
		    lds	    r17, MIDINOTEPREV
		    cp	    r16, r17
		    brne	INTRXNON2_OFF1
		    ldi	    r17, 255		    ;\ remove previous note
		    sts	    MIDINOTEPREV, r17	;/ from buffer

INTRXNON2_OFF1:
            lds	    r17, MIDINOTE
		    cp	    r16, r17		    ;\
		    brne	INTRXNON2_OFF3	    ;/ exit when not the same note
		    lds	    r17, MIDINOTEPREV
		    cpi	    r17, 255
		    breq	INTRXNON2_OFF2
		    sts	    MIDINOTE, r17		; previous note is valid
		    ldi	    r17, 255		    ;\ remove previous note
		    sts	    MIDINOTEPREV, r17	;/ from buffer

INTRXNON2_OFF3:
            rjmp	INTRX_EXIT

INTRXNON2_OFF2:
            ldi	    r17, 255		    ;\ remove last note
		    sts	    MIDINOTE, r17		;/
		    ldi	    r17, 0			    ;\
		    sts	    GATE, r17		    ;/ GATE = 0
		    

			sbi	    PORTD, 1		    ; LED on
		    rjmp	INTRX_EXIT

;turn note on:
INTRXNON2_ON:
            sts	    MIDIVELOCITY, r16	; store velocity
		    lds	    r17, MIDINOTE		;\ move previous note
		    sts	    MIDINOTEPREV, r17	;/ into buffer
		    lds	    r17, MIDIDATA0		;\
		    sts	    MIDINOTE, r17		;/ MIDINOTE = note#
		    ldi	    r17, 1
		    sts	    GATE, r17		    ; GATE = 1
		    sts	    GATEEDGE, r17		; GATEEDGE = 1
		    
			cbi	    PORTD, 1		    ; LED off
		    rjmp	INTRX_EXIT

;Bx control change:
INTRX_CTRL:
            cpi	    r17, 0xB0		    ;\
		    breq	INTRX_CC1		    ; \
		    cpi	    r17, 0xB1		    ; / control change
		    breq	INTRX_CC2		    ;/
		    rjmp	INTRX_PBEND

INTRX_CC1:
            inc     r17			        ;\
		    sts	    MIDIPHASE, r17		;/ MIDIPHASE = 0xB1
		    sts	    MIDIDATA0, r16		; MIDIDATA0 = controller#
		    rjmp	INTRX_EXIT

INTRX_CC2:
            dec     r17			        ;\
		    sts	    MIDIPHASE, r17		;/ MIDIPHASE = 0xB0
		    lds	    r17, MIDIDATA0

;Store MIDI CC in table
			push 	r26					; store contents of r27 and r26 on stack
			push	r27

			cpi		r17, $30			; Just save a controller # < $30
			brlo	INTRX_GOSAVE

			cpi		r17, $40			; save, update old knob value and status
			brlo	INTRX_KNOB

			cpi		r17, $50			; save, update old switch value and status
			brlo	INTRX_SW

INTRX_GOSAVE:
			rjmp	INTRX_SAVE			; Save all other controller # > $50

INTRX_KNOB:
			; save the value in the MIDI table
			ldi 	r26,low(MIDICC)			
  			ldi 	r27,high(MIDICC)
  			add 	r26,r17
  			adc 	r27,zero
  			lsl 	r16					; shift MIDI data to 0..254 to match knob value
  			st 		x,r16				; store in MIDI CC table

			; Get ADC_X and write it into OLD_ADC_X
			subi	r17, $30			; reduce to 0..15
			cbr		r17, $f8			; Clear highest 5 bits, leaving knob 0..7		

			ldi 	r26,low(ADC_0)			
  			ldi 	r27,high(ADC_0)
  			add 	r26,r17
  			adc 	r27,zero
			ld		r16, x				; Fetch ADC_X into r16

			ldi 	r26,low(OLD_ADC_0)			
  			ldi 	r27,high(OLD_ADC_0)
  			add 	r26,r17
  			adc 	r27,zero
			st		x, r16				; Store ADC_X in OLD_ADC_X

			; Clear KNOBX_STATUS (knob not moved)
			ldi 	r26,low(KNOB0_STATUS)			
  			ldi 	r27,high(KNOB0_STATUS)
  			add 	r26,r17
  			adc 	r27,zero
			ldi		r17, 0
			st		x, r17				; Clear KNOBX_STATUS
			rjmp	INTRX_CCEND

INTRX_SW:
		subi	r17, $40			; MIDI CC # --> switch offset 0..15

		cpi		r17, $08
		BRLO	INTRX_SWITCH1		; Jump to Switch 1 if switch 0..7 selected.

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -	

INTRX_SWITCH2:		
		
		cbr		r17, $f8			; Clear highest 5 bits, leaving switch 0..7
		lds		r26, PATCH_SWITCH2
		bst	    r16, 6 		; load MSB of MIDI CC value into SREG T bit	
		
		cpi		r17, 0 
		brne	INTRX_S1		
		bld		r26, 0			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S1:
		cpi		r17, 1 
		brne	INTRX_S2		
		bld		r26, 1			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S2:
		cpi		r17, 2 
		brne	INTRX_S3		
		bld		r26, 2			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S3:
		cpi		r17, 3 
		brne	INTRX_S4		
		bld		r26, 3			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S4:
		cpi		r17, 4 
		brne	INTRX_S5		
		bld		r26, 4			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S5:
		cpi		r17, 5 
		brne	INTRX_S6		
		bld		r26, 5			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S6:
		cpi		r17, 6 
		brne	INTRX_S7		
		bld		r26, 6			; Set bit in PATCH_SWITCH2
		rjmp	INTRX_SEXIT
INTRX_S7:		
		bld		r26, 7			; Set bit in PATCH_SWITCH2		

INTRX_SEXIT:					; Finished switch scan, store updated switch bytes
		sts		PATCH_SWITCH2, r26
		rjmp	INTRX_CCEND
		
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
		
INTRX_SWITCH1:		
		
		cbr		r17, $f8			; Clear highest 5 bits, leaving switch 0..7
		lds		r26, PATCH_SWITCH1
		bst	    r16, 6 		; load MSB of MIDI CC value into SREG T bit	
		
		cpi		r17, 0 
		brne	INTRX_SW1		
		bld		r26, 0			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW1:
		cpi		r17, 1 
		brne	INTRX_SW2		
		bld		r26, 1			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW2:
		cpi		r17, 2 
		brne	INTRX_SW3		
		bld		r26, 2			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW3:
		cpi		r17, 3 
		brne	INTRX_SW4		
		bld		r26, 3			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW4:
		cpi		r17, 4 
		brne	INTRX_SW5		
		bld		r26, 4			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW5:
		cpi		r17, 5 
		brne	INTRX_SW6		
		bld		r26, 5			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW6:
		cpi		r17, 6 
		brne	INTRX_SW7		
		bld		r26, 6			; Set bit in PATCH_SWITCH1
		rjmp	INTRX_SWEXIT
INTRX_SW7:			
		bld		r26, 7			; Set bit in PATCH_SWITCH1

INTRX_SWEXIT:					; Finished switch scan, store updated switch bytes
		sts		PATCH_SWITCH1, r26
		rjmp	INTRX_CCEND

INTRX_SAVE:
			ldi 	r26,low(MIDICC)			
  			ldi 	r27,high(MIDICC)
  			add 	r26,r17
  			adc 	r27,zero
  			lsl 	r16					; shift MIDI data to 0..254 to match knob value
  			st 		x,r16				; store in MIDI CC table

INTRX_CCEND:
			pop		r27					; reload old contents of r27 and r 26
			pop		r26
		    rjmp	INTRX_EXIT

;Ex pitch bender:
INTRX_PBEND:
            cpi	    r17, 0xE0		    ;\
		    breq	INTRX_PB1		    ; \
		    cpi	    r17, 0xE1		    ; / pitch bend
		    breq	INTRX_PB2		    ;/
			rjmp	INTRX_EXIT

INTRX_PB1:
            inc     r17			        ;\
		    sts	    MIDIPHASE, r17		;/ MIDIPHASE = 0xE1
		    sts	    MIDIDATA0, r16		; MIDIDATA0 = dFine	0..127
		    rjmp	INTRX_EXIT

INTRX_PB2:
            dec	    r17			        ;\
		    sts	    MIDIPHASE, r17		;/ MIDIPHASE = 0xE0
		    lds	    r17,MIDIDATA0		;\
		    lsl	    r17			        ;/ r17 = dFine*2	0..254
		    lsl	    r17			        ;\ r16,r17 = P.B.data
		    rol	    r16			        ;/ 0..255,996
		    subi	r16, 128		    ; r16,r17 = -128,000..+127,996
		    sts	    MIDIPBEND_L, r17	;\
		    sts	    MIDIPBEND_H, r16	;/ store P.BEND value
		    rjmp	INTRX_EXIT

INTRX_EXIT:
            pop	    r17
		    pop	    r16			        ;\
		    out	    SREG, r16		    ;/ pop SREG
		    pop	    r16
		    sbi	    UCR, 7			    ; RXCIE=1
		    reti

;-------------------------------------------------------------------------------------------------------------------
;		M A I N   L E V E L   S U B R O U T I N E S
;-------------------------------------------------------------------------------------------------------------------

;=============================================================================
;			Delay subroutines
;=============================================================================

WAIT_10US:
            push	r16		            ; 3+2
		    ldi	    r16, 50		        ; 1

W10U_LOOP:
            dec	    r16		            ; 1\
		    brne	W10U_LOOP	        ; 2/1	/ 49*3 + 2
		    pop	    r16		            ; 2
		    ret			                ; 4

;=============================================================================
;			I/O subroutines
;=============================================================================

;-----------------------------------------------------------------------------
;A/D conversion (start)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r18 = channel #	        0..7
;Out:	-
;Used:	-
;-----------------------------------------------------------------------------
ADC_START:
            out	    ADMUX, r18	        ; set multiplexer
		    sbi	    ADCSRA, 6	        ; ADSC=1
		    ret

;-----------------------------------------------------------------------------
;A/D conversion (end)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	-
;Out:	    r16 = result		            0..255
;Used:	    SREG,r17
;-----------------------------------------------------------------------------
ADC_END:
ADCE_LOOP:
            sbis	ADCSRA, 4 	        ;\
		    rjmp	ADCE_LOOP	        ;/ wait for ADIF==1
		    sbi	    ADCSRA, 4 		    ; clear ADIF
		    in	    r16, ADCL	        ;\
		    in	    r17, ADCH	        ;/ r17:r16 = 000000Dd:dddddddd
		    lsr	    r17		            ;\
		    ror	    r16		            ;/ r17:r16 = 0000000D:dddddddd
		    lsr	    r17		            ;\
		    ror	    r16		            ;/ r16 = Dddddddd
		    ret

;=============================================================================
;			arithmetic subroutines
;=============================================================================

;-----------------------------------------------------------------------------
; 16 bit arithmetical shift right (division by 2^n)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r17:r16 = x
;	        r18 = n (shift count)		0..16
;Out:	    r17:r16 = x asr n
;Used:	    SREG
;-----------------------------------------------------------------------------
ASr16:
            tst	    r18
		    breq	ASr16_EXIT
		    push	r18

ASr16_LOOP:
            asr	    r17		            ;\
		    ror	    r16		            ;/ r17,r16 = r17,r16 asr 1
		    dec	    r18
		    brne	ASr16_LOOP
		    pop	    r18

ASr16_EXIT:
            ret

;-----------------------------------------------------------------------------
; 32 bit logical shift right
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r19:r18:r17:r16 = x
;	        r20 = n (shift count)
;Out:	    r19:r18:r17:r16 = x >> n
;Used:	    SREG
;-----------------------------------------------------------------------------
SHr32:
            tst	    r20
		    breq	SHr32_EXIT
		    push	r20

SHr32_LOOP:
            lsr	    r19
		    ror	    r18
		    ror	    r17
		    ror	    r16
		    dec	    r20
		    brne	SHr32_LOOP
		    pop	    r20

SHr32_EXIT:
            ret

;-----------------------------------------------------------------------------
; 32 bit logical shift left
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r19:r18:r17:r16 = x
;	        r20 = n (shift count)
;Out:	    r19:r18:r17:r16 = x << n
;Used:	    SREG
;-----------------------------------------------------------------------------
SHL32:
            tst	    r20
		    breq	SHL32_EXIT
		    push	r20

SHL32_LOOP:
            lsl	    r16
		    rol	    r17
		    rol	    r18
		    rol	    r19
		    dec	    r20
		    brne	SHL32_LOOP
		    pop	    r20

SHL32_EXIT:
            ret

;-----------------------------------------------------------------------------
;8 bit x 8 bit multiplication (unsigned)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = x					    0..255
;	        r17 = y					    0,000..0,996
;Out:	    r17,r16 = x * y				0,000..254,004
;Used:	    SREG,r18-r20
;-----------------------------------------------------------------------------
MUL8X8U:

			MUL		r16, r17
			movw 	r16,r0
			ret

;-----------------------------------------------------------------------------
;8 bit x 8 bit multiplication (signed)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = x					    -128..+127
;	        r17 = y					    0,000..0,996
;Out:	    r17,r16 = x * y				-127,500..+126,504
;Used:	    SREG,r18-r20
;-----------------------------------------------------------------------------
MUL8X8S:
            bst	    r16, 7			    ; T = sign: 0=plus, 1=minus
		    sbrc	r16, 7			    ;\
		    neg	    r16			        ;/ r16 = abs(r16)	0..128
			mul		r16, r17
			movw 	r16,r0			    ; r17,r16 = LFO * LFOMOD
		    brtc	M8X8S_EXIT		    ; exit if x >= 0
		    com	    r16			        ;\
		    com	    r17			        ; \
		    sec				            ;  > r17:r16 = -r17:r16
		    adc	    r16, ZERO	        ; /
		    adc	    r17, ZERO	        ;/

M8X8S_EXIT:
            ret

;-----------------------------------------------------------------------------
;32 bit x 16 bit multiplication (unsigned)
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r19:r18:r17:r16 = x			0..2^32-1
;	        r23:r22 = y			        0,yyyyyyyyyyyyyyyy	0..0,9999847
;Out:	    r19:r18:r17:r16 = x * y		0..2^32-1
;Used:	    SREG,r20-r29
;-----------------------------------------------------------------------------
MUL32X16:
            push	r30
		    clr	    r20		            ;\
		    clr	    r21		            ;/ XX = x
		    clr	    r24		            ;\
		    clr	    r25		            ; \
		    clr	    r26		            ;  \
		    clr	    r27		            ;  / ZZ = 0
		    clr	    r28		            ; /
		    clr	    r29		            ;/
		    rjmp	M3216_CHECK

M3216_LOOP:
            lsr	    r23		            ;\
		    ror	    r22		            ;/ y:Carry = y >> 1
		    brcc	M3216_SKIP
		    add	    r24,r16		        ;\
		    adc	    r25,r17		        ; \
		    adc	    r26,r18		        ;  \
		    adc	    r27,r19		        ;  / ZZ = ZZ + XX
		    adc	    r28,r20		        ; /
		    adc	    r29,r21		        ;/

M3216_SKIP:
            lsl	    r16		            ;\
		    rol	    r17		            ; \
		    rol	    r18		            ;  \
		    rol	    r19		            ;  / YY = YY << 1
		    rol	    r20		            ; /
		    rol	    r21		            ;/

M3216_CHECK:
            mov	    r30,r22		        ;\
		    or	    r30,r23		        ;/ check if y == 0
		    brne	M3216_LOOP
		    mov	    r16,r26		        ;\
    		mov	    r17,r27		        ; \
		    mov	    r18,r28		        ; / x * y
		    mov	    r19,r29		        ;/
		    pop	    r30
		    ret

;-----------------------------------------------------------------------------
; Load 32 bit phase value from ROM
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r30 = index
;Out:	    r19:r18:r17:r16 = value
;Used:	    SREG,r0,r30,r31
;-----------------------------------------------------------------------------
LOAD_32BIT:
            lsl	    r30			        ; r30 *= 2
		    ldi	    r31, 0
		    adiw	r30, DELTA_C	    ; Z = ROM address
		    add	    r30, r30
    		adc	    r31, r31
		    lpm
		    mov	    r16, r0
		    adiw	r30, 1
		    lpm
		    mov	    r17, r0
		    adiw	r30, 1
		    lpm
		    mov	    r18, r0
		    adiw	r30, 1
		    lpm
		    mov	    r19, r0
		    ret

;-----------------------------------------------------------------------------
; Load phase delta from ROM
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r23,r22 = indexs = 0,0..12,0 = n,octave
;Out:	    r19:r18:r17:r16 = delta
;Used:	    SREG,r0,r21,r24-r31
;-----------------------------------------------------------------------------
LOAD_DELTA:
            push	r22
		    push	r23
		    mov	    r30, r23
    		rcall	LOAD_32BIT
		    mov	    r24, r16
		    mov	    r25, r17
		    mov	    r26, r18
		    mov	    r27, r19		    ; r27-r24 = delta[n]
		    mov	    r30, r23
		    inc	    r30
		    rcall	LOAD_32BIT
		    sub	    r16, r24
		    sbc	    r17, r25
		    sbc	    r18, r26
		    sbc	    r19, r27
		    push	r24
		    push	r25
		    push	r26
		    push	r27
		    mov	    r23, r22
		    ldi	    r22, 0
		    push	r20
		    rcall	MUL32X16
		    pop	    r20
		    pop	    r27
		    pop	    r26
		    pop	    r25
		    pop	    r24
    		add	    r16, r24
		    adc	    r17, r25
    		adc	    r18, r26
		    adc	    r19, r27
		    pop	    r23
		    pop	    r22
		    ret

;-----------------------------------------------------------------------------
;note number recalculation
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r23 = n	                    0..139 = m12 + 12*n12
;Out:	    r23 = m12                   0..11
;	        r20 = n12                   0..11
;Used:	    SREG
;-----------------------------------------------------------------------------
NOTERECALC:
            ldi	r20,0			        ; n12 = 0
		    rjmp	NRC_2

NRC_1:
            subi	r23, 12			    ; m12 -= 12
		    inc	    r20			        ; n12++

NRC_2:
            cpi	    r23, 12
		    brsh	NRC_1			    ; repeat while m12 >= 12
		    ret

;-----------------------------------------------------------------------------
;read a byte from a table
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = i		                0..255
;	        r31:r30 = &Tab
;Out:	    r0 = Tab[i]	                0..255
;Used:	    SREG,r30,r31
;-----------------------------------------------------------------------------
TAB_BYTE:
            add	    r30, r30			;\
		    adc	    r31, r31		    ;/ Z = 2 * &Tab
		    add	    r30, r16
		    adc	    r31, ZERO
		    lpm
		    ret

;-----------------------------------------------------------------------------
;read a word from a table
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = i			            0..255
;	        r31:r30 = &Tab
;Out:	    r19:r18 = Tab[i]            0..65535
;Used:	    SREG,r0,r30,r31
;-----------------------------------------------------------------------------
TAB_WORD:
            add	    r30, r16
		    adc	    r31, ZERO
		    add	    r30, r30		    ;\
		    adc	    r31, r31		    ;/ Z = 2 * &Tab
		    lpm
		    mov	    r18, r0			    ; LSByte
		    adiw	r30, 1			    ; Z++
		    lpm
		    mov	    r19, r0			    ; MSByte
		    ret

;-----------------------------------------------------------------------------
;"time" --> "rate" conversion
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = time			        0..255
;Out:	    r19:r18:r17:r16 = rate		0x001B0000..0xFFFF0000
;Used:	    SREG,r0,r30,r31
;-----------------------------------------------------------------------------
ADCTORATE:
            lsr	    r16
		    lsr	    r16
		    lsr	    r16			        ;0..31
		    ldi	    r30, TIMETORATE
		    ldi	    r31, 0
		    rcall	TAB_WORD		    ;r19:r18 = rate
		    clr	    r16
		    clr	    r17
		    ret

;-----------------------------------------------------------------------------
;conversion of the "detune B" potentiometer function
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = x		                0..255
;Out:	    r17,r16 = y	                0,000..255,996
;Used:	    SREG,r18-r30
;-----------------------------------------------------------------------------
NONLINPOT:
            ldi	    r22, 0
		    mov	    r23, r16
    		cpi	    r23, 112
		    brlo	NLP_I
		    cpi	    r23, 144
		    brlo	NLP_II
		    rjmp	NLP_III

NLP_I:
            ldi	    r16, 0			    ;\  r18,r17:r16 = m =
		    ldi	    r17, 32			    ; > = 126/112 =
		    ldi	    r18, 1			    ;/  = 1,125
    		ldi	    r30, 0			    ;\ r31,r30 = n =
		    ldi	    r31, 0			    ;/ = 0,0
		    rjmp	NLP_CONT

NLP_II:
            ldi	    r16, 8			    ;\  r18,r17:r16 = m =
		    ldi	    r17, 33			    ; > = (130-126)/(143-112) =
    		ldi	    r18, 0			    ;/  = 0,129032258
		    ldi	    r30, 140		    ;\ r31,r30 = n =
		    ldi	    r31, 111		    ;/ = 126 - m*112 = 111,5483871
		    rjmp	NLP_CONT

NLP_III:
            ldi	    r16, 183		    ;\  r18,r17:r16 = m =
		    ldi	    r17, 29			    ; > = (255-130)/(255-143) =
		    ldi	    r18, 1			    ;/  = 1,116071429
    		ldi	    r30, 103		    ;\ r31,r30 = n =
		    ldi	    r31, 226		    ;/ 255 - m*255 = -29,59821429

NLP_CONT:
            ldi	    r19, 0
		    rcall	MUL32X16
		    add	    r16, r30
		    adc	    r17, r31
		    ret

;-----------------------------------------------------------------------------
; Write byte to eeprom memory
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 	= value		                0..255
;			r18:r17 = eeprom memory address
;Used:	    r16, r17, r18
;-----------------------------------------------------------------------------
EEPROM_write:
										; Wait for completion of previous write
			sbic 	EECR,EEWE
			rjmp 	EEPROM_write
			in		temp_SREG, SREG		; save SREG
			cli							; disable interrupts during timed eeprom sequence
			out 	EEARH, r18 
			out 	EEARL, r17			; single byte offset from WRITE_OFFSET
			out 	EEDR,  r16			; Write data (r16) to data register
			sbi 	EECR,EEMWE			; Write logical one to EEMWE
			sbi 	EECR,EEWE			; Start eeprom write by setting EEWE
			out		SREG, temp_SREG		; restore SREG (restarts interrupts if enabled)
			ret									

;-----------------------------------------------------------------------------
; Read byte from eeprom memory
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r18:r17 = eeprom memory address
;Out:		r16 	= value		                0..255
;Used:	    r16, r17, r18
;-----------------------------------------------------------------------------
EEPROM_read:
										
			sbic 	EECR,EEWE			; Wait for completion of previous write
			rjmp 	EEPROM_read
			in		temp_SREG, SREG		; save SREG
			cli							; disable interrupts during timed eeprom sequence
			out 	EEARH, r18			; Set up address (r18:r17) in address register
			out 	EEARL, r17
			sbi 	EECR, EERE			; Start eeprom read by writing EERE
			in 		r16, EEDR			; Read data from data register
			out		SREG, temp_SREG 	; restore SREG (restarts interrupts if enabled)
			ret

;-----------------------------------------------------------------------------
; Clear knob status
; Set knob status to 'unmoved' and save current knob positions
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    --
;Out:		--
;Used:	    r16
;-----------------------------------------------------------------------------

CLEAR_KNOB_STATUS:						;	set knob status to 'unmoved' and save current knob positions
			clr		r16
			sts		KNOB0_STATUS, r16	; 
			sts		KNOB1_STATUS, r16	; 
			sts		KNOB2_STATUS, r16	; 
			sts		KNOB3_STATUS, r16	; 
			sts		KNOB4_STATUS, r16	; 
			sts		KNOB5_STATUS, r16	; 
			sts		KNOB6_STATUS, r16	; 
			sts		KNOB7_STATUS, r16	; 
			lds	    r16, ADC_0			; Save current pot positions for future comparison
			sts	    OLD_ADC_0,r16
			lds	    r16, ADC_1			 
			sts	    OLD_ADC_1,r16
			lds	    r16, ADC_2			 
			sts	    OLD_ADC_2,r16
			lds	    r16, ADC_3			 
			sts	    OLD_ADC_3,r16
			lds	    r16, ADC_4			 
			sts	    OLD_ADC_4,r16
			lds	    r16, ADC_5			 
			sts	    OLD_ADC_5,r16
			lds	    r16, ADC_6			 
			sts	    OLD_ADC_6,r16
			lds	    r16, ADC_7			 
			sts	    OLD_ADC_7,r16	
			ret

;-----------------------------------------------------------------------------
; Load patch
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;In:	    r16 = patch number
;Out:		Loads 16 byte patch into MIDI CC table
;Used:	    r16-r19, r28, r29
;-----------------------------------------------------------------------------

LOAD_PATCH:
										; Enter with patch number in r16
			lsl		r16
			lsl		r16
			lsl		r16
			lsl		r16					; multiply patch number by 16 to get starting address of patch in eeprom
			mov		r17, r16			; Low byte of eeprom address	
			ldi		r18, 0				; High byte of eeprom address
			ldi		r19, $30 			; MIDI CC table offset

									    ; Get byte from eeprom			
PATCH_LOOP:
			rcall	EEPROM_READ			; Returns patch(i) in r16							

			ldi 	r28, low (MIDICC)		
  			ldi 	r29, high(MIDICC)
  			add 	r28, r19
  			adc 	r29, zero
  			st 		Y, r16				; store in MIDI CC table

			inc		r17
			inc		r19
			cpi		r19, $40			; are we finished loading 16 bytes?
			brne	PATCH_LOOP

			; copy switch bytes from MIDI table to current patch
			lds		r16, SW1
			sts		PATCH_SWITCH1, r16
			lds		r16, SW2
			sts		PATCH_SWITCH2, r16
			lds		r16, SWITCH1
			sts		OLD_SWITCH1, r16
			lds		r16, SWITCH2
			sts		OLD_SWITCH2, r16

			; flag knobs as not moved
			rcall	CLEAR_KNOB_STATUS	
			ret	


;-----------------------------------------------------------------------------
; Scan a pot and update its value if it has been moved
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
; In: r16 - the new pot value
;	  r20 - the current conversion channel (0..7) 
; Out: r17 - 1 if the pot has changed, 0 otherwise
; Used: r16-r20, r28, r29, SREG
;-----------------------------------------------------------------------------
POT_SCAN:
		    ldi	    r28, KNOB0_STATUS	;
		    add	    r28, r20		    ; 
		    ldi	    r29, 0			    ;
		    ld	    r18, Y			    ; load KNOBN_STATUS value into r18
			
			sbrc	r18, 0				; Check bit 0
			rjmp	LOAD_ADC			; KNOBN_STATUS is set, so just update parameter
			mov		r19, r16
			
		    ldi	    r28, OLD_ADC_0	    ; 
		    add	    r28, r20		    ; 
		    ldi	    r29, 0			    ;
		    ld	    r17, Y			    ; load OLD_ADC_N value into r17
			sub		r19, r17
			brpl	DEAD_CHECK
			neg		r19		
DEAD_CHECK:
			cpi		r19, 5				 
			brlo	NO_CHANGE			; Skip ahead if pot change is < the deadzone limit
			sbr 	r18,1				; Update knob status bit and continue -- pot moved
			ldi	    r28, KNOB0_STATUS	;
		    add	    r28, r20		    ; 
		    ldi	    r29, 0			    ;
		    st      Y, r18			    ; save updated KNOBN_STATUS
			rjmp 	LOAD_ADC			; 

NO_CHANGE:
			ldi		r17, 0			    ; flag pot unchanged
			ret

LOAD_ADC:	
			ldi		r17, 1				; flag pot changed
			ret 						

;-------------------------------------------------------------------------------------------------------------------
;			M A I N   P R O G R A M
;-------------------------------------------------------------------------------------------------------------------
RESET:
            cli				            ; disable interrupts

;JTAG Disable - Set JTD in MCSCSR
            lds     r16, MCUCSR         ; Read MCUCSR
            sbr     r16, 1 << JTD       ; Set jtag disable flag
            out     MCUCSR, r16         ; Write MCUCSR
            out     MCUCSR, r16         ; and again as per datasheet

;initialize stack:
  			ldi 	r16, low(RAMEND)
			ldi 	r17, high(RAMEND)
		    out	    SPL, r16
		    out	    SPH, r17

;initialize variables:
		    clr	    ZERO
		    clr	    PHASEA_0
    		clr	    PHASEA_1
		    clr	    PHASEA_2
		    clr	    PHASEB_0
		    clr	    PHASEB_1
		    clr	    PHASEB_2
			clr 	a_L					; clear DCF registers
			clr 	a_H					;
			clr		z_L					;
			clr 	z_H					;
			clr 	temp				;
			clr 	temp2				;
			ldi		r16, 5
			sts 	KNOB_DEADZONE, r16	
		    ldi	    r16, 0
			sts		LED_STATUS, r16			; LED status = off
			sts		LED_TIMER, r16		;
			sts		BUTTON_STATUS, r16	; no buttons pressed
			sts		CONTROL_SWITCH, r16 ; no switches flipped
			sts		SETMIDICHANNEL, r16 ; Default MIDI channel to zero (omni)
			sts		SWITCH3, r16		; MIDI/Save/Load switch hasn't been scanned yet, so clear it
			sts		FMDEPTH, r16		; FM Depth = 0
		    sts	    GATE, r16		    ; GATE = 0
		    sts	    GATEEDGE, r16	    ; GATEEDGE = 0
		    sts	    LEVEL, r16		    ; LEVEL = 0
		    sts	    ENV_FRAC_L, r16	    ;\
		    sts	    ENV_FRAC_H, r16	    ; > ENV = 0
		    sts	    ENV_INTEGR, r16	    ;/
		    sts	    ADC_CHAN, r16	    ;ADC_CHAN = 0
		    sts	    NOTE_L, r16		    ;\
		    sts	    NOTE_H, r16		    ; >
		    sts	    NOTE_INTG, r16	    ;/
		    sts	    MIDIPBEND_L, r16    ;\
		    sts	    MIDIPBEND_H, r16    ;/ P.BEND = 0
		    sts	    MIDIMODWHEEL, r16   ; MOD.WHEEL = 0
			sts		KNOB_SHIFT, r16		; Initialize panel shift switch = 0 (unshifted)
		    ldi	    r16, 2
		    sts	    PORTACNT, r16	    ; PORTACNT = 2
		    ldi	    r16, 255
			sts		POWER_UP, r16		; Set power_up flag to 255 to force first initialization of panel switches
		    sts	    LPF_I, r16		    ; no DCF
			sts		HPF_I, r16			
		    sts	    MIDINOTE, r16	    ; note# = 255
		    sts	    MIDINOTEPREV, r16   ; note# = 255
		    ldi	    r16, 0x5E		    ;\
		    ldi	    r17, 0xB4		    ; \
		    ldi	    r18, 0x76		    ;  \ initialising of
		    sts	    SHIFTREG_0, r16		;  / shift register
		    sts	    SHIFTREG_1, r17		; /
		    sts	    SHIFTREG_2, r18		;/
		    ldi	    r16, 0			    ;\
    		ldi	    r17, 0			    ; > Amin = 0
		    ldi	    r18, 0			    ;/
		    sts	    LFOBOTTOM_0, r16	;\
		    sts	    LFOBOTTOM_1, r17	; > store Amin for LFO
		    sts	    LFOBOTTOM_2, r18	;/
		    ldi	    r16, 255		    ;\
		    ldi	    r17, 255		    ; > Amax = 255,999
		    ldi	    r18, 255		    ;/
		    sts	    LFOTOP_0, r16		;\
		    sts	    LFOTOP_1, r17		; > store Amax for LFO
		    sts	    LFOTOP_2, r18		;/
			ldi		r18, 20
			sts	    LFO2BOTTOM_0, r16	;\
		    sts	    LFO2BOTTOM_1, r17	; > store Amin for LFO2
			sts	    LFO2BOTTOM_2, r18	;/
			ldi		r18, 100
			sts	    LFO2TOP_0, r16		;\
		    sts	    LFO2TOP_1, r17		; > store Amax for LFO2
		    sts	    LFO2TOP_2, r18		;/


;initialize sound parameters:
		    sts	    LFOPHASE, r16		;
			sts	    LFO2PHASE, r16		;
		    sts	    ENVPHASE, r16		;
		    sts	    DETUNEB_FRAC, r16	;\
		    sts	    DETUNEB_INTG, r16	;/ detune = 0
		    sts	    LFOLEVEL, r16		;

;initialize port A:
		    ldi	    r16, 0x00    		;\
		    out	    DDRA, r16		    ;/ PA = iiiiiiii    all inputs (panel pots)
			ldi		r16, 0xFF			; enable internal pull-ups, even though we're using analog inputs   		
		    out	    PORTA, r16		    ;/ PA = pppppppp

;initialize port B:
		    ldi	    r16, 0x00    	    ;\
		    out	    DDRB, r16		    ;/ PB = iiiiiiii    all inputs, pull-ups enabled
			ldi	    r16, 0xff    		;\
			out	    PORTB, r16		    ;/ PB = pppppppp

;initialize port C:
    		ldi	    r16, 0xFF    		;\
		    out	    DDRC, r16		    ;/ PC = oooooooo    all outputs (DAC)
		    ldi	    r16, 0x00     	    ;\
		    out	    PORTC, r16		    ;/ PC = 00000000

;initialize port D:
		    ldi		r16, 0x0E			;  PD = iiiioooi
			out	    DDRD, r16		    ;/ PD0 (MIDI-IN)		
			ldi	    r16, 0xFC    		;\
			out	    PORTD, r16		    ;/ PD = 1111110z


; Turn Power/MIDI LED on at power up
			
			sbi	    PORTD, 1		    ; LED on

; initialize DAC port pins

			sbi		PORTD, 3			; Set WR high
			cbi		PORTD, 2			; Pull DAC AB port select low


;initialize Timer0:
		    ldi	    r16, 0x00    		;\
		    out	    TCCr0, r16		    ;/ stop Timer 0

;initialize Timer1:
		    ldi	    r16, 0x04    		;\ prescaler = CK/256
		    out	    TCCr1B, r16		    ;/ (clock = 32µs)

;initialize Timer2:
            ldi     r16, 54             ;\  
            out     OCr2, r16           ;/ OCr2 = 54 gives 36363.63636 Hz sample rate at ~440 cycles per sample loop.
            ldi     r16, 0x0A           ;\ clear timer on compare,
            out     TCCr2, r16          ;/ set prescaler = CK/8

;initialize UART:
		    ldi	    r16, high((cpu_frequency / (baud_rate * 16)) - 1)
		    out	    UBRRH, r16
    		ldi	    r16, low((cpu_frequency / (baud_rate * 16)) - 1)
            out     UBRRL, r16

; enable receiver and receiver interrupt
    		ldi	    r16, (1<<RXCIE)|(1<<RXEN)   ;\
		    out	    UCR, r16		            ;/ RXCIE=1, RXEN=1

;initialize ADC:
		    ldi	    r16, 0x86    		;\
		    out	    ADCSRA, r16		    ;/ ADEN=1, clk = 125 kHz

;initialize interrupts:
		    ldi	    r16, 0x80    		;\
		    out	    TIMSK, r16		    ;/ OCIE2=1

    		sei				            ; Interrupt Enable

;start conversion of the first A/D channel:
		    lds	    r18, ADC_CHAN
		    rcall	ADC_START

;store initial pot positions as OLD_ADC values to avoid snapping to new value unless knob has been moved.

										; Store value of Pot ADC0
		    ldi	    r28, ADC_0		    ; \
		    add	    r28, r18		    ; / Y = &ADC_i
		    ldi	    r29, 0			    ;/
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

		    inc	    r18					; Now do ADC1
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i
			
			inc	    r18					; Now do ADC2
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			inc	    r18					; Now do ADC3
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			inc	    r18					; Now do ADC4
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			inc	    r18					; Now do ADC5
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			inc	    r18					; Now do ADC6
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			inc	    r18					; Now do ADC7
		    rcall	ADC_START	        ; start conversion of next channel
		    inc		r28
			rcall	ADC_END			    ; r16 = AD(i)
		    st	    Y, r16			    ; AD(i) --> ADC_i

			ldi		r18, 0
			sts	    ADC_CHAN,r18
		    rcall	ADC_START	        ; start conversion of ADC0 for main loop 

; Load current patch from eeprom
 
			ldi		r18, $03
			ldi		r17, $FE				; Set eeprom address to $03FE (second last byte)
			rcall   EEPROM_READ				; load current patch number into r16 
			rcall	LOAD_PATCH				; load patch into synthesis engine

; Load MIDI channel from eeprom

			ldi		r18, $03
			ldi		r17, $FF				; Set eeprom address to $03FF (last byte)
			rcall   EEPROM_READ				; load MIDI CHANNEL into r16
			sts		SETMIDICHANNEL, r16

;initialize the keyboard scan time 
		    in		r16, TCNT1L		        ;\
		    in		r17, TCNT1H		        ;/ r17:r16 = TCNT1 = t
		    sts		TPREV_KBD_L, r16
		    sts		TPREV_KBD_H, r17
				 
;-------------------------------------------------------------------------------------------------------------------
; Main Program Loop
;
; This is where everything but sound generation happens. This loop is interrupted 36,636 times per second by the
; sample interrupt routine. When it's actually allowed to get down to work, it scans the panel switches every 100ms,
; scans the knobs a lot more than that,  calculates envelopes, processes the LFO and parses MIDI input. 
; 
; In its spare time, Main Program Loop likes to go for long walks, listen to classical music and perform 
; existential bit flipping.
;-------------------------------------------------------------------------------------------------------------------
;


MAINLOOP:
            ;---------------------
            ; scan panel switches:
            ;---------------------
;begin:

		    in	    r16, TCNT1L		    ;\
		    in	    r17, TCNT1H		    ;/ r17:r16 = t
		    lds	    r18, TPREV_KBD_L	;\
		    lds	    r19, TPREV_KBD_H	;/ r19:r18 = t0
		    sub	    r16, r18			;\
		    sbc	    r17, r19			;/ r17:r16 = t - t0
		    subi	r16, LOW(KBDSCAN)	;\
		    sbci	r17, HIGH(KBDSCAN)	;/ r17:r16 = (t-t0) - 100ms
		    brsh	MLP_SCAN		    ;\
		    rjmp	MLP_WRITE			;/ skip scanning if (t-t0) < 100ms

MLP_SCAN:

			; blink LED if LED/save/load button has been pressed
			lds		r16, SWITCH3
			tst		r16
			breq	CONTROL_EXIT		; Set button status: 1=MIDI, 2=SAVE, 4=LOAD
			sts		BUTTON_STATUS, r16	; Set control status to MIDI, turn on control timer
			ldi		r16, 63
			sts		LED_TIMER, r16
control_exit:
			lds		r16, BUTTON_STATUS
			tst		r16
			breq	MLP_LED_END			; button hasn't been pressed, so skip

			; flip panel LED state until button timer is finished
		    lds		r16, LED_STATUS
			ldi		r17, 64
			add		r16, r17
			cpi		r16, $80
			brlo	MLP_LED_OFF
			lds		r17, LED_TIMER
			dec		r17
			breq	MLP_LED_RESET
			sbi		PORTD, 1			; LED on
			rjmp	MLP_LED_EXIT
MLP_LED_OFF:
			lds		r17, LED_TIMER
			dec		r17
			breq	MLP_LED_RESET
			cbi	    PORTD, 1		    ; LED off
			rjmp	MLP_LED_EXIT
MLP_LED_RESET:
			sbi	    PORTD, 1		    ; Clear everything
			ldi		r16, 0
			sts		BUTTON_STATUS, r16	
MLP_LED_EXIT:
			sts		LED_STATUS, r16
			sts		LED_TIMER, r17
MLP_LED_END:

            in	    r16, TCNT1L
		    in	    r17, TCNT1H
		    sts	    TPREV_KBD_L, r16	;\
		    sts	    TPREV_KBD_H, r17	;/ t0 = t


; Read the digital inputs. See below for mapping to SE parameters
;
;
			; Micro switches are mapped to PB0-4, PD4-6
			in		r16, PINB
			cbr		r16, 0b11100000		; Clear the highest three bits
			in		r17, PIND
			cbr		r17, 0b00001111		; Clear lowest four bits
			lsl		r17					; shift PD4-6 into bits 5-7
			add		r16, r17			; Combine values into a single byte

			ldi	    r19, 0x00    		; bits of SWITCH1
		    ldi	    r20, 0x00    		; bits of SWITCH2
		    ldi	    r21, 0x00			; bits of SWITCH3

			bst		r16, 0
			bld		r20, SW_OSCA_WAVE	; Copy bit 0 into SW_OSCA_WAVE
			bst		r16, 1
			bld		r20, SW_OSCB_WAVE	; Copy bit 1 into SW_OSCB_WAVE 
			bst		r16, 2
			bld		r20, SW_PWM_SWEEP	; Copy bit 2 into SW_PWM_SWEEP
			bst		r16, 3
			bld		r20, SW_OSCB_OCT	; Copy bit 3 into SW_OSCB_OCT
			bst		r16, 4
			bld		r20, SW_SUSTAIN		; Copy bit 4 into SW_SUSTAIN
			bst		r16, 5
			bld		r19, SW_LFO_ENABLE	; Copy bit 5 into SW_LFO_ENABLE
			bst		r16, 6
			bld		r19, SW_LFO_WAVE	; Copy bit 6 into SW_LFO_WAVE					
			bst		r16, 7
			bld		r19, SW_KNOB_SHIFT	; Copy bit 7 into SW_KNOB_SHIFT
			
		    sts	    SWITCH1, r19
		    sts	    SWITCH2, r20
    		sts	    SWITCH3, r21		; Store switch settings


; capture switch values on power up
			
			lds		r17, POWER_UP		; Is this the first time through this code since synth was turned on?
			sbrs	r17, 0				
			rjmp	MLP_SWITCH
			sts		OLD_SWITCH1, r19	; Yes: make OLD_SWITCHx = SWITCHx (so we know when they've been flipped)
			sts		OLD_SWITCH2, r20
			clr		r17					
			sts		POWER_UP, r17		; Clear the POWER_UP flag so we don't reinitialize

;service:
MLP_SWITCH:
			; Compare SWITCH1 to OLD_SWITCH1. Skip if unchanged.

			lds		r16, SWITCH1
			lds		r17, OLD_SWITCH1	
			cp		r16, r17		
			breq	MLP_SWITCH2			; Switch 1 unchanged, so leave as is.
			lds		r18, PATCH_SWITCH1	

			; Compare bits in OLD_SWITCH1 and SWITCH1. If different, copy SWITCH1 bit to PATCH_SWITCH1 bit.
			clr		r30				; Register used to indicate which switch 1..16 has been flipped
			; Perform an exclusive OR on r17 and r16. Changed bits are flagged as 1's.
			eor		r17, r16	
			sbrs	r17, 0				
			rjmp	MLP_BIT1			; Exit if bit is not set
			bst		r16, 0
			bld		r18, 0				; copy bit from SWITCH1 to PATCH_SWITCH1
			; Flag dual parameter knobs unmoved because this is the KNOB_SHIFT switch
			push	r16
			rcall	CLEAR_KNOB_STATUS
			pop		r16
			ldi		r30, 16				; Flag switch 16 moved
MLP_BIT1:
			sbrs	r17, 1				
			rjmp	MLP_BIT2	
			bst		r16, 1
			bld		r18, 1		
			ldi		r30, 15					; Flag switch 15 moved								
MLP_BIT2:
			sbrs	r17, 2				
			rjmp	MLP_BIT3			
			bst		r16, 2
			bld		r18, 2	
			ldi		r30, 14					; Flag switch 14 moved						
MLP_BIT3:
			sbrs	r17, 3				
			rjmp	MLP_BIT4			
			bst		r16, 3
			bld		r18, 3
			ldi		r30, 13					; Flag switch 13 moved				
MLP_BIT4:
			sbrs	r17, 4				
			rjmp	MLP_BIT5			
			bst		r16, 4
			bld		r18, 4				
			ldi		r30, 8					; Flag switch 8 moved
MLP_BIT5:
			sbrs	r17, 5				
			rjmp	MLP_BIT6			
			bst		r16, 5
			bld		r18, 5				
			ldi		r30, 7					; Flag switch 7 moved
MLP_BIT6:
			sbrs	r17, 6				
			rjmp	MLP_BIT7			
			bst		r16, 6
			bld		r18, 6				
			ldi		r30, 6				; Flag switch 6 moved
MLP_BIT7:
			sbrs	r17, 7				
			rjmp	MLP_PATCH1SAVE			
			bst		r16, 7
			bld		r18, 7		
			ldi		r30, 5					; Flag switch 5 moved

MLP_PATCH1SAVE:	
			sts		CONTROL_SWITCH, r30		; Number of last switch flipped: 1..16, where zero indicates none flipped	
			; DON'T save changes to PATCH_SWITCH1 if BUTTON_STATUS is SAVE (2) because we're about to write the patch that has just been changed by flipping the switch. 
			lds		r17, BUTTON_STATUS
			cpi		r17, 2
			breq	MLP_SKIP_PATCH1
			sts		PATCH_SWITCH1, r18		; Store changes	to patch
MLP_SKIP_PATCH1:	
			sts		OLD_SWITCH1, r16		; Keep a copy of panel switches so we know if things change next time

MLP_SWITCH2:				
			; Compare SWITCH2 to OLD_SWITCH2. Skip if unchanged.

			lds		r16, SWITCH2
			lds		r17, OLD_SWITCH2	
			cp		r16, r17		
			breq	MLP_SW_EXIT			; Switch 2 unchanged, so leave as is.
			lds		r18, PATCH_SWITCH2	
			
			; Compare bits in OLD_SWITCH2 and SWITCH2. If different, copy SWITCH2 bit to PATCH_SWITCH2 bit.
			clr		r30				; Register used to indicate which switch 1..16 has been flipped

			; Perform an exclusive OR on r17 and r16. Changed bits are flagged as 1's.
			eor		r17, r16		
			sbrs	r17, 0				
			rjmp	MLP_BIT1A			; Exit if bit is not set
			bst		r16, 0
			bld		r18, 0				; copy bit from SWITCH2 to PATCH_SWITCH2
			ldi		r30, 12					; Flag switch 12 moved
MLP_BIT1A:
			sbrs	r17, 1				
			rjmp	MLP_BIT2A			
			bst		r16, 1
			bld		r18, 1
			ldi		r30, 11					; Flag switch 11 moved								
MLP_BIT2A:
			sbrs	r17, 2				
			rjmp	MLP_BIT3A			
			bst		r16, 2
			bld		r18, 2		
			ldi		r30, 10					; Flag switch 10 moved					
MLP_BIT3A:
			sbrs	r17, 3				
			rjmp	MLP_BIT4A			
			bst		r16, 3
			bld		r18, 3	
			ldi		r30, 9					; Flag switch 9 moved						
MLP_BIT4A:
			sbrs	r17, 4				
			rjmp	MLP_BIT5A			
			bst		r16, 4
			bld		r18, 4	
			ldi		r30, 4					; Flag switch 4 moved						
MLP_BIT5A:
			sbrs	r17, 5				
			rjmp	MLP_BIT6A			
			bst		r16, 5
			bld		r18, 5
			ldi		r30, 3					; Flag switch 3 moved							
MLP_BIT6A:
			sbrs	r17, 6				
			rjmp	MLP_BIT7A			
			bst		r16, 6
			bld		r18, 6				
			ldi		r30, 2					; Flag switch 2 moved
MLP_BIT7A:
			sbrs	r17, 7				
			rjmp	MLP_PATCH2SAVE			
			bst		r16, 7
			bld		r18, 7
			ldi		r30, 1					; Flag switch 1 moved
			
MLP_PATCH2SAVE:
			sts		CONTROL_SWITCH, r30		; Number of last switch flipped: 1..16, where zero indicates none flipped	

			; DON'T save changes to PATCH_SWITCH2 if BUTTON_STATUS is SAVE (2) because we're about to write the patch that has just been changed by flipping the switch. 
			lds		r17, BUTTON_STATUS
			cpi		r17, 2
			breq	MLP_SKIP_PATCH2
			sts		PATCH_SWITCH2, r18		; Store changes	to patch
MLP_SKIP_PATCH2:	
			sts		OLD_SWITCH2, r16		; Keep a copy of panel switches so we know if things change next time
			
MLP_SW_EXIT:

; Set MIDI channel based on panel switches:
			lds		r17, BUTTON_STATUS
			tst		r17
			breq	SKIP_CONTROL_SET			
			lds		r16, CONTROL_SWITCH
			tst		r16
			breq	SKIP_CONTROL_SET			; continue only if a switch was moved
			cpi		r17, 1
			breq	SET_MIDI_CH
			cpi		r17, 2
			breq	MLP_SAVE
MLP_LOAD:
			dec		r16						; Shift patch offset to 0..16
			ldi		r18, $03
			ldi		r17, $FE				; Set eeprom address to $03FE (second last byte in memory)
			rcall   EEPROM_WRITE			; Write current patch # to memory so it will be loaded at power up
			rcall	LOAD_PATCH				; Fetches the patch correspondng to the control switch number stored in r16
			rjmp	END_CONTROL_SET			; reset control button
MLP_SAVE:
			lds		r17, WRITE_MODE
			tst		r17
			breq	END_CONTROL_SET			; Skip if we're already in write mode
			dec		r16						; Shift patch offset to 0..16
			ldi		r18, $03
			ldi		r17, $FE				; Set eeprom address to $03FE (second last byte in memory)
			rcall   EEPROM_WRITE			; Write current patch # to memory so it will be loaded at power up
			ldi		r17, 0	
			sts		WRITE_MODE, r17			; Set knob status to 'unmoved' and save current knob positions
			sts		WRITE_OFFSET, r17	
			lsl		r16
			lsl		r16
			lsl		r16
			lsl		r16					; multiply patch number by 16 to get starting address of patch in eeprom
			sts		WRITE_PATCH_OFFSET, r16 ; switch # 0..16 
			lds		r16, PATCH_SWITCH1
			sts		SW1, r16
			lds		r16, PATCH_SWITCH2
			sts		SW2, r16				; Copy the patch switches into the MIDI CC table		
			rcall	CLEAR_KNOB_STATUS	
			rjmp	END_CONTROL_SET			; reset control button
SET_MIDI_CH:
											; Set MIDI channel - adjust the panel switches so that channel 16 sets the synth in omni mode					
			inc		r16						; Shift value to 2..17 to make room for omni
			cpi		r16, 17					
			brne	NOT_OMNI
			ldi		r16, 1					; If it was channel 16, force it to channel 1
NOT_OMNI:
			dec		r16						; subtract 1 from channel numbers
			sts	    SETMIDICHANNEL, r16		; 0 for OMNI or channel 1..15
			ldi		r18, $03
			ldi		r17, $FF				; Set eeprom address to $03FF (last byte in memory)
			rcall   EEPROM_WRITE			; Write r16 to eeprom
END_CONTROL_SET:
			sbi	    PORTD, 1		        ; Clear control button parameters and leave the LED on
			ldi		r16, 0					;
			sts		BUTTON_STATUS, r16		;
			sts		LED_STATUS, r16			;
			sts		LED_TIMER, r16			;
			sts		CONTROL_SWITCH, r16		;

SKIP_CONTROL_SET:

; ------------------------------------------------------------------------------------------------------------------------
; Asynchronous EEPROM write
;
; Because EEPROM writes are slow, MeeBlip executes the main program and audio interrupts while eeprom writes happen in the 
; background. A new byte is only written if the eeprom hardware flags that it's finished the previous write. 
; ------------------------------------------------------------------------------------------------------------------------
	
MLP_WRITE:
			lds		r16, WRITE_MODE
			sbrc	r16,7			
			rjmp	MLP_SKIPSCAN		; Nothing to write, so skip

			sbic 	EECR,EEWE
			rjmp	MLP_SKIPSCAN		; Skip if we're not finished the last write

; Get the parameter value from MIDI CC table
			lds		r18, WRITE_OFFSET	; r18 contains the byte offset in the patch
			ldi		r17, $30
			add		r17, r18			; Add the byte offset in the MIDI CC table
			ldi 	r28, low (MIDICC)		
  			ldi 	r29, high(MIDICC)
  			add 	r28, r17
  			adc 	r29, zero
  			ld 		r17, Y				; Patch parameter(i) stored in r17

			lds		r16, WRITE_PATCH_OFFSET
			add		r16, r18			; r16 contains the eeprom address of the byte to write, parameter is in r17					

; ------------------------------------------------------------------------------------------------------------------------ 
; Store a single parameter value to eeprom. r16 is the offset, r17 is the data
; ------------------------------------------------------------------------------------------------------------------------
;
										
WRITE_BYTE:									
			ldi		r19, 0														
			out 	EEARH, r19 
			out 	EEARL, r16			; single byte offset from WRITE_OFFSET
			out 	EEDR,r17			; Write data (r17) to data register	
			in 		temp_SREG, SREG 	; store SREG value
			cli							; Disable global interrupts	during timed write					
			sbi 	EECR,EEMWE			; Write logical one to EEMWE
			sbi 	EECR,EEWE			; Start eeprom write by setting EEWE
			out 	SREG, temp_SREG 	; restore SREG value (I-bit - restarts global interrupts)
			cpi		r18, 15				; If eeprom write offset is at the end patch (byte 15)
			breq	CLEAR_WRITE
			inc		r18
			sts		WRITE_OFFSET, r18 	; increment and store eeprom offset for next parameter
			rjmp	MLP_SKIPSCAN

CLEAR_WRITE:
			ldi		r17, 255
			sts		WRITE_MODE, r17		; Set write mode to 255 (off)

; ------------------------------------------------------------------------------------------------------------------------
; Read potentiometer values
; ------------------------------------------------------------------------------------------------------------------------
;

MLP_SKIPSCAN:

            ;--------------------
            ;read potentiometers:
            ;--------------------


		    rcall	ADC_END			    ; r16 = AD(i)
		    lds	    r18, ADC_CHAN		;\
			sts		PREV_ADC_CHAN, r18   ; keep track of which ADC channel we're processing. 
		    ldi	    r28, ADC_0		    ; \
		    add	    r28, r18		    ; / Y = &ADC_i
		    ldi	    r29, 0			    ;/
		    st	    Y, r16			    ; AD(i) --> ADC_i

;next channel:
		    inc	    r18
		    andi	r18, 0x07
		    sts	    ADC_CHAN,r18
		    rcall	ADC_START	        ; start conversion of next channel

			
;-------------------------------------------------------------------------------------------------------------------
; Store knob values based on KNOB SHIFT switch setting
; 
; Pots 2-5 have two parameters with the KNOB SHIFT
; switch used to select knob bank 0 or 1. 
;
; To make things more challenging, the ADC value read from each pot might fluctuate
; through several values. This will cause the synth to think the pot has been moved and update
; the parameter value. To avoid this, require the pot to be moved a level of at least
; X before updating (deadzone check). To reduce processing time, a knob status byte
; tracks whether the pots have been moved since the KNOB SHIFT switch was updated.
; If the status bit is set, we can just skip the deadzone check and update.		
;-------------------------------------------------------------------------------------------------------------------
;
; First process the unshifted pots (0, 1, 6, 7)
;

			lds		r20, PREV_ADC_CHAN	; Only process the most recently scanned pot, store ADC channel 0..7 in r20

CHECK_0:
			cpi		r20, 0				; Update knob 0 - filter resonance?
			brne	CHECK_1
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_CHECK_0		; Skip update if pot hasn't been updated
			sts	    RESONANCE,r16
EXIT_CHECK_0:
			lds		r16, RESONANCE		; Limit resonance				 
			cpi		r16, 0xf6					;\  
			BRLO	LOAD_REZ					; | Limit maximum knob resonance to 0xf6 
			ldi		r16, 0xf6					;/
LOAD_REZ:
		    sts	    RESONANCE,r16
			rjmp	DONE_KNOBS	

CHECK_1:
			cpi		r20, 1				; Update knob 1 - filter cutoff?
			brne	CHECK_6
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_KNOBA				; Skip update if pot hasn't been updated
			sts	    CUTOFF,r16
			rjmp	DONE_KNOBS

CHECK_6:
			cpi		r20, 6				; Update knob 6, PWM?
			brne	CHECK_7
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_CHECK_6		; Skip update if pot hasn't been updated
			sts     PULSE_KNOB, r16
EXIT_CHECK_6:
			; Store limited PULSE_WIDTH values
			lds		r16, PULSE_KNOB		; grab the patch value, just in case it hasn't been updated
			lsr		r16					; Divide it by two (we only need 0-50% pulse)
			subi	r16, 18 
			brcc	LIMIT_PWM1
			ldi		r16, 4				; restrict PULSE_KNOB_LIMITED to 4-115 (avoid 0% and 50% pulse)
			rjmp	LIMIT_PWM3		
LIMIT_PWM1:
			cpi		r16, 4
			brlo	LIMIT_PWM2
			rjmp	LIMIT_PWM3
LIMIT_PWM2:
			ldi		r16, 4
LIMIT_PWM3:
			sts		PULSE_KNOB_LIMITED, r16
			rjmp	DONE_KNOBS

CHECK_7:
			cpi		r20, 7				; Update knob 7, OSC Detune?
			brne	KNOB_SHIFT_CHECK	
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_CHECK7			; Skip update if pot hasn't been updated
			sts		OSC_DETUNE, r16
EXIT_CHECK7:
			lds		r16, OSC_DETUNE		; grab the patch value, just in case it hasn't been updated
		    rcall	NONLINPOT		    ; AD6.1 --> DCO B detune with non-linear knob (center is tuned)
		    subi	r17, 128		     
		    sts	    DETUNEB_FRAC, r16	; Value -128.000..+127.996
		    sts	    DETUNEB_INTG, r17	
EXIT_KNOBA:
			rjmp	DONE_KNOBS

			
KNOB_SHIFT_CHECK:

; Now process the shifted pots ( 2, 3, 4, 5)
; Check which bank of knob parameters we're updating.

			lds	    r19, PATCH_SWITCH1
			sbrc	r19, SW_KNOB_SHIFT	; If knob Shift bit set, jump to process bank 1
			jmp		KNOB_BANK_1

;-------------------------------------------------------------------------------------------------------------------
; KNOB BANK 0 - unshifted ( glide, filter envelope amount, LFO depth, LFO rate)
;-------------------------------------------------------------------------------------------------------------------

CHECK_2:
			cpi		r20, 2				; Update knob 2, LFO rate?
			brne	CHECK_3
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_CHECK2A		; Skip update if pot not updated, post-process DCF_DECAY
			sts	    LFOFREQ,r16
			rjmp	EXIT_CHECK2A

CHECK_3:	cpi		r20, 3				; Update knob 3, LFO depth?
			brne	CHECK_4
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_KNOBB			    ; Skip update if pot hasn't been updated
		    sts	    LFOLEVEL,r16		
			sts		PANEL_LFOLEVEL, r16	
			rjmp	DONE_KNOBS

CHECK_4:	cpi		r20, 4				; Update knob 4, Filter envelope amount?
			brne	CHECK_5
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16	
			tst		r17					
			breq	EXIT_CHECK4A		; Skip update if pot hasn't been updated (post process AMP_DECAY parameters)	
			sts	    VCFENVMOD, r16
			rjmp	EXIT_CHECK4A
		
CHECK_5:	cpi		r20, 5				; Update knob 5, Glide/Portamento?
			brne	EXIT_KNOBB
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16	
			tst		r17					
			breq	EXIT_KNOBB			; Skip update if pot hasn't been updated
			lsr		r16					; 50% of original value +
			mov		r17, r16
			lsr		r17					; 25% of original =
			add		r16, r17			; 75% of original
			sts	    PORTAMENTO,r16

EXIT_KNOBB:
			rjmp	DONE_KNOBS
;-------------------------------------------------------------------------------------------------------------------
; KNOB BANK 1
;-------------------------------------------------------------------------------------------------------------------
KNOB_BANK_1:

CHECK_2A:
			cpi		r20, 2				; Update knob 2^, Filter decay?
			brne	CHECK_3A
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	EXIT_CHECK2A		; Skip update if pot hasn't been updated	
			sts	    KNOB_DCF_DECAY, r16		
EXIT_CHECK2A:
			lds		r16, KNOB_DCF_DECAY			; Grab knob patch value just in case it hasn't been changed
			lds		r19, PATCH_SWITCH2
			sbrs	r19, SW_SUSTAIN				
			rjmp	SUSTAIN_OFF					; skip if sustain switch is off
			ldi		r19, 255					; Sustain is on, so...
			sts		SUSTAINLEVEL2, r19			; Set sustain to maximum
			sts		DECAYTIME2, r19				; Set decay to maximum
			sts		RELEASETIME2, r16			; Set release time to value of decay knob
			rjmp	DONE_KNOBS
SUSTAIN_OFF:
			ldi		r19, 0						; Sustain is off, so...
			sts		SUSTAINLEVEL2, r19			; Set sustain to minimum
			sts		DECAYTIME2, r16				; Set decay time to value of decay knob
			sts		RELEASETIME2, r16			; Set release time to value of decay knob
			rjmp	DONE_KNOBS

CHECK_3A:	cpi		r20, 3				; Update knob 3^, Filter attack?
			brne	CHECK_4A
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16
			tst		r17					
			breq	DONE_KNOBS			; Skip update if pot hasn't been updated	
			sts		KNOB_DCF_ATTACK, r16    
			rjmp	DONE_KNOBS

CHECK_4A:	cpi		r20, 4				; Update knob 4^, Amplitude decay?
			brne	CHECK_5A
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16	
			tst		r17					
			breq	EXIT_CHECK4A		; Skip update if pot hasn't been updated		
			sts	    KNOB_AMP_DECAY, r16	
EXIT_CHECK4A:
			lds		r16, KNOB_AMP_DECAY			; Grab knob patch value just in case it hasn't been changed				
			lds		r19, PATCH_SWITCH2
			sbrs	r19, SW_SUSTAIN				
			rjmp	DCF_SUSTAIN_OFF		    ; Skip if sustain is off...
			ldi		r19, 255					; Sustain is on, so...
			sts		SUSTAINLEVEL, r19			; Set sustain to maximum
			sts		DECAYTIME, r19				; Set decay to maximum
			sts		RELEASETIME, r16			; Set release time to value of decay knob
			rjmp	DONE_KNOBS
DCF_SUSTAIN_OFF:
			ldi		r19, 0						; Sustain is off, so...
			sts		SUSTAINLEVEL, r19			; Set sustain to minimum
			sts		DECAYTIME, r16				; Set decay time to value of decay knob
			sts		RELEASETIME, r16			; Set release time to value of decay knob
			rjmp	DONE_KNOBS
		
CHECK_5A:	cpi		r20, 5				; Update knob 5^, Amplitude attack?
			brne	DONE_KNOBS
			rcall	POT_SCAN			; If so, check if parameter should be updated with pot value in r16	
			tst		r17					
			breq	DONE_KNOBS			; Skip update if pot hasn't been updated		
			sts		KNOB_AMP_ATTACK, r16    

DONE_KNOBS:	


;-------------------------------------------------------------------------------------------------------------------
; Add MIDI velocity code here
;-------------------------------------------------------------------------------------------------------------------
		
MIDI_VELOCITY:
; Not implemented, but this is a good spot.		
		
;-------------------------------------------------------------------------------------------------------------------


            ;-------------
            ;calculate dT:
            ;-------------
		    in	    r22, TCNT1L		    ;\
		    in	    r23, TCNT1H		    ;/ r23:r22 = TCNT1 = t
		    mov	    r18, r22		    ;\
    		mov	    r19, r23		    ;/ r19:r18 = t
		    lds	    r16, TPREV_L	    ;\
		    lds	    r17, TPREV_H	    ;/ r17:r16 = t0
		    sub	    r22, r16		    ;\ r23:r22 = t - t0 = dt
		    sbc	    r23, r17		    ;/ (1 bit = 32 µs)
		    sts	    TPREV_L, r18	    ;\
		    sts	    TPREV_H, r19	    ;/ t0 = t
    		sts	    DELTAT_L, r22		;\
		    sts	    DELTAT_H, r23		;/ r23:r22 = dT

            ;----
            ;LFO:
            ;----

;calculate dA:
		    lds	    r16, LFOFREQ	    ;\
		    com	    r16			        ;/ r16 = 255 - ADC0
		    rcall	ADCTORATE           ; r19:r18:r17:r16 = rate of rise/fall
		    lds	    r22, DELTAT_L		;\
    		lds	    r23, DELTAT_H		;/ r23:r22 = dT
		    rcall	MUL32X16		    ; r18:r17:r16 = dA
		    lds	    r19, LFO_FRAC_L
		    lds	    r20, LFO_FRAC_H
    		lds	    r21, LFO_INTEGR
		    subi    r21, 128
		    ldi	    r31, 0			    ; flag = 0
		    lds	    r30, LFOPHASE
		    tst	    r30
		    brne	MLP_LFOFALL

;rising phase:

MLP_LFORISE:
            lds	    r22, LFOTOP_0		;\
		    lds	    r23, LFOTOP_1		; > r24:r23:r22 = Amax
		    lds	    r24, LFOTOP_2		;/
		    add	    r19, r16		    ;\
    		adc	    r20, r17		    ; > A += dA
		    adc	    r21, r18		    ;/
		    brcs	MLP_LFOTOP
		    cp	    r19, r22		    ;\
		    cpc	    r20, r23		    ; > A - Amax
		    cpc	    r21, r24		    ;/
		    brlo	MLP_LFOX		    ; skip when A < Amax

;A reached top limit:

MLP_LFOTOP:
            mov	    r19, r22		    ;\
		    mov	    r20, r23		    ; > A = Amax
		    mov	    r21, r24		   	;/
		    ldi	    r30, 1			    ; begin of falling
		    ldi	    r31, 1			    ; flag = 1
		    rjmp	MLP_LFOX

;falling phase:

MLP_LFOFALL:
            lds	    r22, LFOBOTTOM_0	;\
		    lds	    r23, LFOBOTTOM_1	; > r24:r23:r22 = Amin
		    lds	    r24, LFOBOTTOM_2	;/
    		sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > A -= dA
		    sbc	    r21, r18		    ;/
		    brcs	MLP_LFOBOTTOM
		    cp	    r22, r19		    ;\
		    cpc	    r23, r20		    ; > Amin - A
		    cpc 	r24, r21		    ;/
		    brlo	MLP_LFOX		    ; skip when A > Amin

;A reached bottom limit:

MLP_LFOBOTTOM:
            mov	    r19, r22		    ;\
		    mov	    r20, r23		    ; > A = Amin
		    mov	    r21, r24		    ;/
		    ldi	    r30, 0			    ; begin of rising
		    ldi	    r31, 1			    ; flag = 1

MLP_LFOX:
            sts	    LFOPHASE, r30
		    subi	r21, 128		    ; r21,r20:r19 = LFO tri wave
		    sts	    LFO_FRAC_L, r19		;\
		    sts	    LFO_FRAC_H, r20		; > store LFO value
    		sts	    LFO_INTEGR, r21		;/

;switch norm/rand:

;determine Amin i Amax:
		    ldi	    r16, 0			    ;\
		    ldi	    r17, 0			    ; > Amin when not LFO==tri
    		ldi	    r18, 0			    ;/  and not LFO==rand
		    lds	    r30, PATCH_SWITCH1
			sbrs 	r30, SW_LFO_RANDOM	; LFO random if switch is set
    		RJMP	MLP_LFOAWR
		    tst	    r31
    		breq	MLP_LFOAX
		    lds	    r16, SHIFTREG_0		;\
		    lds	    r17, SHIFTREG_1		; \ Amin = pseudo-random number
		    lds	    r18, SHIFTREG_2		; /	0,000..127,999
		    andi	r18, 0x7F		    ;/

MLP_LFOAWR:
            sts	    LFOBOTTOM_0, r16	;\
		    sts	    LFOBOTTOM_1, r17	; > store Amin
		    sts	    LFOBOTTOM_2, r18	;/
		    com	    r16			        ;\
		    com	    r17			        ; > Amax = 255,999 - Amin
		    com	    r18			        ;/	128,000..255,999
		    sts	    LFOTOP_0, r16		;\
		    sts	    LFOTOP_1, r17		; > store Amax
		    sts	    LFOTOP_2, r18		;/

MLP_LFOAX:
		    lds	    r16, PATCH_SWITCH1
		    sbrs 	r16, SW_LFO_RANDOM
		    rjmp	MLP_LFONORM
		    tst	    r31			        ; flag == 1 ?
		    breq	MLP_LFONWR		    ; jump when not
		    lds	    r21, SHIFTREG_2
		    rjmp	MLP_LFOWR

MLP_LFONORM:

;switch tri/squ:
		    lds	    r16, PATCH_SWITCH1	;\ Z=0: triangle
			sbrs 	r16, SW_LFO_WAVE	;/ Z=1: square
    		rjmp	MLP_LFOWR
		    lsl	    r21			        ; Cy = (LFO < 0)
		    ldi	    r21, 127		    ;\
		    adc	    r21, ZERO		    ;/ r21 = -128 or +127

MLP_LFOWR:
            sts	    LFOVALUE, r21

; Modulation wheel: Use highest value (Front panel or MIDI)
MLP_LFONWR:
		    lds	    r16, PANEL_LFOLEVEL
		    lds	    r17,MIDIMODWHEEL
		    cp	    r16, r17
    		brsh	MLP_LFOLWR
		    mov	    r16, r17		    ; MOD.WHEEL is greater

MLP_LFOLWR:
            sts	    LFOLEVEL, r16

MLP_LFOMWX:

            ;----
            ;LFO2 (Used to sweep PWM waveform)
            ;----

;calculate dA:
		    lds	    r16, PULSE_KNOB	    ; Use PULSE_KNOB as PWM Sweep rate.
			lsr		r16
			lsr		r16					; Limit PWM sweep rate to 0..63 to avoid PWM aliasing
		    com	    r16			        ;/ r16 = 255 - ADC0
		    rcall	ADCTORATE           ; r19:r18:r17:r16 = rate of rise/fall
		    lds	    r22, DELTAT_L		;\
    		lds	    r23, DELTAT_H		;/ r23:r22 = dT
		    rcall	MUL32X16		    ; r18:r17:r16 = dA
		    lds	    r19, LFO2_FRAC_L
		    lds	    r20, LFO2_FRAC_H
    		lds	    r21, LFO2_INTEGR
		    subi    r21, 128
		    ldi	    r31, 0			    ; flag = 0
		    lds	    r30, LFO2PHASE
		    tst	    r30
		    brne	MLP_LFO2FALL

;rising phase:

MLP_LFO2RISE:
            lds	    r22, LFO2TOP_0		;\
		    lds	    r23, LFO2TOP_1		; > r24:r23:r22 = Amax
		    lds	    r24, LFO2TOP_2		;/
		    add	    r19, r16		    ;\
    		adc	    r20, r17		    ; > A += dA
		    adc	    r21, r18		    ;/
		    brcs	MLP_LFO2TOP
		    cp	    r19, r22		    ;\
		    cpc	    r20, r23		    ; > A - Amax
		    cpc	    r21, r24		    ;/
		    brlo	MLP_LFO2X		    ; skip when A < Amax

;A reached top limit:

MLP_LFO2TOP:
            mov	    r19, r22		    ;\
		    mov	    r20, r23		    ; > A = Amax
		    mov	    r21, r24		   	;/
		    ldi	    r30, 1			    ; begin of falling
		    ldi	    r31, 1			    ; flag = 1
		    rjmp	MLP_LFO2X

;falling phase:

MLP_LFO2FALL:
            lds	    r22, LFO2BOTTOM_0	;\
		    lds	    r23, LFO2BOTTOM_1	; > r24:r23:r22 = Amin
		    lds	    r24, LFO2BOTTOM_2	;/
    		sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > A -= dA
		    sbc	    r21, r18		    ;/
		    brcs	MLP_LFO2BOTTOM
		    cp	    r22, r19		    ;\
		    cpc	    r23, r20		    ; > Amin - A
		    cpc 	r24, r21		    ;/
		    brlo	MLP_LFO2X		    ; skip when A > Amin

;A reached bottom limit:

MLP_LFO2BOTTOM:
            mov	    r19, r22		    ;\
		    mov	    r20, r23		    ; > A = Amin
		    mov	    r21, r24		    ;/
		    ldi	    r30, 0			    ; begin of rising
		    ldi	    r31, 1			    ; flag = 1

MLP_LFO2X:
            sts	    LFO2PHASE, r30
		    subi	r21, 128		    ; r21,r20:r19 = LFO2 tri wave
		    sts	    LFO2_FRAC_L, r19	;\
		    sts	    LFO2_FRAC_H, r20	; > store LFO2 value
    		sts	    LFO2_INTEGR, r21	;/

			subi	r21, $80			; remove sign
            sts	    PULSE_WIDTH, r21	; Update pulse width value


			;----
            ;ENV:
            ;----
;check envelope phase:
		    lds	    r17, ENVPHASE
		    lds	    r16, KNOB_AMP_ATTACK
			;cpi		r17, 5				; If we're in pre-attack mode, zero the envelope and start attack, otherwise continue
			;brne	MLP_PHASE
			;ldi	    r17, 0
			;sts	    ENV_FRAC_L, r17		;\
		    ;sts	    ENV_FRAC_H, r17		; > Set envelope to zero
		    ;sts	    ENV_INTEGR, r17		;/		
			;ldi		r17, 1
			;sts		ENVPHASE, r17		    ; store new phase (attack)


MLP_PHASE:  cpi	    r17, 1
		    breq    MLP_ENVAR		    ; when "attack"
			lds		r16, DECAYTIME
			cpi		r17, 2
			breq	MLP_ENVAR			; when "decay"
		    lds	    r16, RELEASETIME
		    cpi	    r17, 4
		    breq	MLP_ENVAR		    ; when "release"
		    rjmp	MLP_EEXIT		    ; when "stop" or "sustain"

;calculate dL:

MLP_ENVAR:
            rcall	ADCTORATE           ; r19:r18:r17:r16 = rate of rise/fall
		    lds	    r22, DELTAT_L		;\
		    lds	    r23, DELTAT_H		;/ r23:r22 = dT
		    rcall	MUL32X16		    ; r18:r17:r16 = dL

;add/subtract dL to/from L:
		    lds	    r19, ENV_FRAC_L		;\
		    lds	    r20, ENV_FRAC_H		; > r21:r20:r19 = L
    		lds	    r21, ENV_INTEGR		;/
		    lds	    r22, ENVPHASE
		    cpi	    r22, 4
		    breq    MLP_ERELEASE

MLP_EATTACK:
			cpi	    r22, 2				
		    breq    MLP_EDECAY			
		    add	    r19, r16		    ;\
		    adc	    r20, r17		    ; > r21:r20:r19 = L + dL
		    adc	    r21, r18		    ;/
		    brcc	MLP_ESTORE

;L reached top limit:
		    ldi	    r19, 255		    ;\
		    ldi	    r20, 255		    ; > L = Lmax
		    ldi	    r21, 255		    ;/
		    ldi	    r16, 2			    ; now decay
		    rjmp	MLP_ESTOREP

MLP_EDECAY:
            sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > r21:r20:r19 = L - dL
		    sbc	    r21, r18		    ;/		
			brcs	MLP_BOTTOM 			; Exit if we went past bottom level
			lds 	r22, SUSTAINLEVEL
			cp		r22, r21				
			brlo 	MLP_ESTORE			; Keep going if we haven't hit sustain level
			ldi	    r16, 3			    ; now sustain
		    rjmp	MLP_ESTOREP
			
MLP_ERELEASE:
            sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > r21:r20:r19 = L - dL
		    sbc	    r21, r18		    ;/
		    brcc	MLP_ESTORE

;L reached bottom limit:
MLP_BOTTOM:
		    ldi	    r19, 0			    ;\
		    ldi	    r20, 0			    ; > L = 0
		    ldi	    r21, 0			    ;/
		    ldi	    r16, 0			    ; stop

MLP_ESTOREP:
            sts	ENVPHASE, r16		    ; store phase

MLP_ESTORE:
            sts	    ENV_FRAC_L, r19		;\
		    sts	    ENV_FRAC_H, r20		; > store L
		    sts	    ENV_INTEGR, r21		;/

MLP_EEXIT:



			;----
            ;ENV 2 (VCF):
            ;----
;check envelope phase:
		    lds	    r17, ENVPHASE2
		    lds	    r16, KNOB_DCF_ATTACK
			;cpi		r17, 5				; If we're in pre-attack mode, zero the envelope and start attack, otherwise continue
			;brne	MLP_PHASE2
			;ldi	    r17, 0
			;sts	    ENV_FRAC_L2, r17		;\
		    ;sts	    ENV_FRAC_H2, r17		; > Set envelope to zero
		    ;sts	    ENV_INTEGr2, r17		;/		
			;ldi		r17, 1
			;sts		ENVPHASE2, r17		    ; store new phase (attack)


MLP_PHASE2:  
			cpi	    r17, 1
		    breq    MLP_ENVAr2		    ; when "attack"
			lds		r16, DECAYTIME2
			cpi		r17, 2
			breq	MLP_ENVAr2			; when "decay"
		    lds	    r16, RELEASETIME2
		    cpi	    r17, 4
		    breq	MLP_ENVAr2		    ; when "release"
		    rjmp	MLP_EEXIT2		    ; when "stop" or "sustain"

;calculate dL:

MLP_ENVAr2:
            rcall	ADCTORATE           ; r19:r18:r17:r16 = rate of rise/fall
		    lds	    r22, DELTAT_L		;\
		    lds	    r23, DELTAT_H		;/ r23:r22 = dT
		    rcall	MUL32X16		    ; r18:r17:r16 = dL

;add/subtract dL to/from L:
		    lds	    r19, ENV_FRAC_L2		;\
		    lds	    r20, ENV_FRAC_H2		; > r21:r20:r19 = L
    		lds	    r21, ENV_INTEGr2		;/
		    lds	    r22, ENVPHASE2
		    cpi	    r22, 4
		    breq    MLP_ERELEASE2

MLP_EATTACK2:
			cpi	    r22, 2				
		    breq    MLP_EDECAY2			
		    add	    r19, r16		    ;\
		    adc	    r20, r17		    ; > r21:r20:r19 = L + dL
		    adc	    r21, r18		    ;/
		    brcc	MLP_ESTORE2

;L reached top limit:
		    ldi	    r19, 255		    ;\
		    ldi	    r20, 255		    ; > L = Lmax
		    ldi	    r21, 255		    ;/
		    ldi	    r16, 2			    ; now decay
		    rjmp	MLP_ESTOREP2

MLP_EDECAY2:
            sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > r21:r20:r19 = L - dL
		    sbc	    r21, r18		    ;/		
			brcs	MLP_BOTTOM2 			; Exit if we went past bottom level
			lds 	r22, SUSTAINLEVEL2
			cp		r22, r21				
			brlo 	MLP_ESTORE2			; Keep going if we haven't hit sustain level
			ldi	    r16, 3			    ; now sustain
		    rjmp	MLP_ESTOREP2
			
MLP_ERELEASE2:
            sub	    r19, r16		    ;\
		    sbc	    r20, r17		    ; > r21:r20:r19 = L - dL
		    sbc	    r21, r18		    ;/
		    brcc	MLP_ESTORE2

;L reached bottom limit:
MLP_BOTTOM2:
		    ldi	    r19, 0			    ;\
		    ldi	    r20, 0			    ; > L = 0
		    ldi	    r21, 0			    ;/
		    ldi	    r16, 0			    ; stop

MLP_ESTOREP2:
            sts	ENVPHASE2, r16		    ; store phase

MLP_ESTORE2:
            sts	    ENV_FRAC_L2, r19		;\
		    sts	    ENV_FRAC_H2, r20		; > store L
		    sts	    ENV_INTEGr2, r21		;/

			; End of Envelope 2

MLP_EEXIT2:
            ;-----
            ;GATE:
            ;-----
		    lds	    r16, GATE
		    tst	    r16			        ; check GATE
		    brne	MLP_KEYON

;no key is pressed:

MLP_KEYOFF:
            ldi	    r16,4			    ;\
		    sts	    ENVPHASE, r16		;/ "release"
			sts		ENVPHASE2, r16		; "release" for envelope 2
		    rjmp	MLP_NOTEON

;key is pressed:

MLP_KEYON:
            lds	    r16, GATEEDGE
		    tst	    r16		            ; Z=0 when key has just been pressed
		    breq	MLP_NOTEON

;key has just been pressed:
		    ldi	    r16, 0			    ;\
		    sts	    GATEEDGE, r16		;/ GATEEDGE = 0			
		    lds	    r16, PORTACNT		;\
		    tst	    r16			        ; \
		    breq	MLP_KEYON1		    ;  > if ( PORTACNT != 0 )
		    dec	    r16			        ; /    PORTACNT--
		    sts	    PORTACNT, r16		;/

MLP_KEYON1:

;envelope starts:	   
			ldi		r16, 1
		    sts	    ENVPHASE, r16		;/ attack
			sts		ENVPHASE2, r16		; attack for envelope 2

; LFO starts when note triggered:
		    ldi	    r16, 255		    ;\
		    ldi	    r17, 255		    ; > A = Amax
		    ldi	    r18, 127		    ;/
		    sts	    LFO_FRAC_L, r16		;\
		    sts	    LFO_FRAC_H, r17		; > store A
		    sts	    LFO_INTEGR, r18		;/
		    ldi	    r16, 1			    ;\
		    sts	    LFOPHASE, r16		;/ begin of falling

MLP_NOTEON:
            ;-------------
            ;DCO A, DCO B:
            ;-------------
		    ldi	    r25, 0			    ;\
		    ldi	    r22, 0			    ; > r23,r22:r25 = note# 0..127
		    lds	    r23, MIDINOTE		;/
		    cpi	    r23, 255
		    brne	MLP_NLIM2
		    rjmp	MLP_VCOX

;note# limited to 36..96:

MLP_NLIM1:
            subi	r23, 12

MLP_NLIM2:
            cpi	    r23, 97
		    brsh	MLP_NLIM1
		    rjmp	MLP_NLIM4

MLP_NLIM3:
            subi	r23, 244

MLP_NLIM4:
            cpi	    r23, 36
		    brlo	MLP_NLIM3

;transpose 1 octave down:
		    subi	r23, 12			    ; n -= 12		Note range limited to 24..84

; Track which wavetable to use:
			mov		r25, r23			; Store a copy of the note number in r25
			subi	r25, 24				; 0..60
			lsr		r25
			lsr		r25					; 0..15
			sts		WAVETABLE, r25		; Save wavetable 0..15 for lookup when generating oscillator

;portamento:
		    lds	    r25, NOTE_L		    ;\
		    lds	    r26, NOTE_H		    ; > r27,r26:r25 = nCurr
		    lds	    r27, NOTE_INTG		;/
		    lds	    r16, PORTACNT		;\
    		tst	    r16			        ; > jump when it's the first note
		    brne	MLP_PORTAWR	        ;/  (PORTACNT != 0)
		    lds	    r16, PORTAMENTO						
    		rcall	ADCTORATE
		    push    r22
		    push	r23
		    mov	    r22, r18		    ;\ r23:r22 = portamento rate
		    mov	    r23, r19		    ;/ 65535..27
		    ldi	    r16, 0
		    ldi	    r17, 0
		    lds	    r18, DELTAT_L
		    lds	    r19, DELTAT_H
		    ldi	    r20, 3
		    rcall	SHr32
		    rcall	MUL32X16		    ; r18,r17:r16 = nDelta
		    pop	    r23
		    pop	    r22
		    mov	    r19, r16		    ;\
		    mov	    r20, r17		    ; > r21,r20:r19 = nDelta
		    mov	    r21, r18		    ;/
		    lds	    r25, NOTE_L		    ;\
		    lds	    r26, NOTE_H		    ; > r27,r26:r25 = nCurr
		    lds	    r27, NOTE_INTG		;/
		    cp	    r22, r26		    ;\ nEnd - nCurr
		    cpc	    r23, r27		    ;/ Cy = (nEnd < nCurr)
		    brsh	MLP_PORTAADD

MLP_PORTAMIN:
            sub	    r25, r19			;\
		    sbc	    r26, r20			; > nCurr -= nDelta
		    sbc	    r27, r21			;/
		    cp	    r22, r26			;\ nEnd - nCurr;
		    cpc	    r23, r27		    ;/ Cy = (nEnd < nCurr)
		    brlo	MLP_PORTA1
		    rjmp	MLP_PORTAEND

MLP_PORTAADD:
            add	    r25, r19		    ;\
		    adc	    r26, r20		    ; > nCurr += nDelta
		    adc	    r27, r21		    ;/
		    cp	    r22, r26		    ;\ nEnd - nCurr;
		    cpc	    r23, r27		    ;/ Cy = (nEnd < nCurr)
		    brsh	MLP_PORTA1

MLP_PORTAEND:
            ldi	    r25, 0			    ;\
		    mov	    r26, r22			; > nCurr = nEnd
    		mov	    r27, r23			;/

MLP_PORTA1:
            mov	    r22, r26
		    mov	    r23, r27

MLP_PORTAWR:
        	sts	NOTE_L, r25
		    sts	    NOTE_H, r22
		    sts	    NOTE_INTG, r23

;pitch bender (-12..+12):
		    lds	    r16, MIDIPBEND_L	;\ r17,r16 = P.BEND
    		lds	    r17, MIDIPBEND_H	;/	-128,000..+127,996
		    ldi	    r18, 5			    ;\ r17,r16 = P.BEND/32
		    rcall	ASr16			    ;/	-4,000..+3,999
		    mov	    r18, r16		    ;\ r19,r18 = P.BEND/32
		    mov	    r19, r17		    ;/	-4,000..+3,999
		    add	    r16, r18		    ;\ r17,r16 = 2/32*P.BEND
		    adc	    r17, r19		    ;/	-8,000..+7,999
		    add	    r16, r18		    ;\ r17,r16 = 3/32*P.BEND
		    adc	    r17, r19		    ;/	-12,000..+11,999
		    add	    r22, r16		    ;\
		    adc	    r23, r17		    ;/ add P.BEND

MLP_PBX:
;for "DCF KBD TRACK":
		    sts	    PITCH, r23		    ; n = 0..108


;LFO modulation:
		    lds	    r16, PATCH_SWITCH1	; Check LFO destination bit. 
		    sbrs	r16, SW_LFO_DEST	; DCF is 0, DCO is 1
		    jmp		MLP_VCOLFOX		    ; exit when LFO=DCF
		    lds	    r16, LFOVALUE		; r16 = LFO	    -128..+127
    		lds	    r17, LFOLEVEL		; r17 = LFO level	0..255

			lds	    r18, PATCH_SWITCH1	; Is the LFO enabled? 
			sbrs	r18, SW_LFO_ENABLE	
			ldi		r17, 0				; Set LFO level to zero if switch is off

;nonlinear potentiometer function:
		    mov	    r18, r17		    ; r18 = LL
		    lsr	    r17			        ; r17 = LL/2
		    cpi	    r18, 128
		    brlo	MLP_OM1			    ; skip if LL = 0..127
		    subi	r17, 128		    ; r17 = 0,5*LL-128    -64..-1
		    add	    r17, r18		    ; r17 = 1,5*LL-128    +64..254

MLP_OM1:
            rcall	MUL8X8S			    ; r17,r16 = LFO*mod
		    ldi	    r18, 4			    ;\
		    rcall	ASr16			    ;/ r17,r16 = LFO*mod / 16
		    add	    r22, r16		    ;\
		    adc	    r23, r17		    ;/ add LFO to note #

;limiting to 0..108
		    tst	    r23
		    brpl	MLP_VCOLFO1
		    ldi	    r22, 0
		    ldi	    r23, 0
		    rjmp	MLP_VCOLFOX

MLP_VCOLFO1:
            cpi	    r23, 109
		    brlo	MLP_VCOLFOX
		    ldi	    r22, 0
		    ldi	    r23, 108

MLP_VCOLFOX:
            push	r22			        ;\ note# = 0..108
		    push	r23			        ;/ store for phase delta B

;phase delta A:
;octave A:
		    rcall	NOTERECALC		    ; r23,r22 = m12 (0,0..11,996),
						                ; r20 = n12 (0..11)
		    rcall	LOAD_DELTA		    ; r19:r18:r17:r16 = delta
		    rcall	SHL32			    ; r19:r18:r17:r16 = delta*(2^exp)

			  ; store delta
  			sts DELTAA_0,r17
  			sts DELTAA_1,r18
  			sts DELTAA_2,r19

;phase delta B:
		    pop	    r23			        ;\
		    pop	    r22			        ;/ n

;detune B:
		    lds	    r16, DETUNEB_FRAC	;\ r17,r16 = detuneB
		    lds	    r17, DETUNEB_INTG	;/ -128,000..+127,996
		    ldi	    r18, 4			    ;\ r17,r16 = detuneB / 16
    		rcall	ASr16			    ;/ -8,0000..+7,9998
		    add	    r22, r16		    ;\
		    adc	    r23, r17		    ;/

;octave B:
            lds	    r16, PATCH_SWITCH2	; b7 = octave B: 0=down, 1=up
		    sbrc	r16, SW_OSCB_OCT
		    subi	r23, 244		    ; n += 12
		    rcall	NOTERECALC		    ; r23,r22 = m12 (0,0..11,996),
						                ; r20 = n12 (0..11)
		    rcall	LOAD_DELTA		    ; r19:r18:r17:r16 = delta
		    rcall	SHL32			    ; r19:r18:r17:r16 = delta*(2^exp)

			sts DELTAB_0,r17
  			sts DELTAB_1,r18
  			sts DELTAB_2,r19
 

MLP_VCOX:

            ;----
            ;DCF:
            ;----
	        ;LFO mod:
		    ldi	    r30, 0			    ;\
		    ldi	    r31, 0			    ;/ sum = 0

		    lds	    r16, PATCH_SWITCH1	; Check LFO destination bit. 
		    sbrc	r16, SW_LFO_DEST	; DCF is 0, DCO is 1
		    jmp		MLP_DCF0		    ; exit when LFO=DCO
		    lds	    r16, LFOVALUE		; r16 = LFO	    -128..+127
		    lds	    r17, LFOLEVEL		; r17 = DCF LFO MOD	0..255
			lds	    r18, PATCH_SWITCH1	; Is the LFO enabled? 
			sbrs	r18, SW_LFO_ENABLE	
			ldi		r17, 0				; Set LFO level to zero if switch is off
		    rcall	MUL8X8S			    ; r17,r16 = LFO * VCFLFOMOD
		    mov	    r30, r17
		    ldi	    r31, 0
		    rol	    r17			        ; r17.7 --> Cy (sign)
		    sbc	    r31, r31		    ; sign extension to r31

MLP_DCF0:

;ENV mod:
            lds	    r16, ENV_INTEGr2	; Get the integer part of the filter envelope
		    lds	    r17, VCFENVMOD
			mul		r16, r17
			movw 	r16,r0				; r17,r16 = FILTER ENV * ENVMOD		    
    		rol	    r16			        ; Cy = r16.7 (for rounding)
		    adc	    r30, r17
		    adc	    r31, ZERO

;KBD TRACK:
		    lds	    r16, PITCH		    ; r16 = n (12/octave)	0..96
		    lsl	    r16			        ; r16 = 2*n (24/octave)	0..192
		    subi	r16, 96	        	; r16 = 2*(n-48) (24/octave)   -96..+96
		    ldi	    r17, 171

		    rcall	MUL8X8S		        ; r17 = 1,5*(n-48) (16/octave) -64..+64
		    ldi	    r18, 0			    ;\
		    sbrc	r17, 7			    ; > r18 = sign extension
		    ldi	    r18, 255		    ;/  of r17
		    add	    r30, r17
		    adc	    r31, r18

MLP_DCF3:
;CUTOFF:
		    lds	    r16, CUTOFF
		    clr	    r17
		    add	    r16, r30
    		adc	    r17, r31
		    tst	    r17
		    brpl	MLP_DCF1
		    ldi	    r16, 0
		    rjmp	MLP_DCF2

MLP_DCF1:
            breq	MLP_DCF2
		    ldi	    r16, 255

MLP_DCF2:

			lsr	    r16			        ; 0..127
		    ldi	    r30, TAB_VCF	    ;\
    		ldi	    r31, 0			    ;/ Z = &Tab
		    rcall	TAB_BYTE		    ; r0 = 1.. 255
		    sts	    LPF_I, r0			; Store Lowpass F value
			ldi		r16, 10
			sub 	r0, r16				; Offset HP knob value
			brcc	STORE_HPF
			ldi		r16, 0x00			; Limit HP to min of 0
			mov		r0, r16
STORE_HPF:
			sts		HPF_I, r0
			


            ;---------------
            ;sound level:
            ;---------------

MLP_VCAENV:
            lds	    r16,ENV_INTEGR		; 
		    ldi	    r30, TAB_VCA	    ;\
		    ldi	    r31, 0			    ;/ Z = &Tab
		    rcall	TAB_BYTE		    ; r0 = 2..255
		    mov	    r16, r0
MLP_VCAOK:
            sts		LEVEL,r16
            ;-----------------------------------
            ;pseudo-random shift register:
            ;-----------------------------------
	        ;BIT = SHIFTREG.23 xor SHIFTREG.18
	        ;SHIFTREG = (SHIFTREG << 1) + BIT
		    lds	    r16, SHIFTREG_0
		    lds	    r17, SHIFTREG_1
		    lds	    r18, SHIFTREG_2
    		bst	    r18, 7			    ;\
		    bld	    r19, 0			    ;/ r19.0 = SHIFTREG.23
		    bst	    r18, 2			    ;\
		    bld	    r20, 0			    ;/ r20.0 = SHIFTREG.18
		    eor	    r19, r20			    ;r19.0 = BIT
		    lsr	    r19			        ; Cy = BIT
		    rol	    r16			        ;\
		    rol	    r17			        ; > r18:r17:r16 =
		    rol	    r18			        ;/  = (SHIFTREG << 1) + BIT
		    sts	    SHIFTREG_0, r16
		    sts	    SHIFTREG_1, r17
		    sts	    SHIFTREG_2, r18


            ;------------------------
            ;back to the main loop:
            ;------------------------
		    rjmp	MAINLOOP

;-------------------------------------------------------------------------------------------------------------------
;
;*** Bandlimited sawtooth wavetables (each table is 256 bytes long, unsigned integer)
SAW_LIMIT0: .db $F7,$FE,$FF,$FF,$FE,$FE,$FD,$FC,$FB,$FA,$F9,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F1,$F0,$EE,$ED,$EC,$EB,$EA,$E9,$E8,$E7,$E6,$E5,$E4,$E3,$E2,$E1,$E0,$DF,$DE,$DD,$DC,$DB,$DA,$D9,$D8,$D7,$D6,$D5,$D4,$D3,$D1,$D0,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C5,$C4,$C3,$C2,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B7,$B5,$B4,$B3,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9B,$99,$98,$97,$96,$95,$94,$93,$92,$91,$90,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85,$84,$83,$82,$81,$7F,$7E,$7D,$7C,$7B,$7A,$79,$78,$77,$76,$75,$74,$73,$72,$71,$70,$6F,$6E,$6D,$6C,$6B,$6A,$69,$68,$67,$66,$64,$63,$62,$61,$60,$5F,$5E,$5D,$5C,$5B,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4F,$4E,$4D,$4C,$4B,$4A,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3D,$3C,$3B,$3A,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$2F,$2E,$2C,$2B,$2A,$29,$28,$27,$26,$25,$24,$23,$22,$21,$20,$1F,$1E,$1D,$1C,$1B,$1A,$19,$18,$17,$16,$15,$14,$13,$12,$11,$0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$01,$00,$00,$01,$08,$7F
SAW_LIMIT1: .db $F6,$FF,$FF,$FD,$FC,$FA,$FA,$F9,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F1,$F0,$EF,$EE,$ED,$EC,$EB,$EA,$E9,$E8,$E7,$E6,$E4,$E3,$E3,$E2,$E1,$DF,$DE,$DD,$DD,$DC,$DA,$D9,$D8,$D7,$D6,$D5,$D4,$D3,$D2,$D1,$D0,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C5,$C4,$C3,$C2,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B7,$B6,$B5,$B4,$B3,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9B,$9A,$99,$98,$97,$96,$95,$94,$93,$92,$91,$90,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85,$84,$83,$82,$81,$7F,$7E,$7D,$7C,$7B,$7A,$79,$78,$77,$76,$75,$74,$73,$72,$71,$70,$6F,$6E,$6D,$6C,$6B,$6A,$69,$68,$67,$66,$65,$64,$63,$62,$61,$60,$5F,$5E,$5D,$5C,$5B,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4F,$4E,$4D,$4C,$4B,$4A,$49,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3D,$3C,$3B,$3A,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$2F,$2E,$2D,$2C,$2B,$2A,$29,$28,$27,$26,$25,$23,$22,$22,$21,$20,$1E,$1D,$1C,$1C,$1B,$19,$18,$17,$16,$15,$14,$13,$12,$11,$10,$0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$05,$03,$02,$00,$00,$09,$7F
SAW_LIMIT2: .db $F7,$FF,$FE,$FD,$FC,$FB,$FA,$F9,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F0,$EF,$EE,$ED,$EC,$EB,$EA,$E9,$E8,$E7,$E6,$E5,$E4,$E3,$E2,$E1,$E0,$DF,$DE,$DD,$DC,$DB,$DA,$D9,$D8,$D7,$D6,$D5,$D4,$D3,$D2,$D1,$D0,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C5,$C4,$C3,$C2,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B7,$B6,$B5,$B4,$B3,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9B,$9A,$99,$98,$97,$96,$95,$94,$93,$92,$91,$90,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85,$84,$83,$82,$81,$7F,$7E,$7D,$7C,$7B,$7A,$79,$78,$77,$76,$75,$74,$73,$72,$71,$70,$6F,$6E,$6D,$6C,$6B,$6A,$69,$68,$67,$66,$65,$64,$63,$62,$61,$60,$5F,$5E,$5D,$5C,$5B,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4F,$4E,$4D,$4C,$4B,$4A,$49,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3D,$3C,$3B,$3A,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$2F,$2E,$2D,$2C,$2B,$2A,$29,$28,$27,$26,$25,$24,$23,$22,$21,$20,$1F,$1E,$1D,$1C,$1B,$1A,$19,$18,$17,$16,$15,$14,$13,$12,$11,$10,$0F,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$08,$7F
SAW_LIMIT3: .db $F7,$FF,$FF,$FC,$FC,$FB,$FA,$F9,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F1,$F0,$EF,$EE,$ED,$EC,$EB,$EA,$E9,$E8,$E7,$E6,$E5,$E4,$E3,$E2,$E1,$E0,$DF,$DD,$DD,$DB,$DB,$D9,$D9,$D7,$D6,$D5,$D4,$D3,$D2,$D1,$D0,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C5,$C4,$C3,$C2,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B7,$B6,$B5,$B4,$B3,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9B,$9A,$99,$98,$97,$96,$95,$94,$93,$92,$91,$90,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85,$84,$83,$82,$81,$7F,$7E,$7D,$7C,$7B,$7A,$79,$78,$77,$76,$75,$74,$73,$72,$71,$70,$6F,$6E,$6D,$6C,$6B,$6A,$69,$68,$67,$66,$65,$64,$63,$62,$61,$60,$5F,$5E,$5D,$5C,$5B,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4F,$4E,$4D,$4C,$4B,$4A,$49,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3D,$3C,$3B,$3A,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$2F,$2E,$2D,$2C,$2B,$2A,$29,$28,$26,$26,$24,$24,$22,$22,$20,$1F,$1E,$1D,$1C,$1B,$1A,$19,$18,$17,$16,$15,$14,$13,$12,$11,$10,$0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$03,$00,$00,$08,$7F
SAW_LIMIT4: .db $F5,$FF,$FB,$FD,$F8,$FB,$F7,$F7,$F7,$F4,$F5,$F3,$F3,$F1,$F0,$F0,$EE,$EE,$EC,$EB,$EA,$E9,$E9,$E7,$E6,$E5,$E4,$E4,$E2,$E1,$E0,$DF,$DE,$DD,$DC,$DB,$DA,$D9,$D8,$D7,$D6,$D5,$D4,$D3,$D2,$D1,$D0,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C5,$C4,$C3,$C2,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B7,$B6,$B5,$B4,$B3,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A5,$A3,$A2,$A1,$A0,$A0,$9E,$9D,$9C,$9B,$9B,$99,$99,$97,$96,$95,$94,$94,$92,$91,$90,$8F,$8F,$8D,$8D,$8B,$8A,$8A,$88,$88,$86,$86,$85,$83,$83,$81,$81,$7F,$7E,$7E,$7C,$7C,$7A,$79,$79,$77,$77,$75,$75,$74,$72,$72,$70,$70,$6F,$6E,$6D,$6B,$6B,$6A,$69,$68,$66,$66,$64,$64,$63,$62,$61,$5F,$5F,$5E,$5D,$5C,$5A,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$4F,$4E,$4D,$4C,$4B,$4A,$49,$48,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3D,$3C,$3B,$3A,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$2F,$2E,$2D,$2C,$2B,$2A,$29,$28,$27,$26,$25,$24,$23,$22,$21,$20,$1F,$1E,$1D,$1B,$1B,$1A,$19,$18,$16,$16,$15,$14,$13,$11,$11,$0F,$0F,$0E,$0C,$0C,$0A,$0B,$08,$08,$08,$04,$07,$02,$04,$00,$0A,$7F
SAW_LIMIT5: .db $E9,$FF,$F1,$F5,$F7,$F0,$F2,$F3,$EE,$EF,$F0,$EC,$EC,$EC,$E9,$E9,$E9,$E7,$E6,$E6,$E4,$E3,$E3,$E1,$E0,$E1,$DF,$DD,$DE,$DC,$DB,$DB,$D9,$D8,$D8,$D6,$D5,$D5,$D4,$D2,$D2,$D1,$CF,$CF,$CE,$CD,$CC,$CB,$CA,$C9,$C8,$C7,$C6,$C6,$C4,$C4,$C3,$C1,$C1,$C0,$BF,$BE,$BD,$BC,$BB,$BA,$B9,$B8,$B8,$B6,$B5,$B5,$B3,$B2,$B2,$B1,$AF,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5,$A4,$A4,$A3,$A1,$A1,$A0,$9E,$9E,$9D,$9C,$9B,$9A,$99,$98,$97,$96,$95,$94,$93,$92,$92,$90,$8F,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85,$84,$83,$82,$81,$81,$7F,$7E,$7E,$7D,$7C,$7B,$7A,$79,$78,$77,$76,$75,$74,$73,$72,$71,$70,$70,$6F,$6D,$6D,$6C,$6B,$6A,$69,$68,$67,$66,$65,$64,$63,$62,$61,$61,$5F,$5E,$5E,$5C,$5B,$5B,$5A,$59,$58,$57,$56,$55,$54,$53,$52,$51,$50,$50,$4E,$4D,$4D,$4C,$4A,$4A,$49,$47,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3E,$3E,$3C,$3B,$3B,$39,$39,$38,$37,$36,$35,$34,$33,$32,$31,$30,$30,$2E,$2D,$2D,$2B,$2A,$2A,$29,$27,$27,$26,$24,$24,$23,$21,$22,$20,$1E,$1F,$1E,$1C,$1C,$1B,$19,$19,$18,$16,$16,$16,$13,$13,$13,$0F,$10,$11,$0C,$0D,$0F,$08,$0A,$0E,$00,$16,$7F
SAW_LIMIT6: .db $DC,$FF,$F3,$E9,$F0,$F3,$ED,$E9,$ED,$EE,$E9,$E7,$EA,$E9,$E5,$E4,$E6,$E5,$E1,$E1,$E2,$E0,$DE,$DE,$DE,$DC,$DA,$DB,$DB,$D8,$D7,$D7,$D7,$D5,$D3,$D4,$D3,$D1,$D0,$D0,$CF,$CD,$CD,$CD,$CB,$CA,$C9,$C9,$C8,$C6,$C6,$C5,$C4,$C2,$C2,$C2,$C0,$BF,$BF,$BE,$BC,$BB,$BB,$BA,$B8,$B8,$B7,$B6,$B5,$B4,$B4,$B3,$B1,$B1,$B0,$AF,$AD,$AD,$AD,$AB,$AA,$AA,$A9,$A7,$A6,$A6,$A5,$A4,$A3,$A2,$A1,$A0,$9F,$9F,$9E,$9C,$9C,$9B,$9A,$99,$98,$98,$96,$95,$94,$94,$93,$91,$91,$90,$8F,$8E,$8D,$8D,$8B,$8A,$8A,$89,$87,$87,$86,$85,$84,$83,$83,$81,$80,$80,$7F,$7E,$7C,$7C,$7B,$7A,$79,$78,$78,$76,$75,$75,$74,$72,$72,$71,$70,$6F,$6E,$6E,$6C,$6B,$6B,$6A,$69,$67,$67,$66,$65,$64,$63,$63,$61,$60,$60,$5F,$5E,$5D,$5C,$5B,$5A,$59,$59,$58,$56,$55,$55,$54,$52,$52,$52,$50,$4F,$4E,$4E,$4C,$4B,$4B,$4A,$49,$48,$47,$47,$45,$44,$44,$43,$41,$40,$40,$3F,$3D,$3D,$3D,$3B,$3A,$39,$39,$37,$36,$36,$35,$34,$32,$32,$32,$30,$2F,$2F,$2E,$2C,$2B,$2C,$2A,$28,$28,$28,$27,$24,$24,$25,$23,$21,$21,$21,$1F,$1D,$1E,$1E,$1A,$19,$1B,$1A,$16,$15,$18,$16,$11,$12,$16,$12,$0C,$0F,$16,$0C,$00,$23,$7F
SAW_LIMIT7: .db $D0,$FC,$FF,$EF,$E7,$ED,$F3,$F1,$EA,$E7,$EA,$ED,$EB,$E6,$E4,$E6,$E8,$E5,$E1,$E0,$E2,$E2,$E0,$DD,$DC,$DE,$DD,$DB,$D9,$D8,$D9,$D9,$D6,$D4,$D4,$D5,$D4,$D1,$D0,$D0,$D0,$CF,$CD,$CB,$CB,$CB,$CA,$C8,$C7,$C7,$C7,$C5,$C3,$C2,$C2,$C2,$C1,$BF,$BE,$BE,$BE,$BC,$BA,$B9,$B9,$B9,$B7,$B6,$B5,$B5,$B4,$B3,$B1,$B1,$B0,$B0,$AE,$AD,$AC,$AC,$AB,$A9,$A8,$A8,$A7,$A6,$A5,$A3,$A3,$A3,$A2,$A0,$9F,$9F,$9E,$9D,$9B,$9A,$9A,$9A,$98,$97,$96,$96,$95,$94,$92,$91,$91,$90,$8F,$8E,$8D,$8D,$8C,$8A,$89,$88,$88,$87,$86,$84,$84,$84,$83,$81,$80,$7F,$7F,$7E,$7C,$7B,$7B,$7B,$79,$78,$77,$77,$76,$75,$73,$72,$72,$71,$70,$6F,$6E,$6E,$6D,$6B,$6A,$69,$69,$68,$67,$65,$65,$65,$64,$62,$61,$60,$60,$5F,$5D,$5C,$5C,$5C,$5A,$59,$58,$57,$57,$56,$54,$53,$53,$52,$51,$4F,$4F,$4E,$4E,$4C,$4B,$4A,$4A,$49,$48,$46,$46,$46,$45,$43,$41,$41,$41,$40,$3E,$3D,$3D,$3D,$3C,$3A,$38,$38,$38,$37,$35,$34,$34,$34,$32,$30,$2F,$2F,$2F,$2E,$2B,$2A,$2B,$2B,$29,$26,$26,$27,$26,$24,$22,$21,$23,$22,$1F,$1D,$1D,$1F,$1E,$1A,$17,$19,$1B,$19,$14,$12,$15,$18,$15,$0E,$0C,$12,$18,$10,$00,$03,$2F,$7F
SAW_LIMIT8: .db $C1,$EE,$FF,$F9,$EB,$E3,$E4,$EB,$EF,$ED,$E7,$E2,$E1,$E5,$E7,$E6,$E2,$DE,$DD,$DF,$E1,$E0,$DD,$DA,$D8,$D9,$DB,$DA,$D8,$D5,$D3,$D4,$D5,$D5,$D3,$D0,$CE,$CE,$CF,$CF,$CE,$CB,$C9,$C9,$C9,$C9,$C8,$C6,$C4,$C4,$C4,$C4,$C3,$C1,$BF,$BE,$BE,$BE,$BE,$BC,$BA,$B9,$B9,$B9,$B8,$B7,$B5,$B4,$B3,$B3,$B3,$B2,$B0,$AE,$AE,$AE,$AE,$AC,$AB,$A9,$A9,$A8,$A8,$A7,$A5,$A4,$A3,$A3,$A3,$A2,$A0,$9F,$9E,$9E,$9D,$9D,$9B,$99,$98,$98,$98,$97,$96,$94,$93,$93,$93,$92,$91,$8F,$8E,$8D,$8D,$8D,$8B,$8A,$89,$88,$88,$87,$86,$85,$83,$82,$82,$82,$81,$7F,$7E,$7D,$7D,$7D,$7C,$7A,$79,$78,$77,$77,$76,$75,$74,$72,$72,$72,$71,$70,$6E,$6D,$6C,$6C,$6C,$6B,$69,$68,$67,$67,$67,$66,$64,$62,$62,$61,$61,$60,$5F,$5D,$5C,$5C,$5C,$5B,$5A,$58,$57,$57,$56,$56,$54,$53,$51,$51,$51,$51,$4F,$4D,$4C,$4C,$4C,$4B,$4A,$48,$47,$46,$46,$46,$45,$43,$41,$41,$41,$41,$40,$3E,$3C,$3B,$3B,$3B,$3B,$39,$37,$36,$36,$36,$36,$34,$31,$30,$30,$31,$31,$2F,$2C,$2A,$2A,$2B,$2C,$2A,$27,$25,$24,$26,$27,$25,$22,$1F,$1E,$20,$22,$21,$1D,$19,$18,$1A,$1E,$1D,$18,$12,$10,$14,$1B,$1C,$14,$06,$00,$11,$3E,$7F
SAW_LIMIT9: .db $B6,$E1,$F9,$FF,$F7,$EB,$E2,$E0,$E4,$E9,$ED,$EC,$E7,$E2,$DE,$DE,$E0,$E3,$E4,$E2,$DE,$DB,$D9,$D9,$DB,$DC,$DC,$D9,$D6,$D4,$D3,$D3,$D4,$D5,$D4,$D1,$CF,$CD,$CC,$CD,$CE,$CD,$CC,$CA,$C7,$C6,$C6,$C6,$C7,$C6,$C4,$C2,$C0,$BF,$BF,$C0,$C0,$BF,$BD,$BB,$B9,$B9,$B9,$B9,$B8,$B7,$B5,$B3,$B2,$B2,$B2,$B2,$B1,$B0,$AE,$AC,$AB,$AB,$AB,$AB,$AA,$A8,$A6,$A5,$A5,$A5,$A4,$A4,$A3,$A1,$9F,$9E,$9E,$9E,$9E,$9D,$9B,$9A,$98,$97,$97,$97,$97,$95,$94,$92,$91,$90,$90,$90,$8F,$8E,$8D,$8B,$8A,$8A,$8A,$89,$88,$87,$85,$84,$83,$83,$83,$82,$81,$7F,$7E,$7D,$7C,$7C,$7C,$7B,$7A,$78,$77,$76,$75,$75,$75,$74,$72,$71,$70,$6F,$6F,$6F,$6E,$6D,$6B,$6A,$68,$68,$68,$68,$67,$65,$64,$62,$61,$61,$61,$61,$60,$5E,$5C,$5B,$5B,$5A,$5A,$5A,$59,$57,$55,$54,$54,$54,$54,$53,$51,$4F,$4E,$4D,$4D,$4D,$4D,$4C,$4A,$48,$47,$46,$46,$46,$46,$44,$42,$40,$3F,$3F,$40,$40,$3F,$3D,$3B,$39,$38,$39,$39,$39,$38,$35,$33,$32,$31,$32,$33,$32,$30,$2E,$2B,$2A,$2B,$2C,$2C,$2B,$29,$26,$23,$23,$24,$26,$26,$24,$21,$1D,$1B,$1C,$1F,$21,$21,$1D,$18,$13,$12,$16,$1B,$1F,$1D,$14,$08,$00,$06,$1E,$49,$7F
SAW_LIMIT10: .db $AB,$D1,$ED,$FC,$FF,$F9,$F0,$E6,$DF,$DE,$E0,$E4,$E9,$EB,$EA,$E7,$E2,$DD,$DA,$DA,$DB,$DE,$DF,$E0,$DE,$DB,$D8,$D5,$D3,$D3,$D4,$D5,$D6,$D6,$D4,$D1,$CF,$CC,$CB,$CB,$CC,$CD,$CD,$CC,$CA,$C8,$C6,$C4,$C3,$C3,$C4,$C4,$C4,$C3,$C1,$BF,$BD,$BB,$BB,$BB,$BB,$BB,$BB,$B9,$B7,$B5,$B4,$B3,$B2,$B3,$B3,$B2,$B2,$B0,$AE,$AC,$AB,$AA,$AA,$AA,$AA,$AA,$A8,$A7,$A5,$A3,$A2,$A2,$A2,$A2,$A1,$A1,$9F,$9E,$9C,$9A,$9A,$99,$99,$99,$99,$98,$96,$95,$93,$92,$91,$91,$91,$90,$90,$8F,$8D,$8B,$8A,$89,$88,$88,$88,$88,$87,$86,$84,$82,$81,$80,$80,$7F,$7F,$7F,$7E,$7D,$7B,$79,$78,$77,$77,$77,$77,$76,$75,$74,$72,$70,$6F,$6F,$6E,$6E,$6E,$6D,$6C,$6A,$69,$67,$66,$66,$66,$66,$65,$65,$63,$61,$60,$5E,$5E,$5D,$5D,$5D,$5D,$5C,$5A,$58,$57,$55,$55,$55,$55,$55,$54,$53,$51,$4F,$4D,$4D,$4C,$4C,$4D,$4C,$4B,$4A,$48,$46,$44,$44,$44,$44,$44,$44,$42,$40,$3E,$3C,$3B,$3B,$3B,$3C,$3C,$3B,$39,$37,$35,$33,$32,$32,$33,$34,$34,$33,$30,$2E,$2B,$29,$29,$2A,$2B,$2C,$2C,$2A,$27,$24,$21,$1F,$20,$21,$24,$25,$25,$22,$1D,$18,$15,$14,$16,$1B,$1F,$21,$20,$19,$0F,$06,$00,$03,$12,$2E,$54,$7F
SAW_LIMIT11: .db $A2,$C2,$DC,$EF,$FB,$FF,$FD,$F7,$EF,$E6,$E0,$DC,$DB,$DD,$E0,$E3,$E6,$E8,$E7,$E5,$E2,$DE,$DA,$D7,$D5,$D5,$D6,$D8,$D9,$DA,$DA,$D9,$D7,$D4,$D1,$CE,$CC,$CC,$CC,$CC,$CD,$CE,$CE,$CD,$CC,$CA,$C7,$C5,$C3,$C2,$C1,$C1,$C2,$C2,$C2,$C2,$C1,$BF,$BD,$BB,$B9,$B8,$B7,$B6,$B7,$B7,$B7,$B7,$B6,$B5,$B3,$B1,$AF,$AD,$AC,$AC,$AC,$AC,$AC,$AC,$AB,$AA,$A9,$A7,$A5,$A3,$A2,$A1,$A1,$A1,$A1,$A1,$A0,$9F,$9E,$9D,$9B,$99,$98,$97,$96,$96,$96,$96,$95,$95,$94,$92,$91,$8F,$8D,$8C,$8B,$8B,$8B,$8B,$8A,$8A,$89,$88,$86,$85,$83,$82,$80,$80,$80,$80,$7F,$7F,$7F,$7D,$7C,$7A,$79,$77,$76,$75,$75,$74,$74,$74,$74,$73,$72,$70,$6E,$6D,$6B,$6A,$6A,$69,$69,$69,$69,$68,$67,$66,$64,$62,$61,$60,$5F,$5E,$5E,$5E,$5E,$5E,$5D,$5C,$5A,$58,$56,$55,$54,$53,$53,$53,$53,$53,$53,$52,$50,$4E,$4C,$4A,$49,$48,$48,$48,$48,$49,$48,$47,$46,$44,$42,$40,$3E,$3D,$3D,$3D,$3D,$3E,$3E,$3D,$3C,$3A,$38,$35,$33,$32,$31,$31,$32,$33,$33,$33,$33,$31,$2E,$2B,$28,$26,$25,$25,$26,$27,$29,$2A,$2A,$28,$25,$21,$1D,$1A,$18,$17,$19,$1C,$1F,$22,$24,$23,$1F,$19,$10,$08,$02,$00,$04,$10,$23,$3D,$5D,$7F
SAW_LIMIT12: .db $9C,$B6,$CE,$E2,$F0,$FA,$FF,$FF,$FC,$F6,$EF,$E8,$E2,$DD,$DA,$D9,$DA,$DC,$DF,$E1,$E4,$E5,$E5,$E4,$E2,$DE,$DB,$D7,$D4,$D2,$D1,$D0,$D1,$D1,$D3,$D4,$D4,$D5,$D4,$D2,$D0,$CE,$CB,$C9,$C7,$C5,$C4,$C4,$C4,$C5,$C5,$C6,$C6,$C5,$C4,$C3,$C1,$BF,$BC,$BA,$B9,$B7,$B7,$B7,$B7,$B7,$B7,$B7,$B7,$B6,$B5,$B3,$B2,$B0,$AE,$AC,$AB,$AA,$A9,$A9,$A9,$A9,$A9,$A9,$A8,$A8,$A6,$A5,$A3,$A1,$9F,$9E,$9C,$9C,$9B,$9B,$9B,$9B,$9B,$9B,$9A,$99,$97,$96,$94,$92,$91,$8F,$8E,$8E,$8D,$8D,$8D,$8D,$8D,$8C,$8B,$8A,$89,$87,$85,$83,$82,$81,$80,$80,$80,$80,$7F,$7F,$7F,$7E,$7D,$7C,$7A,$78,$76,$75,$74,$73,$72,$72,$72,$72,$72,$71,$71,$70,$6E,$6D,$6B,$69,$68,$66,$65,$64,$64,$64,$64,$64,$64,$63,$63,$61,$60,$5E,$5C,$5A,$59,$57,$57,$56,$56,$56,$56,$56,$56,$55,$54,$53,$51,$4F,$4D,$4C,$4A,$49,$48,$48,$48,$48,$48,$48,$48,$48,$46,$45,$43,$40,$3E,$3C,$3B,$3A,$39,$39,$3A,$3A,$3B,$3B,$3B,$3A,$38,$36,$34,$31,$2F,$2D,$2B,$2A,$2B,$2B,$2C,$2E,$2E,$2F,$2E,$2D,$2B,$28,$24,$21,$1D,$1B,$1A,$1A,$1B,$1E,$20,$23,$25,$26,$25,$22,$1D,$17,$10,$09,$03,$00,$00,$05,$0F,$1D,$31,$49,$63,$7F
SAW_LIMIT13: .db $97,$AD,$C2,$D4,$E3,$EF,$F8,$FD,$FF,$FE,$FB,$F6,$F0,$EA,$E4,$DF,$DB,$D8,$D7,$D6,$D7,$D9,$DB,$DD,$DF,$E1,$E1,$E1,$E0,$DF,$DC,$D9,$D6,$D3,$D0,$CE,$CC,$CB,$CA,$CA,$CB,$CC,$CC,$CD,$CE,$CE,$CD,$CC,$CB,$C9,$C7,$C5,$C2,$C0,$BE,$BD,$BB,$BB,$BB,$BB,$BB,$BB,$BC,$BC,$BC,$BB,$BA,$B9,$B7,$B5,$B3,$B1,$AF,$AE,$AC,$AB,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$A9,$A8,$A7,$A6,$A4,$A2,$A0,$9E,$9D,$9B,$9A,$9A,$99,$99,$99,$99,$99,$99,$99,$98,$97,$96,$94,$93,$91,$8F,$8D,$8C,$8A,$89,$89,$88,$88,$88,$88,$88,$88,$87,$87,$86,$84,$83,$81,$80,$7E,$7C,$7B,$79,$78,$78,$77,$77,$77,$77,$77,$77,$76,$76,$75,$73,$72,$70,$6E,$6C,$6B,$69,$68,$67,$66,$66,$66,$66,$66,$66,$66,$65,$65,$64,$62,$61,$5F,$5D,$5B,$59,$58,$57,$56,$55,$55,$55,$55,$55,$55,$55,$55,$54,$53,$51,$50,$4E,$4C,$4A,$48,$46,$45,$44,$43,$43,$43,$44,$44,$44,$44,$44,$44,$42,$41,$3F,$3D,$3A,$38,$36,$34,$33,$32,$31,$31,$32,$33,$33,$34,$35,$35,$34,$33,$31,$2F,$2C,$29,$26,$23,$20,$1F,$1E,$1E,$1E,$20,$22,$24,$26,$28,$29,$28,$27,$24,$20,$1B,$15,$0F,$09,$04,$01,$00,$02,$07,$10,$1C,$2B,$3D,$52,$68,$7F
SAW_LIMIT14: .db $92,$A4,$B5,$C4,$D3,$DF,$EA,$F2,$F8,$FD,$FF,$FF,$FE,$FB,$F7,$F3,$EE,$E9,$E4,$DF,$DB,$D8,$D5,$D4,$D3,$D3,$D3,$D4,$D6,$D7,$D9,$DA,$DB,$DC,$DC,$DC,$DB,$DA,$D8,$D6,$D3,$D0,$CE,$CB,$C8,$C6,$C4,$C3,$C2,$C1,$C1,$C1,$C1,$C2,$C2,$C3,$C3,$C3,$C3,$C3,$C2,$C1,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AF,$AE,$AD,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AB,$AA,$A9,$A7,$A6,$A4,$A2,$A0,$9E,$9C,$9B,$99,$98,$97,$97,$96,$96,$96,$96,$96,$96,$96,$96,$95,$95,$94,$93,$91,$90,$8E,$8C,$8A,$89,$87,$85,$84,$82,$81,$81,$80,$80,$80,$80,$80,$7F,$7F,$7F,$7F,$7E,$7E,$7D,$7B,$7A,$78,$76,$75,$73,$71,$6F,$6E,$6C,$6B,$6A,$6A,$69,$69,$69,$69,$69,$69,$69,$69,$68,$68,$67,$66,$64,$63,$61,$5F,$5D,$5B,$59,$58,$56,$55,$54,$53,$53,$53,$53,$53,$53,$53,$53,$53,$53,$52,$51,$50,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3E,$3D,$3C,$3C,$3C,$3C,$3C,$3D,$3D,$3E,$3E,$3E,$3E,$3D,$3C,$3B,$39,$37,$34,$31,$2F,$2C,$29,$27,$25,$24,$23,$23,$23,$24,$25,$26,$28,$29,$2B,$2C,$2C,$2C,$2B,$2A,$27,$24,$20,$1B,$16,$11,$0C,$08,$04,$01,$00,$00,$02,$07,$0D,$15,$20,$2C,$3B,$4A,$5B,$6D,$7F
SAW_LIMIT15: .db $8E,$9D,$AB,$B9,$C6,$D1,$DC,$E5,$ED,$F3,$F8,$FC,$FE,$FF,$FF,$FD,$FB,$F8,$F4,$F0,$EC,$E8,$E3,$DF,$DB,$D8,$D5,$D2,$D1,$CF,$CF,$CE,$CF,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D6,$D6,$D6,$D5,$D4,$D3,$D1,$CF,$CD,$CB,$C8,$C6,$C3,$C1,$BF,$BD,$BB,$BA,$B9,$B8,$B7,$B7,$B7,$B7,$B7,$B7,$B8,$B8,$B8,$B8,$B8,$B8,$B7,$B7,$B6,$B4,$B3,$B1,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A1,$9F,$9E,$9D,$9D,$9C,$9C,$9C,$9B,$9C,$9C,$9C,$9C,$9C,$9B,$9B,$9A,$9A,$99,$98,$96,$95,$93,$91,$8F,$8E,$8C,$8A,$88,$86,$85,$84,$83,$82,$81,$80,$80,$80,$80,$80,$80,$7F,$7F,$7F,$7F,$7F,$7E,$7D,$7C,$7B,$7A,$79,$77,$75,$73,$71,$70,$6E,$6C,$6A,$69,$67,$66,$65,$65,$64,$64,$63,$63,$63,$63,$63,$64,$63,$63,$63,$62,$62,$61,$60,$5E,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4E,$4C,$4B,$49,$48,$48,$47,$47,$47,$47,$47,$47,$48,$48,$48,$48,$48,$48,$47,$46,$45,$44,$42,$40,$3E,$3C,$39,$37,$34,$32,$30,$2E,$2C,$2B,$2A,$29,$29,$29,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$30,$31,$30,$30,$2E,$2D,$2A,$27,$24,$20,$1C,$17,$13,$0F,$0B,$07,$04,$02,$00,$00,$01,$03,$07,$0C,$12,$1A,$23,$2E,$39,$46,$54,$62,$71,$7F 

; Inverse sawtooth wavetables
INV_SAW0: .db $7F,$08,$01,$00,$00,$01,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$48,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$61,$62,$63,$64,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9B,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FE,$FF,$FF,$FE,$F7
INV_SAW1: .db $7F,$09,$00,$00,$02,$03,$05,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1B,$1C,$1C,$1D,$1E,$20,$21,$22,$22,$23,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DC,$DD,$DD,$DE,$DF,$E1,$E2,$E3,$E3,$E4,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FA,$FC,$FD,$FF,$FF,$F6
INV_SAW2: .db $7F,$08,$00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,$F0,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF,$F7
INV_SAW3: .db $7F,$08,$00,$00,$03,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,$20,$22,$22,$24,$24,$26,$26,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D9,$D9,$DB,$DB,$DD,$DD,$DF,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FC,$FF,$FF,$F7
INV_SAW4: .db $7F,$0A,$00,$04,$02,$07,$04,$08,$08,$08,$0B,$0A,$0C,$0C,$0E,$0F,$0F,$11,$11,$13,$14,$15,$16,$16,$18,$19,$1A,$1B,$1B,$1D,$1E,$1F,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5A,$5C,$5D,$5E,$5F,$5F,$61,$62,$63,$64,$64,$66,$66,$68,$69,$6A,$6B,$6B,$6D,$6E,$6F,$70,$70,$72,$72,$74,$75,$75,$77,$77,$79,$79,$7A,$7C,$7C,$7E,$7E,$7F,$81,$81,$83,$83,$85,$86,$86,$88,$88,$8A,$8A,$8B,$8D,$8D,$8F,$8F,$90,$91,$92,$94,$94,$95,$96,$97,$99,$99,$9B,$9B,$9C,$9D,$9E,$A0,$A0,$A1,$A2,$A3,$A5,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$E0,$E1,$E2,$E4,$E4,$E5,$E6,$E7,$E9,$E9,$EA,$EB,$EC,$EE,$EE,$F0,$F0,$F1,$F3,$F3,$F5,$F4,$F7,$F7,$F7,$FB,$F8,$FD,$FB,$FF,$F5
INV_SAW5: .db $7F,$16,$00,$0E,$0A,$08,$0F,$0D,$0C,$11,$10,$0F,$13,$13,$13,$16,$16,$16,$18,$19,$19,$1B,$1C,$1C,$1E,$1F,$1E,$20,$22,$21,$23,$24,$24,$26,$27,$27,$29,$2A,$2A,$2B,$2D,$2D,$2E,$30,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$39,$3B,$3B,$3C,$3E,$3E,$3F,$40,$41,$42,$43,$44,$45,$46,$47,$47,$49,$4A,$4A,$4C,$4D,$4D,$4E,$50,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5B,$5C,$5E,$5E,$5F,$61,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6D,$6F,$70,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7E,$7F,$81,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$8F,$90,$92,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9E,$A0,$A1,$A1,$A3,$A4,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$AF,$B1,$B2,$B2,$B3,$B5,$B5,$B6,$B8,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1,$C1,$C3,$C4,$C4,$C6,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$CF,$D1,$D2,$D2,$D4,$D5,$D5,$D6,$D8,$D8,$D9,$DB,$DB,$DC,$DE,$DD,$DF,$E1,$E0,$E1,$E3,$E3,$E4,$E6,$E6,$E7,$E9,$E9,$E9,$EC,$EC,$EC,$F0,$EF,$EE,$F3,$F2,$F0,$F7,$F5,$F1,$FF,$E9
INV_SAW6: .db $7F,$23,$00,$0C,$16,$0F,$0C,$12,$16,$12,$11,$16,$18,$15,$16,$1A,$1B,$19,$1A,$1E,$1E,$1D,$1F,$21,$21,$21,$23,$25,$24,$24,$27,$28,$28,$28,$2A,$2C,$2B,$2C,$2E,$2F,$2F,$30,$32,$32,$32,$34,$35,$36,$36,$37,$39,$39,$3A,$3B,$3D,$3D,$3D,$3F,$40,$40,$41,$43,$44,$44,$45,$47,$47,$48,$49,$4A,$4B,$4B,$4C,$4E,$4E,$4F,$50,$52,$52,$52,$54,$55,$55,$56,$58,$59,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$60,$61,$63,$63,$64,$65,$66,$67,$67,$69,$6A,$6B,$6B,$6C,$6E,$6E,$6F,$70,$71,$72,$72,$74,$75,$75,$76,$78,$78,$79,$7A,$7B,$7C,$7C,$7E,$7F,$80,$80,$81,$83,$83,$84,$85,$86,$87,$87,$89,$8A,$8A,$8B,$8D,$8D,$8E,$8F,$90,$91,$91,$93,$94,$94,$95,$96,$98,$98,$99,$9A,$9B,$9C,$9C,$9E,$9F,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A6,$A7,$A9,$AA,$AA,$AB,$AD,$AD,$AD,$AF,$B0,$B1,$B1,$B3,$B4,$B4,$B5,$B6,$B7,$B8,$B8,$BA,$BB,$BB,$BC,$BE,$BF,$BF,$C0,$C2,$C2,$C2,$C4,$C5,$C6,$C6,$C8,$C9,$C9,$CA,$CB,$CD,$CD,$CD,$CF,$D0,$D0,$D1,$D3,$D4,$D3,$D5,$D7,$D7,$D7,$D8,$DB,$DB,$DA,$DC,$DE,$DE,$DE,$E0,$E2,$E1,$E1,$E5,$E6,$E4,$E5,$E9,$EA,$E7,$E9,$EE,$ED,$E9,$ED,$F3,$F0,$E9,$F3,$FF,$DC
INV_SAW7: .db $7F,$2F,$03,$00,$10,$18,$12,$0C,$0E,$15,$18,$15,$12,$14,$19,$1B,$19,$17,$1A,$1E,$1F,$1D,$1D,$1F,$22,$23,$21,$22,$24,$26,$27,$26,$26,$29,$2B,$2B,$2A,$2B,$2E,$2F,$2F,$2F,$30,$32,$34,$34,$34,$35,$37,$38,$38,$38,$3A,$3C,$3D,$3D,$3D,$3E,$40,$41,$41,$41,$43,$45,$46,$46,$46,$48,$49,$4A,$4A,$4B,$4C,$4E,$4E,$4F,$4F,$51,$52,$53,$53,$54,$56,$57,$57,$58,$59,$5A,$5C,$5C,$5C,$5D,$5F,$60,$60,$61,$62,$64,$65,$65,$65,$67,$68,$69,$69,$6A,$6B,$6D,$6E,$6E,$6F,$70,$71,$72,$72,$73,$75,$76,$77,$77,$78,$79,$7B,$7B,$7B,$7C,$7E,$7F,$7F,$80,$81,$83,$84,$84,$84,$86,$87,$88,$88,$89,$8A,$8C,$8D,$8D,$8E,$8F,$90,$91,$91,$92,$94,$95,$96,$96,$97,$98,$9A,$9A,$9A,$9B,$9D,$9E,$9F,$9F,$A0,$A2,$A3,$A3,$A3,$A5,$A6,$A7,$A8,$A8,$A9,$AB,$AC,$AC,$AD,$AE,$B0,$B0,$B1,$B1,$B3,$B4,$B5,$B5,$B6,$B7,$B9,$B9,$B9,$BA,$BC,$BE,$BE,$BE,$BF,$C1,$C2,$C2,$C2,$C3,$C5,$C7,$C7,$C7,$C8,$CA,$CB,$CB,$CB,$CD,$CF,$D0,$D0,$D0,$D1,$D4,$D5,$D4,$D4,$D6,$D9,$D9,$D8,$D9,$DB,$DD,$DE,$DC,$DD,$E0,$E2,$E2,$E0,$E1,$E5,$E8,$E6,$E4,$E6,$EB,$ED,$EA,$E7,$EA,$F1,$F3,$ED,$E7,$EF,$FF,$FC,$D0
INV_SAW8: .db $7F,$3E,$11,$00,$06,$14,$1C,$1B,$14,$10,$12,$18,$1D,$1E,$1A,$18,$19,$1D,$21,$22,$20,$1E,$1F,$22,$25,$27,$26,$24,$25,$27,$2A,$2C,$2B,$2A,$2A,$2C,$2F,$31,$31,$30,$30,$31,$34,$36,$36,$36,$36,$37,$39,$3B,$3B,$3B,$3B,$3C,$3E,$40,$41,$41,$41,$41,$43,$45,$46,$46,$46,$47,$48,$4A,$4B,$4C,$4C,$4C,$4D,$4F,$51,$51,$51,$51,$53,$54,$56,$56,$57,$57,$58,$5A,$5B,$5C,$5C,$5C,$5D,$5F,$60,$61,$61,$62,$62,$64,$66,$67,$67,$67,$68,$69,$6B,$6C,$6C,$6C,$6D,$6E,$70,$71,$72,$72,$72,$74,$75,$76,$77,$77,$78,$79,$7A,$7C,$7D,$7D,$7D,$7E,$7F,$81,$82,$82,$82,$83,$85,$86,$87,$88,$88,$89,$8A,$8B,$8D,$8D,$8D,$8E,$8F,$91,$92,$93,$93,$93,$94,$96,$97,$98,$98,$98,$99,$9B,$9D,$9D,$9E,$9E,$9F,$A0,$A2,$A3,$A3,$A3,$A4,$A5,$A7,$A8,$A8,$A9,$A9,$AB,$AC,$AE,$AE,$AE,$AE,$B0,$B2,$B3,$B3,$B3,$B4,$B5,$B7,$B8,$B9,$B9,$B9,$BA,$BC,$BE,$BE,$BE,$BE,$BF,$C1,$C3,$C4,$C4,$C4,$C4,$C6,$C8,$C9,$C9,$C9,$C9,$CB,$CE,$CF,$CF,$CE,$CE,$D0,$D3,$D5,$D5,$D4,$D3,$D5,$D8,$DA,$DB,$D9,$D8,$DA,$DD,$E0,$E1,$DF,$DD,$DE,$E2,$E6,$E7,$E5,$E1,$E2,$E7,$ED,$EF,$EB,$E4,$E3,$EB,$F9,$FF,$EE,$C1
INV_SAW9: .db $7F,$49,$1E,$06,$00,$08,$14,$1D,$1F,$1B,$16,$12,$13,$18,$1D,$21,$21,$1F,$1C,$1B,$1D,$21,$24,$26,$26,$24,$23,$23,$26,$29,$2B,$2C,$2C,$2B,$2A,$2B,$2E,$30,$32,$33,$32,$31,$32,$33,$35,$38,$39,$39,$39,$38,$39,$3B,$3D,$3F,$40,$40,$3F,$3F,$40,$42,$44,$46,$46,$46,$46,$47,$48,$4A,$4C,$4D,$4D,$4D,$4D,$4E,$4F,$51,$53,$54,$54,$54,$54,$55,$57,$59,$5A,$5A,$5A,$5B,$5B,$5C,$5E,$60,$61,$61,$61,$61,$62,$64,$65,$67,$68,$68,$68,$68,$6A,$6B,$6D,$6E,$6F,$6F,$6F,$70,$71,$72,$74,$75,$75,$75,$76,$77,$78,$7A,$7B,$7C,$7C,$7C,$7D,$7E,$7F,$81,$82,$83,$83,$83,$84,$85,$87,$88,$89,$8A,$8A,$8A,$8B,$8D,$8E,$8F,$90,$90,$90,$91,$92,$94,$95,$97,$97,$97,$97,$98,$9A,$9B,$9D,$9E,$9E,$9E,$9E,$9F,$A1,$A3,$A4,$A4,$A5,$A5,$A5,$A6,$A8,$AA,$AB,$AB,$AB,$AB,$AC,$AE,$B0,$B1,$B2,$B2,$B2,$B2,$B3,$B5,$B7,$B8,$B9,$B9,$B9,$B9,$BB,$BD,$BF,$C0,$C0,$BF,$BF,$C0,$C2,$C4,$C6,$C7,$C6,$C6,$C6,$C7,$CA,$CC,$CD,$CE,$CD,$CC,$CD,$CF,$D1,$D4,$D5,$D4,$D3,$D3,$D4,$D6,$D9,$DC,$DC,$DB,$D9,$D9,$DB,$DE,$E2,$E4,$E3,$E0,$DE,$DE,$E2,$E7,$EC,$ED,$E9,$E4,$E0,$E2,$EB,$F7,$FF,$F9,$E1,$B6
INV_SAW10:.db $7F,$54,$2E,$12,$03,$00,$06,$0F,$19,$20,$21,$1F,$1B,$16,$14,$15,$18,$1D,$22,$25,$25,$24,$21,$20,$1F,$21,$24,$27,$2A,$2C,$2C,$2B,$2A,$29,$29,$2B,$2E,$30,$33,$34,$34,$33,$32,$32,$33,$35,$37,$39,$3B,$3C,$3C,$3B,$3B,$3B,$3C,$3E,$40,$42,$44,$44,$44,$44,$44,$44,$46,$48,$4A,$4B,$4C,$4D,$4C,$4C,$4D,$4D,$4F,$51,$53,$54,$55,$55,$55,$55,$55,$57,$58,$5A,$5C,$5D,$5D,$5D,$5D,$5E,$5E,$60,$61,$63,$65,$65,$66,$66,$66,$66,$67,$69,$6A,$6C,$6D,$6E,$6E,$6E,$6F,$6F,$70,$72,$74,$75,$76,$77,$77,$77,$77,$78,$79,$7B,$7D,$7E,$7F,$7F,$7F,$80,$80,$81,$82,$84,$86,$87,$88,$88,$88,$88,$89,$8A,$8B,$8D,$8F,$90,$90,$91,$91,$91,$92,$93,$95,$96,$98,$99,$99,$99,$99,$9A,$9A,$9C,$9E,$9F,$A1,$A1,$A2,$A2,$A2,$A2,$A3,$A5,$A7,$A8,$AA,$AA,$AA,$AA,$AA,$AB,$AC,$AE,$B0,$B2,$B2,$B3,$B3,$B2,$B3,$B4,$B5,$B7,$B9,$BB,$BB,$BB,$BB,$BB,$BB,$BD,$BF,$C1,$C3,$C4,$C4,$C4,$C3,$C3,$C4,$C6,$C8,$CA,$CC,$CD,$CD,$CC,$CB,$CB,$CC,$CF,$D1,$D4,$D6,$D6,$D5,$D4,$D3,$D3,$D5,$D8,$DB,$DE,$E0,$DF,$DE,$DB,$DA,$DA,$DD,$E2,$E7,$EA,$EB,$E9,$E4,$E0,$DE,$DF,$E6,$F0,$F9,$FF,$FC,$ED,$D1,$AB
INV_SAW11:.db $7F,$5D,$3D,$23,$10,$04,$00,$02,$08,$10,$19,$1F,$23,$24,$22,$1F,$1C,$19,$17,$18,$1A,$1D,$21,$25,$28,$2A,$2A,$29,$27,$26,$25,$25,$26,$28,$2B,$2E,$31,$33,$33,$33,$33,$32,$31,$31,$32,$33,$35,$38,$3A,$3C,$3D,$3E,$3E,$3D,$3D,$3D,$3D,$3E,$40,$42,$44,$46,$47,$48,$49,$48,$48,$48,$48,$49,$4A,$4C,$4E,$50,$52,$53,$53,$53,$53,$53,$53,$54,$55,$56,$58,$5A,$5C,$5D,$5E,$5E,$5E,$5E,$5E,$5F,$60,$61,$62,$64,$66,$67,$68,$69,$69,$69,$69,$6A,$6A,$6B,$6D,$6E,$70,$72,$73,$74,$74,$74,$74,$75,$75,$76,$77,$79,$7A,$7C,$7D,$7F,$7F,$7F,$80,$80,$80,$80,$82,$83,$85,$86,$88,$89,$8A,$8A,$8B,$8B,$8B,$8B,$8C,$8D,$8F,$91,$92,$94,$95,$95,$96,$96,$96,$96,$97,$98,$99,$9B,$9D,$9E,$9F,$A0,$A1,$A1,$A1,$A1,$A1,$A2,$A3,$A5,$A7,$A9,$AA,$AB,$AC,$AC,$AC,$AC,$AC,$AC,$AD,$AF,$B1,$B3,$B5,$B6,$B7,$B7,$B7,$B7,$B6,$B7,$B8,$B9,$BB,$BD,$BF,$C1,$C2,$C2,$C2,$C2,$C1,$C1,$C2,$C3,$C5,$C7,$CA,$CC,$CD,$CE,$CE,$CD,$CC,$CC,$CC,$CC,$CE,$D1,$D4,$D7,$D9,$DA,$DA,$D9,$D8,$D6,$D5,$D5,$D7,$DA,$DE,$E2,$E5,$E7,$E8,$E6,$E3,$E0,$DD,$DB,$DC,$E0,$E6,$EF,$F7,$FD,$FF,$FB,$EF,$DC,$C2,$A2
INV_SAW12:.db $7F,$63,$49,$31,$1D,$0F,$05,$00,$00,$03,$09,$10,$17,$1D,$22,$25,$26,$25,$23,$20,$1E,$1B,$1A,$1A,$1B,$1D,$21,$24,$28,$2B,$2D,$2E,$2F,$2E,$2E,$2C,$2B,$2B,$2A,$2B,$2D,$2F,$31,$34,$36,$38,$3A,$3B,$3B,$3B,$3A,$3A,$39,$39,$3A,$3B,$3C,$3E,$40,$43,$45,$46,$48,$48,$48,$48,$48,$48,$48,$48,$49,$4A,$4C,$4D,$4F,$51,$53,$54,$55,$56,$56,$56,$56,$56,$56,$57,$57,$59,$5A,$5C,$5E,$60,$61,$63,$63,$64,$64,$64,$64,$64,$64,$65,$66,$68,$69,$6B,$6D,$6E,$70,$71,$71,$72,$72,$72,$72,$72,$73,$74,$75,$76,$78,$7A,$7C,$7D,$7E,$7F,$7F,$7F,$80,$80,$80,$80,$81,$82,$83,$85,$87,$89,$8A,$8B,$8C,$8D,$8D,$8D,$8D,$8D,$8E,$8E,$8F,$91,$92,$94,$96,$97,$99,$9A,$9B,$9B,$9B,$9B,$9B,$9B,$9C,$9C,$9E,$9F,$A1,$A3,$A5,$A6,$A8,$A8,$A9,$A9,$A9,$A9,$A9,$A9,$AA,$AB,$AC,$AE,$B0,$B2,$B3,$B5,$B6,$B7,$B7,$B7,$B7,$B7,$B7,$B7,$B7,$B9,$BA,$BC,$BF,$C1,$C3,$C4,$C5,$C6,$C6,$C5,$C5,$C4,$C4,$C4,$C5,$C7,$C9,$CB,$CE,$D0,$D2,$D4,$D5,$D4,$D4,$D3,$D1,$D1,$D0,$D1,$D2,$D4,$D7,$DB,$DE,$E2,$E4,$E5,$E5,$E4,$E1,$DF,$DC,$DA,$D9,$DA,$DD,$E2,$E8,$EF,$F6,$FC,$FF,$FF,$FA,$F0,$E2,$CE,$B6,$9C
INV_SAW13:.db $7F,$68,$52,$3D,$2B,$1C,$10,$07,$02,$00,$01,$04,$09,$0F,$15,$1B,$20,$24,$27,$28,$29,$28,$26,$24,$22,$20,$1E,$1E,$1E,$1F,$20,$23,$26,$29,$2C,$2F,$31,$33,$34,$35,$35,$34,$33,$33,$32,$31,$31,$32,$33,$34,$36,$38,$3A,$3D,$3F,$41,$42,$44,$44,$44,$44,$44,$44,$43,$43,$43,$44,$45,$46,$48,$4A,$4C,$4E,$50,$51,$53,$54,$55,$55,$55,$55,$55,$55,$55,$55,$56,$57,$58,$59,$5B,$5D,$5F,$61,$62,$64,$65,$65,$66,$66,$66,$66,$66,$66,$66,$67,$68,$69,$6B,$6C,$6E,$70,$72,$73,$75,$76,$76,$77,$77,$77,$77,$77,$77,$78,$78,$79,$7B,$7C,$7E,$80,$81,$83,$84,$86,$87,$87,$88,$88,$88,$88,$88,$88,$89,$89,$8A,$8C,$8D,$8F,$91,$93,$94,$96,$97,$98,$99,$99,$99,$99,$99,$99,$99,$9A,$9A,$9B,$9D,$9E,$A0,$A2,$A4,$A6,$A7,$A8,$A9,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AB,$AC,$AE,$AF,$B1,$B3,$B5,$B7,$B9,$BA,$BB,$BC,$BC,$BC,$BB,$BB,$BB,$BB,$BB,$BB,$BD,$BE,$C0,$C2,$C5,$C7,$C9,$CB,$CC,$CD,$CE,$CE,$CD,$CC,$CC,$CB,$CA,$CA,$CB,$CC,$CE,$D0,$D3,$D6,$D9,$DC,$DF,$E0,$E1,$E1,$E1,$DF,$DD,$DB,$D9,$D7,$D6,$D7,$D8,$DB,$DF,$E4,$EA,$F0,$F6,$FB,$FE,$FF,$FD,$F8,$EF,$E3,$D4,$C2,$AD,$97
INV_SAW14:.db $7F,$6D,$5B,$4A,$3B,$2C,$20,$15,$0D,$07,$02,$00,$00,$01,$04,$08,$0C,$11,$16,$1B,$20,$24,$27,$2A,$2B,$2C,$2C,$2C,$2B,$29,$28,$26,$25,$24,$23,$23,$23,$24,$25,$27,$29,$2C,$2F,$31,$34,$37,$39,$3B,$3C,$3D,$3E,$3E,$3E,$3E,$3D,$3D,$3C,$3C,$3C,$3C,$3C,$3D,$3E,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$50,$51,$52,$53,$53,$53,$53,$53,$53,$53,$53,$53,$53,$54,$55,$56,$58,$59,$5B,$5D,$5F,$61,$63,$64,$66,$67,$68,$68,$69,$69,$69,$69,$69,$69,$69,$69,$6A,$6A,$6B,$6C,$6E,$6F,$71,$73,$75,$76,$78,$7A,$7B,$7D,$7E,$7E,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80,$81,$81,$82,$84,$85,$87,$89,$8A,$8C,$8E,$90,$91,$93,$94,$95,$95,$96,$96,$96,$96,$96,$96,$96,$96,$97,$97,$98,$99,$9B,$9C,$9E,$A0,$A2,$A4,$A6,$A7,$A9,$AA,$AB,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AD,$AE,$AF,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C1,$C2,$C3,$C3,$C3,$C3,$C3,$C2,$C2,$C1,$C1,$C1,$C1,$C2,$C3,$C4,$C6,$C8,$CB,$CE,$D0,$D3,$D6,$D8,$DA,$DB,$DC,$DC,$DC,$DB,$DA,$D9,$D7,$D6,$D4,$D3,$D3,$D3,$D4,$D5,$D8,$DB,$DF,$E4,$E9,$EE,$F3,$F7,$FB,$FE,$FF,$FF,$FD,$F8,$F2,$EA,$DF,$D3,$C4,$B5,$A4,$92
INV_SAW15:.db $7F,$71,$62,$54,$46,$39,$2E,$23,$1A,$12,$0C,$07,$03,$01,$00,$00,$02,$04,$07,$0B,$0F,$13,$17,$1C,$20,$24,$27,$2A,$2D,$2E,$30,$30,$31,$30,$30,$2F,$2E,$2D,$2C,$2B,$2A,$29,$29,$29,$29,$2A,$2B,$2C,$2E,$30,$32,$34,$37,$39,$3C,$3E,$40,$42,$44,$45,$46,$47,$48,$48,$48,$48,$48,$48,$47,$47,$47,$47,$47,$47,$48,$48,$49,$4B,$4C,$4E,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5E,$60,$61,$62,$62,$63,$63,$63,$64,$63,$63,$63,$63,$63,$64,$64,$65,$65,$66,$67,$69,$6A,$6C,$6E,$70,$71,$73,$75,$77,$79,$7A,$7B,$7C,$7D,$7E,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80,$80,$81,$82,$83,$84,$85,$86,$88,$8A,$8C,$8E,$8F,$91,$93,$95,$96,$98,$99,$9A,$9A,$9B,$9B,$9C,$9C,$9C,$9C,$9C,$9B,$9C,$9C,$9C,$9D,$9D,$9E,$9F,$A1,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B1,$B3,$B4,$B6,$B7,$B7,$B8,$B8,$B8,$B8,$B8,$B8,$B7,$B7,$B7,$B7,$B7,$B7,$B8,$B9,$BA,$BB,$BD,$BF,$C1,$C3,$C6,$C8,$CB,$CD,$CF,$D1,$D3,$D4,$D5,$D6,$D6,$D6,$D6,$D5,$D4,$D3,$D2,$D1,$D0,$CF,$CF,$CE,$CF,$CF,$D1,$D2,$D5,$D8,$DB,$DF,$E3,$E8,$EC,$F0,$F4,$F8,$FB,$FD,$FF,$FF,$FE,$FC,$F8,$F3,$ED,$E5,$DC,$D1,$C6,$B9,$AB,$9D,$8E


;*** Bandlimited square wavetables
SQ_LIMIT0: .db $F2,$FB,$FC,$FD,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FD,$FC,$FB,$F2,$80,$0D,$04,$03,$02,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$02,$03,$04,$0D,$7F
SQ_LIMIT1: .db $F4,$FE,$FF,$FE,$FE,$FD,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FD,$FE,$FE,$FF,$FE,$F4,$80,$0B,$01,$00,$01,$01,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$01,$01,$00,$01,$0B,$7F
SQ_LIMIT2: .db $F6,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F6,$80,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$7F
SQ_LIMIT3: .db $F6,$FE,$FF,$FE,$FF,$FE,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FE,$FF,$FE,$FF,$FE,$F6,$80,$09,$01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$00,$01,$09,$7F
SQ_LIMIT4: .db $F4,$FF,$FC,$FF,$FB,$FE,$FC,$FD,$FD,$FC,$FE,$FC,$FE,$FD,$FD,$FE,$FD,$FE,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FE,$FD,$FE,$FD,$FD,$FE,$FC,$FE,$FC,$FD,$FD,$FC,$FE,$FB,$FF,$FC,$FF,$F4,$80,$0B,$00,$03,$00,$04,$01,$03,$02,$02,$03,$01,$03,$01,$02,$02,$01,$02,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$02,$01,$02,$02,$01,$03,$01,$03,$02,$02,$03,$01,$04,$00,$03,$00,$0B,$7F
SQ_LIMIT5: .db $E9,$FF,$F2,$F7,$FA,$F4,$F7,$F9,$F5,$F7,$F8,$F5,$F7,$F8,$F6,$F7,$F8,$F6,$F7,$F8,$F6,$F7,$F8,$F6,$F7,$F8,$F6,$F7,$F7,$F6,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F7,$F7,$F6,$F6,$F7,$F7,$F6,$F8,$F7,$F6,$F8,$F7,$F6,$F8,$F7,$F6,$F8,$F7,$F6,$F8,$F7,$F5,$F8,$F7,$F5,$F9,$F7,$F4,$FA,$F7,$F2,$FF,$E9,$80,$16,$00,$0D,$08,$05,$0B,$08,$06,$0A,$08,$07,$0A,$08,$07,$09,$08,$07,$09,$08,$07,$09,$08,$07,$09,$08,$07,$09,$08,$08,$09,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$08,$08,$09,$09,$08,$08,$09,$07,$08,$09,$07,$08,$09,$07,$08,$09,$07,$08,$09,$07,$08,$0A,$07,$08,$0A,$06,$08,$0B,$05,$08,$0D,$00,$16,$7F
SQ_LIMIT6: .db $DB,$FF,$F5,$EB,$F3,$F7,$F2,$EF,$F3,$F5,$F1,$F0,$F4,$F4,$F1,$F1,$F4,$F4,$F1,$F1,$F4,$F3,$F1,$F2,$F4,$F3,$F1,$F2,$F3,$F3,$F1,$F2,$F3,$F2,$F1,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F2,$F2,$F2,$F3,$F2,$F2,$F2,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F2,$F2,$F3,$F3,$F1,$F2,$F3,$F2,$F1,$F3,$F3,$F2,$F1,$F3,$F4,$F2,$F1,$F3,$F4,$F1,$F1,$F4,$F4,$F1,$F1,$F4,$F4,$F0,$F1,$F5,$F3,$EF,$F2,$F7,$F3,$EB,$F5,$FF,$DB,$80,$24,$00,$0A,$14,$0C,$08,$0D,$10,$0C,$0A,$0E,$0F,$0B,$0B,$0E,$0E,$0B,$0B,$0E,$0E,$0B,$0C,$0E,$0D,$0B,$0C,$0E,$0D,$0C,$0C,$0E,$0D,$0C,$0D,$0E,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0D,$0D,$0D,$0C,$0D,$0D,$0D,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0D,$0D,$0C,$0C,$0E,$0D,$0C,$0D,$0E,$0C,$0C,$0D,$0E,$0C,$0B,$0D,$0E,$0C,$0B,$0E,$0E,$0B,$0B,$0E,$0E,$0B,$0B,$0F,$0E,$0A,$0C,$10,$0D,$08,$0C,$14,$0A,$00,$24,$7F
SQ_LIMIT7: .db $CE,$FB,$FF,$F1,$E9,$EF,$F7,$F6,$F0,$ED,$F1,$F5,$F4,$F0,$EF,$F2,$F4,$F3,$F0,$F0,$F2,$F4,$F3,$F0,$F0,$F2,$F3,$F2,$F0,$F0,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F1,$F1,$F1,$F3,$F3,$F1,$F1,$F1,$F3,$F3,$F1,$F1,$F1,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F1,$F1,$F2,$F3,$F2,$F0,$F0,$F2,$F3,$F2,$F0,$F0,$F3,$F4,$F2,$F0,$F0,$F3,$F4,$F2,$EF,$F0,$F4,$F5,$F1,$ED,$F0,$F6,$F7,$EF,$E9,$F1,$FF,$FB,$CE,$80,$31,$04,$00,$0E,$16,$10,$08,$09,$0F,$12,$0E,$0A,$0B,$0F,$10,$0D,$0B,$0C,$0F,$0F,$0D,$0B,$0C,$0F,$0F,$0D,$0C,$0D,$0F,$0F,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0E,$0E,$0E,$0C,$0C,$0E,$0E,$0E,$0C,$0C,$0E,$0E,$0E,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0E,$0E,$0D,$0C,$0D,$0F,$0F,$0D,$0C,$0D,$0F,$0F,$0C,$0B,$0D,$0F,$0F,$0C,$0B,$0D,$10,$0F,$0B,$0A,$0E,$12,$0F,$09,$08,$10,$16,$0E,$00,$04,$31,$7F
SQ_LIMIT8: .db $C1,$EE,$FF,$F9,$EC,$E6,$E9,$F0,$F5,$F3,$ED,$EA,$EB,$EF,$F2,$F1,$EE,$EB,$EC,$EF,$F1,$F1,$EE,$EC,$EC,$EF,$F1,$F0,$EE,$ED,$ED,$EE,$F0,$F0,$EF,$ED,$ED,$EE,$F0,$F0,$EF,$ED,$ED,$EE,$F0,$F0,$EF,$ED,$ED,$EE,$EF,$F0,$EF,$EE,$ED,$EE,$EF,$F0,$EF,$EE,$ED,$EE,$EF,$F0,$EF,$EE,$ED,$EE,$EF,$F0,$EF,$EE,$ED,$EE,$EF,$F0,$EF,$EE,$ED,$ED,$EF,$F0,$F0,$EE,$ED,$ED,$EF,$F0,$F0,$EE,$ED,$ED,$EF,$F0,$F0,$EE,$ED,$ED,$EE,$F0,$F1,$EF,$EC,$EC,$EE,$F1,$F1,$EF,$EC,$EB,$EE,$F1,$F2,$EF,$EB,$EA,$ED,$F3,$F5,$F0,$E9,$E6,$EC,$F9,$FF,$EE,$C1,$80,$3E,$11,$00,$06,$13,$19,$16,$0F,$0A,$0C,$12,$15,$14,$10,$0D,$0E,$11,$14,$13,$10,$0E,$0E,$11,$13,$13,$10,$0E,$0F,$11,$12,$12,$11,$0F,$0F,$10,$12,$12,$11,$0F,$0F,$10,$12,$12,$11,$0F,$0F,$10,$12,$12,$11,$10,$0F,$10,$11,$12,$11,$10,$0F,$10,$11,$12,$11,$10,$0F,$10,$11,$12,$11,$10,$0F,$10,$11,$12,$11,$10,$0F,$10,$11,$12,$12,$10,$0F,$0F,$11,$12,$12,$10,$0F,$0F,$11,$12,$12,$10,$0F,$0F,$11,$12,$12,$11,$0F,$0E,$10,$13,$13,$11,$0E,$0E,$10,$13,$14,$11,$0E,$0D,$10,$14,$15,$12,$0C,$0A,$0F,$16,$19,$13,$06,$00,$11,$3E,$7F
SQ_LIMIT9: .db $B6,$E1,$F9,$FF,$F8,$ED,$E5,$E5,$EA,$F0,$F4,$F3,$EF,$EA,$E8,$EA,$ED,$F1,$F2,$F0,$ED,$EA,$EA,$EC,$EF,$F0,$F0,$EE,$EC,$EB,$EB,$ED,$EF,$F0,$EF,$ED,$EC,$EB,$EC,$EE,$F0,$EF,$EE,$EC,$EB,$EC,$ED,$EF,$EF,$EF,$ED,$EC,$EC,$ED,$EE,$EF,$EF,$EE,$ED,$EC,$EC,$ED,$EF,$EF,$EF,$ED,$EC,$EC,$ED,$EE,$EF,$EF,$EE,$ED,$EC,$EC,$ED,$EF,$EF,$EF,$ED,$EC,$EB,$EC,$EE,$EF,$F0,$EE,$EC,$EB,$EC,$ED,$EF,$F0,$EF,$ED,$EB,$EB,$EC,$EE,$F0,$F0,$EF,$EC,$EA,$EA,$ED,$F0,$F2,$F1,$ED,$EA,$E8,$EA,$EF,$F3,$F4,$F0,$EA,$E5,$E5,$ED,$F8,$FF,$F9,$E1,$B6,$80,$49,$1E,$06,$00,$07,$12,$1A,$1A,$15,$0F,$0B,$0C,$10,$15,$17,$15,$12,$0E,$0D,$0F,$12,$15,$15,$13,$10,$0F,$0F,$11,$13,$14,$14,$12,$10,$0F,$10,$12,$13,$14,$13,$11,$0F,$10,$11,$13,$14,$13,$12,$10,$10,$10,$12,$13,$13,$12,$11,$10,$10,$11,$12,$13,$13,$12,$10,$10,$10,$12,$13,$13,$12,$11,$10,$10,$11,$12,$13,$13,$12,$10,$10,$10,$12,$13,$14,$13,$11,$10,$0F,$11,$13,$14,$13,$12,$10,$0F,$10,$12,$14,$14,$13,$11,$0F,$0F,$10,$13,$15,$15,$12,$0F,$0D,$0E,$12,$15,$17,$15,$10,$0C,$0B,$0F,$15,$1A,$1A,$12,$07,$00,$06,$1E,$49,$7F
SQ_LIMIT10: .db $AA,$CF,$EB,$FA,$FF,$FB,$F3,$EA,$E4,$E3,$E5,$EA,$EF,$F3,$F3,$F2,$EE,$EA,$E8,$E7,$E9,$EC,$EF,$F1,$F1,$EF,$ED,$EB,$E9,$E9,$EA,$EC,$EF,$F0,$F0,$EE,$ED,$EB,$EA,$EA,$EB,$ED,$EE,$EF,$EF,$EE,$EC,$EB,$EA,$EA,$EB,$ED,$EE,$EF,$EF,$EE,$EC,$EB,$EA,$EA,$EC,$ED,$EF,$EF,$EF,$ED,$EC,$EA,$EA,$EB,$EC,$EE,$EF,$EF,$EE,$ED,$EB,$EA,$EA,$EB,$EC,$EE,$EF,$EF,$EE,$ED,$EB,$EA,$EA,$EB,$ED,$EE,$F0,$F0,$EF,$EC,$EA,$E9,$E9,$EB,$ED,$EF,$F1,$F1,$EF,$EC,$E9,$E7,$E8,$EA,$EE,$F2,$F3,$F3,$EF,$EA,$E5,$E3,$E4,$EA,$F3,$FB,$FF,$FA,$EB,$CF,$AA,$80,$55,$30,$14,$05,$00,$04,$0C,$15,$1B,$1C,$1A,$15,$10,$0C,$0C,$0D,$11,$15,$17,$18,$16,$13,$10,$0E,$0E,$10,$12,$14,$16,$16,$15,$13,$10,$0F,$0F,$11,$12,$14,$15,$15,$14,$12,$11,$10,$10,$11,$13,$14,$15,$15,$14,$12,$11,$10,$10,$11,$13,$14,$15,$15,$13,$12,$10,$10,$10,$12,$13,$15,$15,$14,$13,$11,$10,$10,$11,$12,$14,$15,$15,$14,$13,$11,$10,$10,$11,$12,$14,$15,$15,$14,$12,$11,$0F,$0F,$10,$13,$15,$16,$16,$14,$12,$10,$0E,$0E,$10,$13,$16,$18,$17,$15,$11,$0D,$0C,$0C,$10,$15,$1A,$1C,$1B,$15,$0C,$04,$00,$05,$14,$30,$55,$7F
SQ_LIMIT11: .db $A1,$BF,$D9,$ED,$F9,$FF,$FF,$FA,$F4,$ED,$E7,$E3,$E2,$E4,$E7,$EC,$F0,$F3,$F4,$F3,$F1,$EE,$EB,$E9,$E7,$E7,$E8,$EA,$ED,$EF,$F1,$F1,$F1,$EF,$ED,$EB,$E9,$E9,$E9,$EA,$EB,$ED,$EF,$F0,$F0,$F0,$EE,$ED,$EB,$EA,$E9,$E9,$EA,$EC,$EE,$EF,$F0,$F0,$EF,$EE,$EC,$EB,$EA,$E9,$EA,$EB,$EC,$EE,$EF,$F0,$F0,$EF,$EE,$EC,$EA,$E9,$E9,$EA,$EB,$ED,$EE,$F0,$F0,$F0,$EF,$ED,$EB,$EA,$E9,$E9,$E9,$EB,$ED,$EF,$F1,$F1,$F1,$EF,$ED,$EA,$E8,$E7,$E7,$E9,$EB,$EE,$F1,$F3,$F4,$F3,$F0,$EC,$E7,$E4,$E2,$E3,$E7,$ED,$F4,$FA,$FF,$FF,$F9,$ED,$D9,$BF,$A1,$80,$5E,$40,$26,$12,$06,$00,$00,$05,$0B,$12,$18,$1C,$1D,$1B,$18,$13,$0F,$0C,$0B,$0C,$0E,$11,$14,$16,$18,$18,$17,$15,$12,$10,$0E,$0E,$0E,$10,$12,$14,$16,$16,$16,$15,$14,$12,$10,$0F,$0F,$0F,$11,$12,$14,$15,$16,$16,$15,$13,$11,$10,$0F,$0F,$10,$11,$13,$14,$15,$16,$15,$14,$13,$11,$10,$0F,$0F,$10,$11,$13,$15,$16,$16,$15,$14,$12,$11,$0F,$0F,$0F,$10,$12,$14,$15,$16,$16,$16,$14,$12,$10,$0E,$0E,$0E,$10,$12,$15,$17,$18,$18,$16,$14,$11,$0E,$0C,$0B,$0C,$0F,$13,$18,$1B,$1D,$1C,$18,$12,$0B,$05,$00,$00,$06,$12,$26,$40,$5E,$7F
SQ_LIMIT12: .db $9A,$B4,$CA,$DE,$ED,$F7,$FD,$FF,$FE,$FA,$F4,$EF,$E9,$E5,$E2,$E1,$E2,$E4,$E7,$EB,$EE,$F1,$F3,$F3,$F3,$F1,$EF,$EC,$EA,$E8,$E6,$E6,$E6,$E8,$E9,$EC,$EE,$EF,$F1,$F1,$F1,$EF,$EE,$EC,$EA,$E9,$E8,$E7,$E8,$E9,$EA,$EC,$ED,$EF,$F0,$F0,$F0,$EF,$EE,$EC,$EA,$E9,$E8,$E8,$E8,$E9,$EA,$EC,$EE,$EF,$F0,$F0,$F0,$EF,$ED,$EC,$EA,$E9,$E8,$E7,$E8,$E9,$EA,$EC,$EE,$EF,$F1,$F1,$F1,$EF,$EE,$EC,$E9,$E8,$E6,$E6,$E6,$E8,$EA,$EC,$EF,$F1,$F3,$F3,$F3,$F1,$EE,$EB,$E7,$E4,$E2,$E1,$E2,$E5,$E9,$EF,$F4,$FA,$FE,$FF,$FD,$F7,$ED,$DE,$CA,$B4,$9A,$80,$65,$4B,$35,$21,$12,$08,$02,$00,$01,$05,$0B,$10,$16,$1A,$1D,$1E,$1D,$1B,$18,$14,$11,$0E,$0C,$0C,$0C,$0E,$10,$13,$15,$17,$19,$19,$19,$17,$16,$13,$11,$10,$0E,$0E,$0E,$10,$11,$13,$15,$16,$17,$18,$17,$16,$15,$13,$12,$10,$0F,$0F,$0F,$10,$11,$13,$15,$16,$17,$17,$17,$16,$15,$13,$11,$10,$0F,$0F,$0F,$10,$12,$13,$15,$16,$17,$18,$17,$16,$15,$13,$11,$10,$0E,$0E,$0E,$10,$11,$13,$16,$17,$19,$19,$19,$17,$15,$13,$10,$0E,$0C,$0C,$0C,$0E,$11,$14,$18,$1B,$1D,$1E,$1D,$1A,$16,$10,$0B,$05,$01,$00,$02,$08,$12,$21,$35,$4B,$65,$7F
SQ_LIMIT13: .db $97,$AD,$C2,$D5,$E4,$F0,$F8,$FD,$FF,$FE,$FB,$F7,$F2,$ED,$E8,$E5,$E2,$E1,$E1,$E3,$E5,$E8,$EB,$EE,$F1,$F2,$F3,$F3,$F2,$F1,$EF,$EC,$EA,$E8,$E7,$E6,$E6,$E6,$E8,$E9,$EB,$ED,$EF,$F0,$F1,$F1,$F1,$F0,$EE,$EC,$EB,$E9,$E8,$E7,$E7,$E7,$E8,$E9,$EB,$ED,$EE,$EF,$F0,$F1,$F0,$EF,$EE,$ED,$EB,$E9,$E8,$E7,$E7,$E7,$E8,$E9,$EB,$EC,$EE,$F0,$F1,$F1,$F1,$F0,$EF,$ED,$EB,$E9,$E8,$E6,$E6,$E6,$E7,$E8,$EA,$EC,$EF,$F1,$F2,$F3,$F3,$F2,$F1,$EE,$EB,$E8,$E5,$E3,$E1,$E1,$E2,$E5,$E8,$ED,$F2,$F7,$FB,$FE,$FF,$FD,$F8,$F0,$E4,$D5,$C2,$AD,$97,$80,$68,$52,$3D,$2A,$1B,$0F,$07,$02,$00,$01,$04,$08,$0D,$12,$17,$1A,$1D,$1E,$1E,$1C,$1A,$17,$14,$11,$0E,$0D,$0C,$0C,$0D,$0E,$10,$13,$15,$17,$18,$19,$19,$19,$17,$16,$14,$12,$10,$0F,$0E,$0E,$0E,$0F,$11,$13,$14,$16,$17,$18,$18,$18,$17,$16,$14,$12,$11,$10,$0F,$0E,$0F,$10,$11,$12,$14,$16,$17,$18,$18,$18,$17,$16,$14,$13,$11,$0F,$0E,$0E,$0E,$0F,$10,$12,$14,$16,$17,$19,$19,$19,$18,$17,$15,$13,$10,$0E,$0D,$0C,$0C,$0D,$0E,$11,$14,$17,$1A,$1C,$1E,$1E,$1D,$1A,$17,$12,$0D,$08,$04,$01,$00,$02,$07,$0F,$1B,$2A,$3D,$52,$68,$7F
SQ_LIMIT14: .db $90,$A1,$B1,$BF,$CD,$D9,$E4,$ED,$F4,$F9,$FD,$FF,$FF,$FE,$FC,$F9,$F6,$F2,$EF,$EB,$E8,$E5,$E3,$E1,$E0,$E0,$E1,$E2,$E4,$E6,$E8,$EB,$ED,$EF,$F1,$F2,$F3,$F4,$F4,$F3,$F2,$F1,$EF,$ED,$EB,$EA,$E8,$E7,$E5,$E5,$E4,$E5,$E5,$E6,$E7,$E9,$EA,$EC,$EE,$EF,$F0,$F1,$F2,$F2,$F2,$F1,$F0,$EF,$EE,$EC,$EA,$E9,$E7,$E6,$E5,$E5,$E4,$E5,$E5,$E7,$E8,$EA,$EB,$ED,$EF,$F1,$F2,$F3,$F4,$F4,$F3,$F2,$F1,$EF,$ED,$EB,$E8,$E6,$E4,$E2,$E1,$E0,$E0,$E1,$E3,$E5,$E8,$EB,$EF,$F2,$F6,$F9,$FC,$FE,$FF,$FF,$FD,$F9,$F4,$ED,$E4,$D9,$CD,$BF,$B1,$A1,$90,$80,$6F,$5E,$4E,$40,$32,$26,$1B,$12,$0B,$06,$02,$00,$00,$01,$03,$06,$09,$0D,$10,$14,$17,$1A,$1C,$1E,$1F,$1F,$1E,$1D,$1B,$19,$17,$14,$12,$10,$0E,$0D,$0C,$0B,$0B,$0C,$0D,$0E,$10,$12,$14,$15,$17,$18,$1A,$1A,$1B,$1A,$1A,$19,$18,$16,$15,$13,$11,$10,$0F,$0E,$0D,$0D,$0D,$0E,$0F,$10,$11,$13,$15,$16,$18,$19,$1A,$1A,$1B,$1A,$1A,$18,$17,$15,$14,$12,$10,$0E,$0D,$0C,$0B,$0B,$0C,$0D,$0E,$10,$12,$14,$17,$19,$1B,$1D,$1E,$1F,$1F,$1E,$1C,$1A,$17,$14,$10,$0D,$09,$06,$03,$01,$00,$00,$02,$06,$0B,$12,$1B,$26,$32,$40,$4E,$5E,$6F,$7F
SQ_LIMIT15: .db $8D,$9A,$A7,$B4,$BF,$CA,$D4,$DE,$E6,$ED,$F2,$F7,$FB,$FD,$FF,$FF,$FF,$FD,$FC,$F9,$F7,$F4,$F1,$EE,$EB,$E8,$E6,$E3,$E2,$E1,$E0,$E0,$E0,$E1,$E2,$E3,$E5,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F3,$F4,$F4,$F4,$F4,$F4,$F3,$F2,$F0,$EF,$ED,$EB,$EA,$E8,$E7,$E5,$E4,$E3,$E3,$E3,$E3,$E3,$E4,$E5,$E7,$E8,$EA,$EB,$ED,$EF,$F0,$F2,$F3,$F4,$F4,$F4,$F4,$F4,$F3,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E5,$E3,$E2,$E1,$E0,$E0,$E0,$E1,$E2,$E3,$E6,$E8,$EB,$EE,$F1,$F4,$F7,$F9,$FC,$FD,$FF,$FF,$FF,$FD,$FB,$F7,$F2,$ED,$E6,$DE,$D4,$CA,$BF,$B4,$A7,$9A,$8D,$80,$72,$65,$58,$4B,$40,$35,$2B,$21,$19,$12,$0D,$08,$04,$02,$00,$00,$00,$02,$03,$06,$08,$0B,$0E,$11,$14,$17,$19,$1C,$1D,$1E,$1F,$1F,$1F,$1E,$1D,$1C,$1A,$19,$17,$15,$13,$11,$0F,$0D,$0C,$0B,$0B,$0B,$0B,$0B,$0C,$0D,$0F,$10,$12,$14,$15,$17,$18,$1A,$1B,$1C,$1C,$1C,$1C,$1C,$1B,$1A,$18,$17,$15,$14,$12,$10,$0F,$0D,$0C,$0B,$0B,$0B,$0B,$0B,$0C,$0D,$0F,$11,$13,$15,$17,$19,$1A,$1C,$1D,$1E,$1F,$1F,$1F,$1E,$1D,$1C,$19,$17,$14,$11,$0E,$0B,$08,$06,$03,$02,$00,$00,$00,$02,$04,$08,$0D,$12,$19,$21,$2B,$35,$40,$4B,$58,$65,$72,$7F

;*** Bandlimited triangle wavetables
TRI_LIMIT0: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT1: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT2: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT3: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT4: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT5: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT6: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT7: .db $81,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$81,$80,$7E,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$05,$03,$01,$00,$01,$03,$05,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7E,$80
TRI_LIMIT8: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EA,$EC,$EE,$F0,$F2,$F4,$F6,$F8,$FB,$FD,$FE,$FF,$FE,$FD,$FB,$F8,$F6,$F4,$F2,$F0,$EE,$EC,$EA,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$15,$13,$11,$0F,$0D,$0B,$09,$07,$04,$02,$01,$00,$01,$02,$04,$07,$09,$0B,$0D,$0F,$11,$13,$15,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT9: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E4,$E6,$E8,$EB,$ED,$EF,$F1,$F2,$F4,$F6,$F9,$FB,$FD,$FE,$FF,$FE,$FD,$FB,$F9,$F6,$F4,$F2,$F1,$EF,$ED,$EB,$E8,$E6,$E4,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1B,$19,$17,$14,$12,$10,$0E,$0D,$0B,$09,$06,$04,$02,$01,$00,$01,$02,$04,$06,$09,$0B,$0D,$0E,$10,$12,$14,$17,$19,$1B,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT10: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BE,$C0,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D1,$D3,$D5,$D7,$D9,$DB,$DD,$DF,$E1,$E3,$E5,$E7,$E9,$EB,$ED,$EF,$F1,$F3,$F5,$F7,$FA,$FC,$FD,$FF,$FF,$FF,$FD,$FC,$FA,$F7,$F5,$F3,$F1,$EF,$ED,$EB,$E9,$E7,$E5,$E3,$E1,$DF,$DD,$DB,$D9,$D7,$D5,$D3,$D1,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C0,$BE,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$41,$3F,$3D,$3B,$39,$37,$35,$33,$31,$2E,$2C,$2A,$28,$26,$24,$22,$20,$1E,$1C,$1A,$18,$16,$14,$12,$10,$0E,$0C,$0A,$08,$05,$03,$02,$00,$00,$00,$02,$03,$05,$08,$0A,$0C,$0E,$10,$12,$14,$16,$18,$1A,$1C,$1E,$20,$22,$24,$26,$28,$2A,$2C,$2E,$31,$33,$35,$37,$39,$3B,$3D,$3F,$41,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT11: .db $81,$83,$85,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B0,$B2,$B4,$B6,$B8,$BA,$BC,$BF,$C1,$C3,$C5,$C7,$C9,$CB,$CD,$CF,$D1,$D3,$D5,$D7,$D9,$DB,$DD,$DF,$E1,$E3,$E5,$E7,$E9,$EB,$ED,$EF,$F1,$F4,$F6,$F8,$FA,$FC,$FE,$FF,$FF,$FF,$FE,$FC,$FA,$F8,$F6,$F4,$F1,$EF,$ED,$EB,$E9,$E7,$E5,$E3,$E1,$DF,$DD,$DB,$D9,$D7,$D5,$D3,$D1,$CF,$CD,$CB,$C9,$C7,$C5,$C3,$C1,$BF,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$85,$83,$81,$80,$7E,$7C,$7A,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4F,$4D,$4B,$49,$47,$45,$43,$40,$3E,$3C,$3A,$38,$36,$34,$32,$30,$2E,$2C,$2A,$28,$26,$24,$22,$20,$1E,$1C,$1A,$18,$16,$14,$12,$10,$0E,$0B,$09,$07,$05,$03,$01,$00,$00,$00,$01,$03,$05,$07,$09,$0B,$0E,$10,$12,$14,$16,$18,$1A,$1C,$1E,$20,$22,$24,$26,$28,$2A,$2C,$2E,$30,$32,$34,$36,$38,$3A,$3C,$3E,$40,$43,$45,$47,$49,$4B,$4D,$4F,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$7A,$7C,$7E,$80
TRI_LIMIT12: .db $81,$83,$85,$87,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AA,$AC,$AE,$B1,$B3,$B5,$B7,$B9,$BB,$BD,$BF,$C1,$C3,$C5,$C7,$C9,$CB,$CD,$CF,$D1,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E2,$E3,$E5,$E7,$E9,$EB,$EE,$F0,$F2,$F5,$F7,$F9,$FB,$FD,$FE,$FF,$FF,$FF,$FE,$FD,$FB,$F9,$F7,$F5,$F2,$F0,$EE,$EB,$E9,$E7,$E5,$E3,$E2,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D1,$CF,$CD,$CB,$C9,$C7,$C5,$C3,$C1,$BF,$BD,$BB,$B9,$B7,$B5,$B3,$B1,$AE,$AC,$AA,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$87,$85,$83,$81,$80,$7E,$7C,$7A,$78,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$55,$53,$51,$4E,$4C,$4A,$48,$46,$44,$42,$40,$3E,$3C,$3A,$38,$36,$34,$32,$30,$2E,$2B,$29,$27,$25,$23,$21,$1F,$1D,$1C,$1A,$18,$16,$14,$11,$0F,$0D,$0A,$08,$06,$04,$02,$01,$00,$00,$00,$01,$02,$04,$06,$08,$0A,$0D,$0F,$11,$14,$16,$18,$1A,$1C,$1D,$1F,$21,$23,$25,$27,$29,$2B,$2E,$30,$32,$34,$36,$38,$3A,$3C,$3E,$40,$42,$44,$46,$48,$4A,$4C,$4E,$51,$53,$55,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$78,$7A,$7C,$7E,$80
TRI_LIMIT13: .db $82,$84,$86,$88,$8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A7,$A9,$AB,$AD,$AF,$B1,$B3,$B5,$B7,$B9,$BB,$BD,$BF,$C1,$C3,$C5,$C7,$C9,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E1,$E3,$E5,$E8,$EA,$EC,$EE,$F1,$F3,$F6,$F8,$FA,$FC,$FD,$FE,$FF,$FF,$FF,$FE,$FD,$FC,$FA,$F8,$F6,$F3,$F1,$EE,$EC,$EA,$E8,$E5,$E3,$E1,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$C9,$C7,$C5,$C3,$C1,$BF,$BD,$BB,$B9,$B7,$B5,$B3,$B1,$AF,$AD,$AB,$A9,$A7,$A4,$A2,$A0,$9E,$9C,$9A,$98,$96,$94,$92,$90,$8E,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$71,$6F,$6D,$6B,$69,$67,$65,$63,$61,$5F,$5D,$5B,$58,$56,$54,$52,$50,$4E,$4C,$4A,$48,$46,$44,$42,$40,$3E,$3C,$3A,$38,$36,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1E,$1C,$1A,$17,$15,$13,$11,$0E,$0C,$09,$07,$05,$03,$02,$01,$00,$00,$00,$01,$02,$03,$05,$07,$09,$0C,$0E,$11,$13,$15,$17,$1A,$1C,$1E,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$36,$38,$3A,$3C,$3E,$40,$42,$44,$46,$48,$4A,$4C,$4E,$50,$52,$54,$56,$58,$5B,$5D,$5F,$61,$63,$65,$67,$69,$6B,$6D,$6F,$71,$73,$75,$77,$79,$7B,$7D,$80
TRI_LIMIT14: .db $82,$84,$86,$88,$8A,$8C,$8F,$91,$93,$95,$97,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8,$AB,$AD,$AF,$B1,$B3,$B6,$B8,$BA,$BC,$BE,$C1,$C3,$C5,$C7,$C9,$CB,$CC,$CE,$D0,$D2,$D4,$D6,$D8,$DA,$DC,$DE,$E0,$E3,$E5,$E7,$EA,$EC,$EF,$F1,$F3,$F6,$F8,$FA,$FB,$FC,$FE,$FE,$FF,$FF,$FF,$FE,$FE,$FC,$FB,$FA,$F8,$F6,$F3,$F1,$EF,$EC,$EA,$E7,$E5,$E3,$E0,$DE,$DC,$DA,$D8,$D6,$D4,$D2,$D0,$CE,$CC,$CB,$C9,$C7,$C5,$C3,$C1,$BE,$BC,$BA,$B8,$B6,$B3,$B1,$AF,$AD,$AB,$A8,$A6,$A4,$A2,$A0,$9E,$9C,$9A,$98,$97,$95,$93,$91,$8F,$8C,$8A,$88,$86,$84,$82,$80,$7D,$7B,$79,$77,$75,$73,$70,$6E,$6C,$6A,$68,$67,$65,$63,$61,$5F,$5D,$5B,$59,$57,$54,$52,$50,$4E,$4C,$49,$47,$45,$43,$41,$3E,$3C,$3A,$38,$36,$34,$33,$31,$2F,$2D,$2B,$29,$27,$25,$23,$21,$1F,$1C,$1A,$18,$15,$13,$10,$0E,$0C,$09,$07,$05,$04,$03,$01,$01,$00,$00,$00,$01,$01,$03,$04,$05,$07,$09,$0C,$0E,$10,$13,$15,$18,$1A,$1C,$1F,$21,$23,$25,$27,$29,$2B,$2D,$2F,$31,$33,$34,$36,$38,$3A,$3C,$3E,$41,$43,$45,$47,$49,$4C,$4E,$50,$52,$54,$57,$59,$5B,$5D,$5F,$61,$63,$65,$67,$68,$6A,$6C,$6E,$70,$73,$75,$77,$79,$7B,$7D,$7F
TRI_LIMIT15: .db $81,$83,$85,$87,$89,$8B,$8D,$8F,$92,$94,$96,$98,$9A,$9D,$9F,$A1,$A3,$A6,$A8,$AA,$AC,$AF,$B1,$B3,$B5,$B7,$B9,$BB,$BD,$BF,$C1,$C2,$C4,$C6,$C8,$CA,$CC,$CE,$D0,$D2,$D4,$D7,$D9,$DB,$DE,$E0,$E2,$E5,$E7,$EA,$EC,$EF,$F1,$F3,$F5,$F7,$F9,$FA,$FC,$FD,$FE,$FE,$FF,$FF,$FF,$FE,$FE,$FD,$FC,$FA,$F9,$F7,$F5,$F3,$F1,$EF,$EC,$EA,$E7,$E5,$E2,$E0,$DE,$DB,$D9,$D7,$D4,$D2,$D0,$CE,$CC,$CA,$C8,$C6,$C4,$C2,$C1,$BF,$BD,$BB,$B9,$B7,$B5,$B3,$B1,$AF,$AC,$AA,$A8,$A6,$A3,$A1,$9F,$9D,$9A,$98,$96,$94,$92,$8F,$8D,$8B,$89,$87,$85,$83,$81,$80,$7E,$7C,$7A,$78,$76,$74,$72,$70,$6D,$6B,$69,$67,$65,$62,$60,$5E,$5C,$59,$57,$55,$53,$50,$4E,$4C,$4A,$48,$46,$44,$42,$40,$3E,$3D,$3B,$39,$37,$35,$33,$31,$2F,$2D,$2B,$28,$26,$24,$21,$1F,$1D,$1A,$18,$15,$13,$10,$0E,$0C,$0A,$08,$06,$05,$03,$02,$01,$01,$00,$00,$00,$01,$01,$02,$03,$05,$06,$08,$0A,$0C,$0E,$10,$13,$15,$18,$1A,$1D,$1F,$21,$24,$26,$28,$2B,$2D,$2F,$31,$33,$35,$37,$39,$3B,$3D,$3E,$40,$42,$44,$46,$48,$4A,$4C,$4E,$50,$53,$55,$57,$59,$5C,$5E,$60,$62,$65,$67,$69,$6B,$6D,$70,$72,$74,$76,$78,$7A,$7C,$7E,$7F

;-------------------------------------------------------------------------------------------------------------------

            .EXIT

;-------------------------------------------------------------------------------------------------------------------
