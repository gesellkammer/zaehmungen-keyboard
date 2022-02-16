/*
	Eduardo Moguillansky -- ZAEHMUNGEN #2 (Bogenwechsel)

	MIDI keyboard patch -- Version 4.0
	Should be used inside CsoundQt
	
	Needs: 
	* CsoundQt version >= 0.9.8
		(download from https://github.com/CsoundQt/CsoundQt/releases)
	* csound version >= 6.15
	       
	Hardware:
		* a MIDI keyboard with at least 67 keys
		* an expression pedal can be connected to control the overall gain
		* a sustain pedal is optional (but can be helpful)
		
*/

<CsoundSynthesizer>
<CsOptions>
-m0  ; disables debug information  
</CsOptions>
<CsInstruments>
sr = 44100
nchnls = 2
ksmps = 64    
0dbfs = 1        
	
/*
					################################
					#         GLOBAL SETUP         #
					################################
*/

;; MIDI Configuration
#define MIDICHANNEL       # 1 #   ; which channel to listen to (0 to listen to all)
#define CC_sustain        # 64 #  ; sustain pedal
#define CC_volume         # 1 #   ; expression pedal used to control gain

#define volumePedalCurve  # 0.8 # ; coefficient for gain pedal curve (1=linear)

;; CONFIGURATION
#define COMPRESSOR_KNEE   # 6 #   ; compressor knee (dB)

#define MINGAIN_DB        # -80 # ; gain value when vol. pedal is at minimum
#define MAXGAIN_DB        # 0   # ; gain value when vol. pedal is at maximum

#define LAG_GLOBAL        #0.005#  ; default lag time   
#define LAG_RATE          #0.005#  ; lag time for grain rate
#define LAG_SPEED         #0.1#    ; lag time for speed modifications
#define ATTACK            #0.002#  ; attack time for every note
#define RELEASE           #0.02#   ; release time for every note
#define RATEMULT          #1.05#   ; a factor multiplying grain rate (higher=faster) 


; ------------------------------------------------------------------------------
; FROM HERE, DO NOT CHANGE IF YOU DO NOT KNOW WHAT YOU ARE DOING
; ------------------------------------------------------------------------------

; Select the set of files used by the keyboard. DEFAULT: sndfiles/48/NORMALIZED
#define SNDFILE_VL    #"assets/sndfiles48/NORMALIZED/VL.wav"#
#define SNDFILE_VLA   #"assets/sndfiles48/NORMALIZED/VLA.wav"#
#define SNDFILE_VC    #"assets/sndfiles48/NORMALIZED/VC.wav"#

#define RATEFACTOR_MAX # 2.5 #
#define RATEFACTOR_MIN # 1 #

#define INFO_UPDATE_RATE #24#
#define SCOPE_PERIOD #0.05#

massign 0, 0

;; Tables
; giSine          ftgen   0, 0, 2^10, 10, 1 
gi_cosineTab      ftgen   0, 0, 8193, 9, 1, 1, 90         ; cosine
gi_distTab        ftgen   0, 0, 32768, 7, 0, 32768, 1     ; for kdistribution
; gi_grainEnvelope  ftgen   0, 0, 4096, 20, 9, 1            ; grain envelope
gi_grainEnvelope  ftgen   0, 0, 8192, 20, 7, 1, 2         ; grain envelope
gi_sigmoRise      ftgen   0, 0, 8193, 19, 0.5, 1, 270, 1  ; rising sigmoid
gi_sigmoFall      ftgen   0, 0, 8193, 19, 0.5, 1, 90, 1   ; falling sigmoid
gi_panTab         ftgen   0, 0, 32768, -21, 1, 0          ; for panning (random values between 0 and 1)

; soundfile for source waveform. -1 = do not normalize
gi_sndfileVl  ftgen   0, 0,     0, -1, $SNDFILE_VL,  0, 0, 0  
gi_sndfileVla ftgen   0, 0,     0, -1, $SNDFILE_VLA, 0, 0, 0
gi_sndfileVc  ftgen   0, 0,     0, -1, $SNDFILE_VC,  0, 0, 0

; UI-Configurable values
gk_noteonMinDb   init -40
gk_noteonMaxDb   init -3
gk_compression   init 0.2
gk_rnd           init 0.35
gk_volpedalCurve init 1


gi_sndfiles[] fillarray gi_sndfileVl, gi_sndfileVla, gi_sndfileVc
gS_tableNames[] fillarray "VL", "VLA", "VC"

gi_speedValues[] fillarray \
	0.1000000, 0.125834, 0.153589, 0.183772, 0.217157, \
	0.2550510, 0.300000, 0.358578, 0.500000, 0.718750, \
	0.8750000, 0.968750, 1.0     , 1.259921, 1.587401, \
	1.2      , 2.519842, 3.174802, 4.0     , 5.039684, \
	6.3496042, 8.0     , 10.07936, 12.69920, 16.0
	
gi_rateFactors[]    genarray $RATEFACTOR_MIN, $RATEFACTOR_MAX, \
                    ($RATEFACTOR_MAX - $RATEFACTOR_MIN)/(ntom:i("3C")-ntom:i("2Eb")-1)

gk_rateFactor       init 1
gk_keybSustainPedal init 0	
gk_keybNotesHeld[]  init 128
gk_keybNotesSustained[] init 128
gi_keybNotesHeld       ftgen 0, 0, 128, 2, 0
gi_keybNotesSustained  ftgen 0, 0, 128, 2, 0

