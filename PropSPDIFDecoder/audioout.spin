''***************************************************************************
''* Analog Audio Output for S/PDIF Decoder
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
{{
  This module demonstrates an audio player using the data from the
  biphase decoder.

  It uses the two timers in Duty Cycle mode, on a single cog, to play the
  audio data from the biphase decoder to two output pins that are connected
  to speakers or headphones.

  I tested this with the headphone outputs of a "QuickStart Human Interface
  Board for QuickStart" (Parallax 40003) mounted on top of a QuickStart
  (Parallax 40000) and yes, you can hear the audio, but NO, it isn't exactly
  "CD quality". Not even close! That's no suprise of course; the Propeller
  only has digital pins so the Duty Cycle based D/A conversion is (at best)
  an approximation.

  Oh well. It's only a demo. The project is not intended to even do audio,
  but this module proves that the audio data is processed correctly by the
  Biphase decoder.

  PS For some reason that I can't quite figure out, sometimes the audio
  gets sent out WAY loud and WAY distorted. A reboot fixes the problem.
  I think this has to do with us not resetting the PHSA/PHSB or something,
  so that sometimes the counters and the code get into some race condition.
  I may look at it in the future but I'm open to suggestions if you
  have one.
}}

OBJ
  hw:           "hardware"

PUB Start(par_psample)
'' par_sample (pointer to long): SPDIF subframe
''

  cognew(@audiocog, par_psample)
  
DAT 
                        org 0
audiocog
                        ' Init I/O
                        mov     outa, #0
                        mov     dira, outputmask

                        ' Init timer A (Left Channel)
                        mov     ctra, ctraval
                        mov     frqa, #0
                        mov     phsa, #0

                        ' Init timer B (Right Channel)
                        mov     ctrb, ctrbval
                        mov     frqb, #0
                        mov     phsb, #0

loop
                        ' Wait for the next subframe
                        waitpeq zero, mask_PRADET
                        waitpne zero, mask_PRADET

                        ' Get subframe from the sample pointer                        
                        rdlong  subframe, par

                        ' Copy the subframe to the sample
                        ' Make sure the parity is even and the data is valid
                        mov     sample, subframe wc
                        test    sample, mask_VALIDITY wz
        if_c_or_nz      jmp     #loop
                        
                        shl     sample, #(31 - hw#sh_AUDIOMSB)
                        and     sample, filter          ' Cut off non-audio bits, probably not needed                        
                        add     sample, v8000_0000

                        ' Update only the channel that needs updating
                        test    subframe, mask_LCHAN wc
              if_c      mov     left, sample
              if_nc     mov     right, sample

                        ' Write both timers always (though this doesn't
                        ' appear necessary and could generate more
                        ' quantization noise)
                        mov     frqa, left
                        mov     frqb, right
                        
                        jmp     #loop

sample                  long    0
subframe                long    0
left                    long    0
right                   long    0        

zero                    long    0
outputmask              long    hw#mask_AUDIOL | hw#mask_AUDIOR                        
ctraval                 long    (%00110 << 26) | hw#pin_AUDIOL
ctrbval                 long    (%00110 << 26) | hw#pin_AUDIOR
v8000_0000              long    $8000_0000
filter                  long    $FFFF0000

mask_PRADET             long    |< hw#pin_PRADET
mask_LCHAN              long    |< hw#sh_LCHAN
mask_VALIDITY           long    |< hw#sh_VALIDITY

                        fit
                        
CON     
''***************************************************************************
''* MIT LICENSE
''*
''* Permission is hereby granted, free of charge, to any person obtaining a
''* copy of this software and associated documentation files (the
''* "Software"), to deal in the Software without restriction, including
''* without limitation the rights to use, copy, modify, merge, publish,
''* distribute, sublicense, and/or sell copies of the Software, and to permit
''* persons to whom the Software is furnished to do so, subject to the
''* following conditions:
''*
''* The above copyright notice and this permission notice shall be included
''* in all copies or substantial portions of the Software.
''*
''* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
''* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
''* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
''* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
''* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
''* OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
''* THE USE OR OTHER DEALINGS IN THE SOFTWARE.
''***************************************************************************