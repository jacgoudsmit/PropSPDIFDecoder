''***************************************************************************
''* S/PDIF Analyzer for Propeller
''* Copyright (C) 2021 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.
''***************************************************************************
''
''
{{
  This module generates serial output, compatible with a serial-to-USB
  converter such as the FTDI chips on the Parallax FLiP or Prop Plug.

  The original plan was to generate some sort of reduced version of the
  digital audio, combined with the subcode data, but unfortunately the
  FTDI chip doesn't provide enough bandwidth for a sustained data stream
  of 3 megabits per second. It does support 3mbps as baud rate but needs
  sufficient delay between the characters in order to not drop any data.

  So the current version of the module generates one byte per S/PDIF frame
  containing the subcode bits of the two subcode frames that were received.
  There is one byte per frame, and the frame is transmitted right after
  every right-channel subframe.

  Each byte contains the following bits:
  01VB_C021
  Where:
  0=Reserved        Always 0
  1=Reserved        Always 1
  V=Validity:       0=both channels were valid, 1=left or right are invalid
  B=Block:          1=Beginning of block (once every 192 frames)
  C=Channel Status  One bit of the Channel Status subchannel
  2=User Channel 2  One bit of the User Data subchannel (right channel)
  1=User Channel 1  One bit of the User Data subchannel (left channel)

  In the future, I hope to find a way to transfer all the data to a PC
  through a USB serial port, probably using different USB-to-serial
  hardware.
}}

OBJ
  hw:           "hardware"

VAR
  long  cog           ' Cog number + 1 when running

PUB Start(par_pin, par_psubframe)
'' Start a serial output cog
''
'' The cog generates serial output on the given pin number, at 3 megabits per
'' second (the highest speed that's supported by an FTDI FT232R USB-to-serial
'' chip, like the ones that are used on standard Propeller Plugs and the
'' Parallax Propeller FLiP module.
''
'' par_pin(long):               Pin number to transmit on (0-31)
'' par_psubframe(long ptr):     Location of subframe in hub memory

  Stop

  bittime := clkfreq / 3000000
  pinnum := par_pin
  gpsubframe := par_psubframe

  cog := cognew(@seroutcog, 0) + 1

PUB Stop
'' Stop a serial output cog

  if (cog)
    cogstop(cog - 1)
    cog := 0

DAT
                        org     0
seroutcog
                        ' Initialize the serial output

                        ' Store the pin number in the lowest bits of CTRA
                        ' This is safe if the pin number is valid (i.e. <32)
                        mov     CTRA, pinnum

                        ' Make sure PHSA never changes by itself
                        mov     FRQA, #0

                        ' In NCO mode, PHSA[31] is what controls the output
                        ' pin, so initialize it to 1 to simulate continuous
                        ' stop bits.
                        mov     PHSA, v8000_0000h

                        ' Calculate the bitmask for DIRA in x.
                        mov     x, #1
                        shl     x, CTRA

                        ' Activate the timer before setting DIRA
                        or      CTRA, ctra_NCO

                        ' Enable the output pin.
                        ' NOTE: when used with pin 30, a pullup resistor (on
                        ' the Prop Plug) has been pulling our TxD pin high.
                        ' By putting the above instructions in (roughly) this
                        ' order, the pin is never low until data is
                        ' generated.
                        ' NOTE: OUTA is assumed to be (and remain) 0.
                        mov     DIRA, x

                        jmp     #mainloop

                        ' Loop address entry point when handling left channel
mainloopleft
                        ' Init output byte
                        mov     outbyte, #$140          ' $100 for stop bit

                        ' Test for start of block
                        test    subframe, mask_sf_BLKDET wc
                        muxc    outbyte, mask_out_BLKDET

                        ' Get User subchannel
                        test    subframe, mask_sf_USERDATA wc
                        muxc    outbyte, mask_out_USERDATA1

                        ' Get Channel Status subchannel
                        test    subframe, mask_sf_CHANSTAT wc
                        muxc    outbyte, mask_out_CHANSTAT

                        ' Get Validity
                        test    subframe, mask_sf_VALIDITY wc
                        muxc    outbyte, mask_out_VALIDITY

                        ' Main loop
mainloop
                        ' Synchronize with the subframe clock and get the
                        ' subframe. We start processing the subframe after
                        ' the biphase cog is done processing a preamble.
                        waitpne zero, mask_PRADET       ' Got a preamble
                        waitpeq zero, mask_PRADET       ' End of preamble
                        rdlong  subframe, gpsubframe

                        ' If this frame is for the left channel, initialize
                        ' the byte we're going to send
                        test    subframe, mask_sf_LCHAN wc
              if_c      jmp     #mainloopleft

                        ' The current subframe is for the right channel
                        ' The output byte is already initialized with
                        ' data from the left channel

                        ' Get User subchannel
                        test    subframe, mask_sf_USERDATA wc
                        muxc    outbyte, mask_out_USERDATA2

                        ' No need to get the status subchannel,
                        ' it should be the same as the left channel

                        ' Check validity. Both channels must be valid (i.e. 0)
                        test    subframe, mask_sf_VALIDITY wc
              if_c      or      outbyte, mask_out_VALIDITY

                        ' Send byte
                        ' NOTE: the output byte must have bit 9 set so that
                        ' the serial output ends in a stop bit
                        mov     chr_time, CNT           ' Read the current count
                        add     chr_time, #9            ' Value 9 ends next waitcnt immediately

                        waitcnt chr_time, bittime       ' Never waits
                        mov     PHSA, outbyte           ' Bit 31 is 0: start bit
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 0
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 1
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 2
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 3
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 4
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 5
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 6
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 7
                        waitcnt chr_time, bittime       ' Wait for next bit
                        ror     PHSA, #1                ' Output original bit 8: stop bit
                        waitcnt chr_time, bittime       ' Ensure stop bit at least 1 bit time

                        jmp     #mainloop

                        ' Parameters
bittime                 long    0                       ' Initialized by Spin
pinnum                  long    0                       ' Initialized by Spin
gpsubframe              long    0                       ' Initialized by Spin

                        ' Constants
zero                    long    0
v8000_0000H             long    $8000_0000
ctra_NCO                long    (%00100 << 26)
mask_PRADET             long    hw#mask_PRADET
mask_sf_BLKDET          long    |< hw#sf_BLKDET
mask_sf_USERDATA        long    |< hw#sf_USERDATA
mask_sf_CHANSTAT        long    |< hw#sf_CHANSTAT
mask_sf_VALIDITY        long    |< hw#sf_VALIDITY
mask_sf_LCHAN           long    |< hw#sf_LCHAN
mask_out_USERDATA1      long    %0000_0001
mask_out_USERDATA2      long    %0000_0010
mask_out_CHANSTAT       long    %0000_1000
mask_out_BLKDET         long    %0001_0000
mask_out_VALIDITY       long    %0010_0000

                        ' Uninitialized data
x                       res     1
outbyte                 res     1
subframe                res     1
chr_time                res     1

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