gi_numSpeedValues init lenarray(gi_speedValues)

; C2 +                   F#  G   G#  A    Bb   B
gi_grainDurs[] fillarray 10, 20, 50, 100, 200, 500  ;; ms
gk_grainDurIndex init 3

gi_grainRateMask[] = fillarray(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)

;; Initial Settings ---------------

; The variable with 0-suffix is set by the presets/keyboard commands
; The variable without the 0 is used in the partikkel instrument, 
; a "port"ed version of the 0-suffixed one.

; grain rate in Hz
gk_grainRate, gk_grainRate0 init 8

; playback speed in x (1 == original speed)     
gk_speed, gk_speed0 init 1

; grain duration in ms
gk_grainDuration, gk_grainDuration0 init 100

; gain of the partikkel instr
gk_gain, gk_gain0   init 1  

gi_partikkelInstrnum = 0
gk_tableIndex init 0
gk_table  init gi_sndfileVl
gk_rms    init 0
gk_peak   init 0

gaL init 0
gaR init 0

;; Internal Constants ------------------

#define C2  #36#
#define Cx2 #37#
#define D2  #38#
#define Eb2 #39#
#define E2  #40#
#define F2  #41#
#define Fx2 #42#
#define G2  #43#
#define Ab2 #44#
#define A2  #45#

#define C3  #48#

#define MIDI_NOTEON #144#
#define MIDI_NOTEOFF #128#
#define MIDI_CC     #176#

#define TABLE_VL  #0#
#define TABLE_VLA #1#
#define TABLE_VC  #2#


;; Opcodes -----------------------------

opcode stopEvent, 0, kk
	kinstrnum, kinstance xin
	kevent = kinstrnum + kinstance/1000
	turnoff2 kevent, 4, 1
endop

opcode peakKeep, k, ki
	kpeak, iholdtime  xin
	klast init -99999
	kt timeinsts
	klasttime init 0
	if kpeak > klast then
		klast = kpeak
		klasttime = kt
		kout = kpeak
	elseif kt - klasttime < iholdtime then
		kout = klast
	else
	  kout = kpeak
	  klast = kpeak
	endif
	kout = sc_lagud(kout, 0, 0.05)
	xout kout
endop

opcode playNote, 0, kk
	kmidinote, kvelocity xin
	kposition = (kmidinote - $C3) / 48
	kdb = linlin(kvelocity, gk_noteonMinDb, gk_noteonMaxDb, 0, 127)
	kgain = ampdb(kdb)
	
	stopEvent gi_partikkelInstrnum, kmidinote
	
	schedulek gi_partikkelInstrnum+kmidinote/1000, 0, -1,   \ 
				gk_speed,           \     ; p4
				0,                  \     ; p5 (icent): transposition in cents
				30,                 \     ; p6 (iposrand): max. time randomness in ms
				30,                 \     ; p7 (itranspRandCents): max transposition randomness in cents
				0,                  \     ; p8 (ipan): panning narrow (0) to wide (1)
				0.1,                \     ; p9 (igrainDistribution): grain distribution (0=periodic, 1=scattered)
				kposition,          \     ; p10 (ipos): position in buffer (rel. position 0-1)
				kgain                     ; p11 (igain): event gain (raw amp 0-1)
	
endop


opcode tableChange, 0, k																		
	kindex xin
	if kindex >= 0 && kindex <= 2 then
		gk_tableIndex = kindex
		gk_table = gi_sndfiles[kindex]
		Stab = gS_tableNames[kindex]
		println "Setting table to %d (%s)", kindex, Stab
		outvalue "table", Stab
	else
		println "Table index out of range (%d)\n", kindex
	endif
endop


opcode setSpeedFromKey, 0, k
	kmidinote xin
	kindex = kmidinote - $C3
	if kindex >= 0 && kindex < gi_numSpeedValues then
		gk_speed0 = gi_speedValues[kindex]
	else
		println "Speed change with key out of range. Key: %d\n", kmidinote
	endif
endop


opcode getGrainRateFromKeyboardboard, k, 0
	kidx = 0
	kval = 0
	while kidx < lenarray(gi_grainRateMask) do
		kmidinote = kidx + $C2
		krate = gi_grainRateMask[kidx]
		; knotedown = gk_keybNotesHeld[kmidinote]
		knotedown = tab(kmidinote, gi_keybNotesHeld)
		kval += krate * knotedown
		kidx += 1
	od
	xout kval
endop


opcode setGrainRate, 0, k
	kgrainRate xin
	gk_grainRate0 = kgrainRate
	outvalue "grainRate", sprintfk("%d", kgrainRate)
endop

opcode setRateFactor, 0, k
	kindex xin
	gk_rateFactor = gi_rateFactors[kindex]
	outvalue "rateFactor", sprintfk("%.2f", gk_rateFactor)
endop
	
opcode setGrainDurationFromKey, 0, k
	kmidinote xin
	kidx = kmidinote - $Fx2
	gk_grainDuration0 = gi_grainDurs[kidx]
	outvalue "grainDuration", sprintfk("%d", gk_grainDuration0)
endop

opcode setGainPedal, 0, k
	kvalue xin  ; kvalue: betwee 0 and 1
	outvalue "gainPedal", kvalue 
	gk_gain0 = kvalue
endop

opcode setSustainPedal, 0, k
	kstate xin
	outvalue "sustPedal", kstate
	gk_keybSustainPedal = kstate
	if kstate == 1 then
		; press sustain pedal.
		tablecopy gi_keybNotesSustained, gi_keybNotesHeld
		; gk_keybNotesSustained = gk_keybNotesHeld
		kgoto finish
	endif
	; release all notes which are sustained but are not being held
	kidx = $C3
	while kidx < 128 do
		if tab:k(kidx, gi_keybNotesSustained) == 1 && tab:k(kidx, gi_keybNotesHeld) == 0 then
		; if gk_keybNotesSustained[kidx] == 1 && gk_keybNotesHeld[kidx] == 0 then
			stopEvent gi_partikkelInstrnum, kidx
		endif
		kidx += 1
	od
	; reset all sustained notes
	println "Resetting sustained notes"	
	ftset gi_keybNotesSustained, 0
	; gk_keybNotesSustained = 0
finish:
endop


;; ----- Instrs -----

instr setup
	tableChange($TABLE_VL)
	setRateFactor(0)
	setGrainDurationFromKey($A2)
	setGrainRate(10)
	setGainPedal(1)
	setSustainPedal(0)
	
	gi_partikkelInstrnum = nstrnum("partikkel")
	outvalue "graph1", "@find signal gaL"
	outvalue "graph2", "@find signal aL"
	
	turnoff
endin

instr io
	; gk_table = gi_sndfiles[gk_tableIndex]
	gk_grainRate = port(gk_grainRate0 * gk_rateFactor, $LAG_RATE) * $RATEMULT
	gk_speed = port(gk_speed0, $LAG_SPEED)
	gk_grainDuration = port(gk_grainDuration0,  $LAG_GLOBAL)
	gk_gain = port(gk_gain0, $LAG_GLOBAL)

	gk_noteonMaxDb invalue "noteonMaxDb"
	gk_noteonMinDb invalue "noteonMinDb"
	krandomness  invalue "randomness"
	
	gk_rnd = krandomness
	
	; MIDI
	kstatus, kchan, kdata1, kdata2 midiin
	

	if metro($INFO_UPDATE_RATE) == 1 then
		krmsdB = limit(dbamp:k(gk_rms), -120, 18)
		kpeakdB = limit(dbamp:k(gk_peak), -120, 18)
		outvalue "peak", kpeakdB
		outvalue "rms", krmsdB
	endif
	
	if metro($INFO_UPDATE_RATE/4) == 1 then
		outvalue "peaktext", kpeakdB
		outvalue "rmstext", krmsdB
	endif
endin


instr midiIn
	; This instrument runs all the time
	kstatus init 0
	kstatus = 0
	kstatus, kchan, kdata1, kdata2 midiin
	if kchan != $MIDICHANNEL || kchan > 0 then
		println "Received MIDI in channel %d, but listening to channel %d", \
			kchan, $MIDICHANNEL
		kgoto finish 
	endif
	if kstatus == $MIDI_NOTEON && kdata1 > 0 then
		schedulek "noteon", 0, -1, kdata1, kdata2
	elseif kstatus == $MIDI_NOTEOFF then
		schedulek "noteoff", 0, -1, kdata1 
	elseif kstatus == $MIDI_CC then
		schedulek "midicc", 0, -1, kchan, kdata1, kdata2
	endif
endin


instr noteon		; (midinote, velocity)
	imidinote, ivelocity passign 4
	kmidinote = imidinote	
	if imidinote < $C2 then
		prints "Key %d out of range\n", imidinote
		goto finish
	endif
	
	; if i(gk_keybNotesHeld, imidinote) == 1 then
	if table(imidinote, gi_keybNotesHeld) == 1 then
		prints "Key %d already down\n", imidinote
		goto finish
	endif

	; gk_keybNotesHeld[imidinote] = 1    ; mark note as down
	tabw(1, imidinote, gi_keybNotesHeld)

	; keep track of notes held by pedal
	if gk_keybSustainPedal == 1 then
		tabw(1, imidinote, gi_keybNotesSustained) 
		; gk_keybNotesSustained[imidinote] = 1
	endif

	if imidinote >= $C3 then
		; normal note, outside the control octave
		; if gk_keybNotesHeld[$Cx2] == 1 then
		if tab:k($Cx2, gi_keybNotesHeld) == 1 then
			; Cx2 is beeing held down: change of speed
			setSpeedFromKey(imidinote)
		else
			; normal note
			playNote(imidinote, ivelocity)
		endif
		goto finish
	endif
	
	; for C2 and Cx2, we just mark them as down, they work as "shift" keys
	if imidinote <= $Cx2 then
		goto finish
	endif
	
	; inside the control octave
	; if gk_keybNotesHeld[$C2] == 1 then
	if tab:k($C2, gi_keybNotesHeld) == 1 then
		; C2 is down, the pressed key changes either table (D,E,F),
		; grain dur (F#-B) or panic (Eb)
		if imidinote == $D2 then
			tableChange($TABLE_VC) 
		elseif imidinote == $E2 then
			tableChange($TABLE_VLA)
		elseif imidinote == $F2 then
			tableChange($TABLE_VL)
		elseif imidinote == $Eb2 then
			schedulek "panic", 0, -1
		else
			; grain duration
			setGrainDurationFromKey(imidinote)
		endif
	; elseif gk_keybNotesHeld[$Cx2] == 1 && imidinote >= $Eb2 then
	elseif tab:k($Cx2, gi_keybNotesHeld) == 1 && imidinote >= $Eb2 then
		; Cx2 is down. Cx2 + Eb2-B2 changes the rate factor
		kidx = imidinote - $Eb2
		setRateFactor(kidx)
		; gk_rateFactor = gi_rateFactors[kidx]
	else
		; No shift keys, change the grain rate
		setGrainRate(getGrainRateFromKeyboardboard())
	endif
	
finish:
	turnoff
endin


instr noteoff
	imidinote = p4
	; if gk_keybNotesHeld[imidinote] == 0 then
	if tab:k(imidinote, gi_keybNotesHeld) == 0 then
		println "Note %d (%s) was not held\n", imidinote, mton(imidinote)
		schedulek "panic", 0, -1
		kgoto finish
	endif
	
	; gk_keybNotesHeld[imidinote] = 0
	tabw(0, imidinote, gi_keybNotesHeld)

	if gk_keybSustainPedal == 1 then
		println "Note held by pedal: %d\n", imidinote
		kgoto finish
	endif

	if imidinote >= $C3 then
		stopEvent gi_partikkelInstrnum, imidinote
	endif
		
finish:
	turnoff
endin


instr midicc
	ichan, icc, ivalue passign 4
	if icc == $CC_volume then
		igainrel = (ivalue/127) ^ $volumePedalCurve
		igain = linlin:i(igainrel, ampdb($MINGAIN_DB), ampdb($MAXGAIN_DB))
		setGainPedal(igain)
	elseif icc == $CC_sustain then
		println "sustain pedal: %d", ivalue
		setSustainPedal(ivalue > 0 ? 1 : 0)
	else
		println "CC unknown: %d = %d", icc, ivalue
	endif
	turnoff
endin
	

instr panic
	; turn off all notes
	turnoff2 gi_partikkelInstrnum, 0, 0
	turnoff
endin


instr partikkel
	ispeed          = p4   ; 1 = original speed 
	icent           = p5   ; transposition in cent
	iposrand        = p6   ; max time randomness (offset) of the pointer in ms
	itranspRandCents = p7   ; max transposition randomness in cents
	ipan            = p8   ; panning narrow (0) to wide (1)
	igrainDistribution = p9   ; grain distribution (0=periodic, 1=scattered)
	ipos            = p10
	igain           = p11
		
	; get length of source wave file, needed for both transposition 
	; and time pointer*/
	ifilen = ftlen(gi_sndfileVl)
	ifilsr = ftsr(gi_sndfileVl)
	ifildur = ifilen / sr
	; TODO: is this correct???
	; ifildur = ifilen / ifilsr
	
	; sync input (disabled)
	async = 0     
	
	; grain envelope
	kenv2amt = 1         ; use only secondary envelope
	ienv2tab = gi_grainEnvelope     ; grain (secondary) envelope
	ienvAttack = gi_sigmoRise 
	ienvDecay = gi_sigmoFall
	; no meaning in this case (use only secondary envelope, ienv2tab)
	ksustainAmount = 0.5       
	ka_d_ratio = 0.5       
	
	; amplitude
	kamp = 1*0dbfs         ; grain amplitude
	igainmasks = -1        ; (default) no gain masking
	
	; transposition
	ktransprand = itranspRandCents * gk_rnd
	kcentrand   rnd ktransprand    ; random transposition
	
	iorig    = 1 / ifildur   ; original pitch
	kwavfreq = iorig * gk_speed * cent(icent + kcentrand)
	
	; other pitch related (disabled)
	ksweepshape      = 0        ; no frequency sweep
	iwavfreqstarttab = -1       ; default frequency sweep start
	iwavfreqendtab   = -1       ; default frequency sweep end
	awavfm      = 0     ; no FM input
	ifmamptab   = -1        ; default FM scaling (=1)
	kfmenv      = -1        ; default FM envelope (flat)
	
	; trainlet related (disabled)
	icosine = gi_cosineTab   ; cosine ftable
	ktrainFreq = gk_grainRate ; set trainlet cps equal to grain rate 
													 ; for single-cycle trainlet in each grain
	knumPartials = 1        ; number of partials in trainlet
	kchroma = 1             ; balance of partials in trainlet

	/* panning, using channel masks */
	imid        = .5        ; center
	ileftmost   = imid - ipan/2
	irightmost  = imid + ipan/2
	
	/*
	gi_panTabthis   ftgen   0, 0, 32768, -24, gi_panTab, ileftmost, irightmost  ; rescales gi_panTab according to ipan
	tableiw 0, 0, gi_panTabthis             ; change index 0 ...
	tableiw 32766, 1, gi_panTabthis         ; ... and 1 for ichannelmasks
	*/
	; ichannelmasks = gi_panTabthis       ; ftable for panning
	ichannelmasks = gi_panTab

	/* random gain masking (disabled) */
	krandommask     = 0 

	/* source waveforms */
	kwaveform1      = gk_table      ; source waveform
	kwaveform2      = kwaveform1    ; all 4 sources are the same
	kwaveform3      = kwaveform1
	kwaveform4      = kwaveform1
	;** (default) equal mix of source waveforms, no amplitude for trainlets
	iwaveamptab     = -1	

	/* time pointer */
	afilposphas     phasor ispeed / ifildur
	/*generate random deviation of the time pointer*/
	kposrandphase     = (iposrand * gk_rnd) / 1000 / ifildur
	krndpos         linrand  kposrandphase  ; random offset in phase values
	/*add random deviation to the time pointer*/
	; asamplepos1       = floor(kslider1 * 2) / 96; afilposphas + krndpos; resulting phase values (0-1)
	; asamplepos1     = gk_pos + krndpos
	asamplepos1     = ipos + krndpos
	asamplepos2     = asamplepos1
	asamplepos3     = asamplepos1   
	asamplepos4     = asamplepos1   

	;** original key for each source waveform
	kwavekey1       = 1
	kwavekey2       = kwavekey1 
	kwavekey3       = kwavekey1
	kwavekey4       = kwavekey1

	;** maximum number of grains per k-period
	imax_grains     = 100       
	ksize  = gk_grainDuration   ; ms
	
	aL, aR  partikkel \
			gk_grainRate, igrainDistribution, gi_distTab, async, kenv2amt, ienv2tab, \
			ienvAttack, ienvDecay, ksustainAmount, ka_d_ratio, \ 
			ksize, kamp, igainmasks, kwavfreq, ksweepshape, \
			iwavfreqstarttab, iwavfreqendtab, awavfm, ifmamptab, 
			kfmenv, gi_cosineTab, ktrainFreq, knumPartials, kchroma, \ 
			ichannelmasks, krandommask, \ 
			kwaveform1, kwaveform2, kwaveform3, kwaveform4, \
			iwaveamptab, \
			asamplepos1, asamplepos2, asamplepos3, asamplepos4, \ 
			kwavekey1, kwavekey2, kwavekey3, kwavekey4, imax_grains
	; kgain = igain * gk_gain
		
	aenv linenr igain, $ATTACK, $RELEASE, 0.01
	aL *= aenv
	gaL += aL
	gaR += aL
	
endin


instr master
	; kcompThresh = $COMPRESSOR_THRESHOLD
	kcompThresh invalue "compThresh"
	kcompKnee = $COMPRESSOR_KNEE
	kcompAttack = 0.001
	kcompRelease = 0.17
	ilimiterLookahead = 0.005
	
	kcompLoKnee = kcompThresh - kcompKnee
	kcompHiKnee = kcompThresh
	kcompRatio    invalue "compRatio"
	kcompGainCompDb invalue "compGainComp"
	kcompGate  = -90
	
	kmasterGainDb invalue "masterGain"
	kmasterGain = ampdb(kmasterGainDb)
	
	aL = gaL
	aR = gaR
	
	kgain = ampdb(kcompGainCompDb) * gk_gain
	apreGain = interp(kgain)
	aL *= apreGain
	aR *= apreGain
	
	aL compress2 aL, aL, kcompGate, kcompLoKnee, kcompHiKnee, kcompRatio, \
	                  kcompAttack, kcompRelease, 0
	aR compress2 aR, aR, kcompGate, kcompLoKnee, kcompHiKnee, kcompRatio, \
	                  kcompAttack, kcompRelease, 0             
	   
	aL *= kmasterGain
	aR *= kmasterGain
	
	// limiter
	aL compress2, aL, aL, -120, -2, -0.5, 40, 0.001, 0.01, ilimiterLookahead
	aR compress2, aR, aR, -120, -2, -0.5, 40, 0.001, 0.01, ilimiterLookahead
	
	display gaL, $SCOPE_PERIOD
	display aL, $SCOPE_PERIOD
	
	gk_rms    rms aL
	gk_rms = sc_lagud(gk_rms, 0, 0.2)
	kpeakTrig metro $INFO_UPDATE_RATE * 4
	kmax    max_k aL, kpeakTrig, 1
	gk_peak = peakKeep(kmax, 2)

	outs aL, aR
	gaR = 0
	gaL = 0
endin

</CsInstruments>
<CsScore>
i "setup"  0.1 -1 
 
i "io"     0.2 -1 
i "midiIn" 0.2 -1 
i "master" 0 -1 
 
; i "noteon" 0.5 1 47 90 
 
f 0 36000 
e 
 </CsScore>


</CsoundSynthesizer>
<bsbPanel>
 <label>Widgets</label>
 <objectName/>
 <x>0</x>
 <y>0</y>
 <width>495</width>
 <height>544</height>
 <visible>true</visible>
 <uuid/>
 <bgcolor mode="background">
  <r>22</r>
  <g>22</g>
  <b>22</b>
 </bgcolor>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>5</x>
  <y>9</y>
  <width>490</width>
  <height>535</height>
  <uuid>{91b410f9-6cf7-4908-a0b8-c59a7ed08e83}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label/>
  <alignment>left</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>10</fontsize>
  <precision>3</precision>
  <color>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </color>
  <bgcolor mode="background">
   <r>33</r>
   <g>33</g>
   <b>33</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>3</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>randomness</objectName>
  <x>90</x>
  <y>75</y>
  <width>64</width>
  <height>64</height>
  <uuid>{225f2b09-4816-4787-94f6-8dfe841b50bd}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Randomness scaling for all random parameters</description>
  <minimum>0.00000000</minimum>
  <maximum>2.00000000</maximum>
  <value>0.94940000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>207</r>
   <g>101</g>
   <b>255</b>
  </color>
  <textcolor>#cf65ff</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>false</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>90</x>
  <y>135</y>
  <width>60</width>
  <height>25</height>
  <uuid>{4ad07c65-83cd-42f3-ba2b-b6936e690637}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Random</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>207</r>
   <g>101</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>compRatio</objectName>
  <x>385</x>
  <y>75</y>
  <width>64</width>
  <height>64</height>
  <uuid>{1437ab93-4334-4969-a201-bfaf65fe0db7}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description/>
  <minimum>1.00000000</minimum>
  <maximum>10.00000000</maximum>
  <value>2.19880000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>245</r>
   <g>124</g>
   <b>0</b>
  </color>
  <textcolor>#f27a00</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>false</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>370</x>
  <y>135</y>
  <width>90</width>
  <height>40</height>
  <uuid>{0b96a964-004f-4d5b-a813-c7978d9966b2}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Compression
Ratio</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>255</r>
   <g>170</g>
   <b>0</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>5</x>
  <y>15</y>
  <width>490</width>
  <height>40</height>
  <uuid>{829190bd-cdff-4568-93fe-f8b0d6ca7ca0}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Zaehmungen #2 (Bogenwechsel)</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>16</fontsize>
  <precision>3</precision>
  <color>
   <r>241</r>
   <g>241</g>
   <b>241</b>
  </color>
  <bgcolor mode="nobackground">
   <r>37</r>
   <g>37</g>
   <b>37</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>2</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>noteonMinDb</objectName>
  <x>90</x>
  <y>210</y>
  <width>64</width>
  <height>64</height>
  <uuid>{716b0fa3-1a98-4367-ad11-693433db66ef}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Amplitude (in dB) corresponding to velocity 1</description>
  <minimum>-90.00000000</minimum>
  <maximum>0.00000000</maximum>
  <value>-51.00300000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>0</r>
   <g>255</g>
   <b>127</b>
  </color>
  <textcolor>#00ff7f</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>true</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>85</x>
  <y>270</y>
  <width>69</width>
  <height>55</height>
  <uuid>{ee541656-0b96-4e4d-a61f-462adc7467eb}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Amplitude (in dB) corresponding to note velocity 1</description>
  <label>Min Amplitude (dB)</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>0</r>
   <g>255</g>
   <b>127</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>noteonMaxDb</objectName>
  <x>185</x>
  <y>210</y>
  <width>64</width>
  <height>64</height>
  <uuid>{3a04ce9a-f35d-400c-98b7-a6a41af19fdf}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Amplitude (in dB) corresponding to velocity 127</description>
  <minimum>-90.00000000</minimum>
  <maximum>0.00000000</maximum>
  <value>-10.50300000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>0</r>
   <g>255</g>
   <b>127</b>
  </color>
  <textcolor>#00ff7f</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>true</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>180</x>
  <y>270</y>
  <width>72</width>
  <height>53</height>
  <uuid>{b24615bb-d9cb-4d7f-af58-866f5cbe0920}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Max Amplitude (dB)</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>0</r>
   <g>255</g>
   <b>127</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBController" version="2">
  <objectName/>
  <x>35</x>
  <y>105</y>
  <width>30</width>
  <height>160</height>
  <uuid>{f6950dc1-6561-4e22-a5e5-ff95d0920df1}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Meter of audio post compressor/limiter</description>
  <objectName2>rms</objectName2>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>-70.00000000</yMin>
  <yMax>12.00000000</yMax>
  <xValue>0.00000000</xValue>
  <yValue>-120.00000000</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <bordermode>border</bordermode>
  <borderColor>#49dc00</borderColor>
  <color>
   <r>73</r>
   <g>220</g>
   <b>0</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>12</r>
   <g>38</g>
   <b>0</b>
  </bgcolor>
  <bgcolormode>true</bgcolormode>
 </bsbObject>
 <bsbObject type="BSBScrollNumber" version="2">
  <objectName>peaktext</objectName>
  <x>35</x>
  <y>80</y>
  <width>30</width>
  <height>28</height>
  <uuid>{1f80ff96-5e37-4bd3-b874-9ca71a5ebcc5}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Peak (dB)</description>
  <alignment>center</alignment>
  <font>Arial</font>
  <fontsize>11</fontsize>
  <color>
   <r>255</r>
   <g>105</g>
   <b>30</b>
  </color>
  <bgcolor mode="nobackground">
   <r>22</r>
   <g>22</g>
   <b>22</b>
  </bgcolor>
  <value>-1.23965276</value>
  <resolution>1.00000000</resolution>
  <minimum>-99.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>false</bordermode>
  <borderradius>0</borderradius>
  <borderwidth>0</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject type="BSBScrollNumber" version="2">
  <objectName>rmstext</objectName>
  <x>35</x>
  <y>265</y>
  <width>30</width>
  <height>28</height>
  <uuid>{5235a894-fe01-4c8b-aebf-c3fbc389d421}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>rms (dB)</description>
  <alignment>center</alignment>
  <font>Arial</font>
  <fontsize>11</fontsize>
  <color>
   <r>100</r>
   <g>220</g>
   <b>40</b>
  </color>
  <bgcolor mode="nobackground">
   <r>22</r>
   <g>22</g>
   <b>22</b>
  </bgcolor>
  <value>-120.00000000</value>
  <resolution>1.00000000</resolution>
  <minimum>-99.00000000</minimum>
  <maximum>999999999999.00000000</maximum>
  <bordermode>false</bordermode>
  <borderradius>0</borderradius>
  <borderwidth>0</borderwidth>
  <randomizable group="0">false</randomizable>
  <mouseControl act=""/>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>masterGain</objectName>
  <x>380</x>
  <y>210</y>
  <width>64</width>
  <height>64</height>
  <uuid>{40e7950e-7379-466c-8e7a-0678feaadd10}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Master gain (in dB) pre limiter</description>
  <minimum>-60.00000000</minimum>
  <maximum>18.00000000</maximum>
  <value>-0.71220000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>85</r>
   <g>170</g>
   <b>255</b>
  </color>
  <textcolor>#55a8fb</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>true</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>355</x>
  <y>270</y>
  <width>115</width>
  <height>42</height>
  <uuid>{22a7a682-9a40-4523-8b66-6dd474e16f20}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Master Volume
(dB)</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>85</r>
   <g>170</g>
   <b>255</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>compThresh</objectName>
  <x>285</x>
  <y>75</y>
  <width>64</width>
  <height>64</height>
  <uuid>{fa6008c7-2f5c-4bc1-9019-f26e95c61ee9}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Compression Threshold (dB)</description>
  <minimum>-48.00000000</minimum>
  <maximum>0.00000000</maximum>
  <value>-6.41760000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>245</r>
   <g>124</g>
   <b>0</b>
  </color>
  <textcolor>#f27a00</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>true</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>270</x>
  <y>135</y>
  <width>90</width>
  <height>52</height>
  <uuid>{5e458df9-69f9-4905-844d-6996d9a001bb}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Compression
Threshold 
(dB)</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>255</r>
   <g>170</g>
   <b>0</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBKnob" version="2">
  <objectName>compGainComp</objectName>
  <x>185</x>
  <y>75</y>
  <width>64</width>
  <height>64</height>
  <uuid>{947c480b-989b-4109-b5a1-6d4c7fb1a3e0}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Gain before compression (in dB)</description>
  <minimum>0.00000000</minimum>
  <maximum>36.00000000</maximum>
  <value>4.15080000</value>
  <mode>lin</mode>
  <mouseControl act="">continuous</mouseControl>
  <resolution>0.01000000</resolution>
  <randomizable group="0">false</randomizable>
  <color>
   <r>245</r>
   <g>124</g>
   <b>0</b>
  </color>
  <textcolor>#f27a00</textcolor>
  <showvalue>true</showvalue>
  <flatstyle>true</flatstyle>
  <integerMode>true</integerMode>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>170</x>
  <y>135</y>
  <width>91</width>
  <height>52</height>
  <uuid>{b961b102-7e01-426d-952b-f1f95b4deea5}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Compression
Pre Gain 
(dB)</label>
  <alignment>center</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>14</fontsize>
  <precision>3</precision>
  <color>
   <r>255</r>
   <g>170</g>
   <b>0</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>60</x>
  <y>335</y>
  <width>95</width>
  <height>30</height>
  <uuid>{f371d50c-60f3-425d-8eb7-c8bee448d081}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>PRE compressor</label>
  <alignment>left</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>11</fontsize>
  <precision>3</precision>
  <color>
   <r>199</r>
   <g>199</g>
   <b>199</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>245</x>
  <y>335</y>
  <width>143</width>
  <height>30</height>
  <uuid>{54b5f4c1-9f70-43ed-a955-b4f3e695c8d8}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>POST compressor/limiter</label>
  <alignment>left</alignment>
  <valignment>top</valignment>
  <font>Arial</font>
  <fontsize>11</fontsize>
  <precision>3</precision>
  <color>
   <r>199</r>
   <g>199</g>
   <b>199</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBGraph" version="2">
  <objectName>graph1</objectName>
  <x>60</x>
  <y>360</y>
  <width>180</width>
  <height>80</height>
  <uuid>{f1feda95-b3bb-4f36-9c6f-a012e2e17c57}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Audio before copression</description>
  <value>11</value>
  <objectName2/>
  <zoomx>1.00000000</zoomx>
  <zoomy>1.00000000</zoomy>
  <dispx>1.00000000</dispx>
  <dispy>1.00000000</dispy>
  <modex>lin</modex>
  <modey>lin</modey>
  <showSelector>false</showSelector>
  <showGrid>false</showGrid>
  <showTableInfo>false</showTableInfo>
  <showScrollbars>true</showScrollbars>
  <all>true</all>
 </bsbObject>
 <bsbObject type="BSBGraph" version="2">
  <objectName>graph2</objectName>
  <x>245</x>
  <y>360</y>
  <width>180</width>
  <height>80</height>
  <uuid>{964a2865-8fbb-4716-a875-8525e53fff50}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Audio after gain scaling/compressor/limiter</description>
  <value>12</value>
  <objectName2/>
  <zoomx>1.00000000</zoomx>
  <zoomy>1.00000000</zoomy>
  <dispx>1.00000000</dispx>
  <dispy>1.00000000</dispy>
  <modex>lin</modex>
  <modey>lin</modey>
  <showSelector>false</showSelector>
  <showGrid>true</showGrid>
  <showTableInfo>false</showTableInfo>
  <showScrollbars>true</showScrollbars>
  <all>true</all>
 </bsbObject>
 <bsbObject type="BSBDisplay" version="2">
  <objectName>table</objectName>
  <x>70</x>
  <y>455</y>
  <width>50</width>
  <height>25</height>
  <uuid>{83b25314-8620-46b1-9271-2cab3f2d5981}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Which soundfile is acted upon</description>
  <label>VL</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>221</r>
   <g>146</g>
   <b>255</b>
  </color>
  <bgcolor mode="background">
   <r>69</r>
   <g>34</g>
   <b>85</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>3</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>65</x>
  <y>480</y>
  <width>60</width>
  <height>30</height>
  <uuid>{b51c60ce-4fc1-4041-ab66-ad6e37bbc698}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Soundfile</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>209</r>
   <g>139</g>
   <b>214</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBDisplay" version="2">
  <objectName>rateFactor</objectName>
  <x>355</x>
  <y>455</y>
  <width>50</width>
  <height>25</height>
  <uuid>{d9d2c410-25bf-4785-a4be-8666485e198e}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Factor modifying all rates</description>
  <label>1.00</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>221</r>
   <g>146</g>
   <b>255</b>
  </color>
  <bgcolor mode="background">
   <r>69</r>
   <g>34</g>
   <b>85</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>3</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>340</x>
  <y>480</y>
  <width>76</width>
  <height>28</height>
  <uuid>{4155a0d0-4d23-4792-9036-868c6bdfe185}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Rate Factor</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>209</r>
   <g>139</g>
   <b>214</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBDisplay" version="2">
  <objectName>grainDuration</objectName>
  <x>165</x>
  <y>455</y>
  <width>50</width>
  <height>25</height>
  <uuid>{76831217-f37b-496c-b716-11e2375bbf3f}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Duration of each grain</description>
  <label>100</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>221</r>
   <g>146</g>
   <b>255</b>
  </color>
  <bgcolor mode="background">
   <r>69</r>
   <g>34</g>
   <b>85</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>3</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>150</x>
  <y>480</y>
  <width>77</width>
  <height>40</height>
  <uuid>{9f80a6d2-a784-47aa-989c-add90d18c32e}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Grain Dur. (ms)</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>209</r>
   <g>139</g>
   <b>214</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBDisplay" version="2">
  <objectName>grainRate</objectName>
  <x>260</x>
  <y>455</y>
  <width>50</width>
  <height>25</height>
  <uuid>{c0e75be3-6a15-48d5-a756-af4527b38b5c}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description>Grain Frequency (average) in Hz</description>
  <label>10</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>221</r>
   <g>146</g>
   <b>255</b>
  </color>
  <bgcolor mode="background">
   <r>69</r>
   <g>34</g>
   <b>85</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>3</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBLabel" version="2">
  <objectName/>
  <x>245</x>
  <y>480</y>
  <width>77</width>
  <height>40</height>
  <uuid>{3d86d8a2-2840-48a9-aa21-fdbf769ff52b}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>-3</midicc>
  <description/>
  <label>Grain Rate (hz)</label>
  <alignment>center</alignment>
  <valignment>center</valignment>
  <font>Arial</font>
  <fontsize>13</fontsize>
  <precision>3</precision>
  <color>
   <r>209</r>
   <g>139</g>
   <b>214</b>
  </color>
  <bgcolor mode="nobackground">
   <r>255</r>
   <g>255</g>
   <b>255</b>
  </bgcolor>
  <bordermode>false</bordermode>
  <borderradius>1</borderradius>
  <borderwidth>0</borderwidth>
 </bsbObject>
 <bsbObject type="BSBController" version="2">
  <objectName/>
  <x>15</x>
  <y>105</y>
  <width>10</width>
  <height>160</height>
  <uuid>{afbc5bae-dc58-41d5-9227-a50f36d03a40}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Activity of the gain pedal</description>
  <objectName2>gainPedal</objectName2>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.00000000</xValue>
  <yValue>1.00000000</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <bordermode>noborder</bordermode>
  <borderColor>#00ff00</borderColor>
  <color>
   <r>216</r>
   <g>30</g>
   <b>30</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>0</r>
   <g>0</g>
   <b>0</b>
  </bgcolor>
  <bgcolormode>false</bgcolormode>
 </bsbObject>
 <bsbObject type="BSBController" version="2">
  <objectName/>
  <x>440</x>
  <y>460</y>
  <width>15</width>
  <height>15</height>
  <uuid>{94809790-7826-4357-8135-75a80b244f61}</uuid>
  <visible>true</visible>
  <midichan>0</midichan>
  <midicc>0</midicc>
  <description>Sustain Pedal</description>
  <objectName2>sustPedal</objectName2>
  <xMin>0.00000000</xMin>
  <xMax>1.00000000</xMax>
  <yMin>0.00000000</yMin>
  <yMax>1.00000000</yMax>
  <xValue>0.00000000</xValue>
  <yValue>0.00000000</yValue>
  <type>fill</type>
  <pointsize>1</pointsize>
  <fadeSpeed>0.00000000</fadeSpeed>
  <mouseControl act="press">jump</mouseControl>
  <bordermode>border</bordermode>
  <borderColor>#faa77d</borderColor>
  <color>
   <r>255</r>
   <g>170</g>
   <b>127</b>
  </color>
  <randomizable mode="both" group="0">false</randomizable>
  <bgcolor>
   <r>22</r>
   <g>22</g>
   <b>22</b>
  </bgcolor>
  <bgcolormode>true</bgcolormode>
 </bsbObject>
</bsbPanel>
<bsbPresets>
</bsbPresets>
