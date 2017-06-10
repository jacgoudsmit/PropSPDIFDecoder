''***************************************************************************
''* Bi-phase Decoder for S/PDIF
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
{{
Schematic:
 
 
          3.3V                          
        10k|                         
           Z                         
      100n | |\       100R    |\          Inverters  are 74HC04
o)--+--||--o-| >o--+--|\|--o--| >o--+     NAND ports are 74HC00
    |      | |/    |       |  |/    |
    Z      Z  A    |       =   B    |
 75R|   10k|       |   100p|        |
   gnd    gnd      |      gnd       |
                   |                |
                   |                |    ___
                   |                +---|   \
                   |                |   |    )o--+
                   +--------------------|___/    |
                   |                |            |
                   |                |            |   ___
                 -----            -----          +--|   \
                 \   /            \   /             |    )o---> XORIN
                  \ /              \ /           +--|___/
                   o                o            |
                   |                |    ___     |
                   |                +---|   \    |
                   |                    |    )o--+
                   +--------------------|___/
 

The above schematic was what I tested with. Alternatively you can use
the following but that hasn't been tested:

 
          3.3V                          
        10k|                         
           Z         ___                       ___
      100n |  +----\\   \       100R    +----\\   \        All ports
o)--+--||--o--+    ||    >---+--|\|--o--+    ||    >--+    are 74HC86  
    |      |     +-//___/    |       |     +-//___/   |    (XOR)
    Z      Z     |           |       =     |          |
 75R|   10k|     |           |   100p|     |          |
   gnd    gnd   gnd          |      gnd   gnd         |
                             |                        |
                             |                        |
                             |   +--------------------+
                             |   |     ___
                             |   +---\\   \
                             |       ||    >----> XORIN
                             +-------//___/

 
The input is connected to inverter A via a small circuit that provides the
correct input impedance, a capacitor that decouples the DC, and a voltage
divider that pulls the voltage to the center of inverter A's sensitivity
range. Inverter A amplifies the signal from 0.5Vpp to full CMOS digital
(and inverts it) so it's basically a 1-bit A/D converter.
 
The output of inverter A is fed into inverter B via an RC network,
which act as a delay (in addition to the propagation delay of
inverter B).
 
The rest of the circuit forms an equivalence circuit (i.e. an inverted
XOR port, the inversion compensates for the inverted output signal of
inverter B): As long as the input signal doesn't change, the output of
inverter B is always the inverse of channel A and the XORIN output is
LOW. But when a positive or negative edge appears at the input, port
B changes polarity slightly  later than port A, so for a short
time, the outputs of ports A and B are equal and XORIN goes high during
that time, as illustrated below: 
 
         +-------+       +---+   +-------+   +---+           +---+   +--
A out    |   0   |   0   |   1   |   0   |   1   |     P     |   1   |
         +       +-------+   +---+       +---+   +-----------+   +---+
 
         --+       +-------+   +---+       +---+   +-----------+   +---+
B out      |   0   |   0   |   1   |   0   |   1   |     P     |   1   |
           +-------+       +---+   +-------+   +---+           +---+   +
                                                   
         +-+     +-+     +-+ +-+ +-+     +-+ +-+ +-+         +-+ +-+ +-+
XORIN    | |     | |     | | | | | |     | | | | | |         | | | | | |
         + +-----+ +-----+ +-+ +-+ +-----+ +-+ +-+ +---------+ +-+ +-+ +
 
The R/C values of the delay circuit are not very critical as long as the
delay time is longer than one Propeller clock pulse (12.5ns) and shorter
than the time it takes to execute one instruction (4 clock cycles i.e.
50ns). According to my oscilloscope, the 100 Ohm, 100 pF combination
generates pulses on XORIN that are about 30ns wide so that's perfect.
There should be no need to adjust any of the resistors, and it's not
necessary to have an oscilloscope or logic analyzer to use the circuit. 
 
I noticed there is a bit of jitter on the width of the positive pulses
on XORIN. This should not be a problem because the code only waits for
the positive edges and ignores the negative edges.
 
The project supports stereo PCM data between 32kHz and 48kHz sample
frequency (Fs), stereo only(*). There are 32 bits in each subframe, and two
subframes in each frame (one for each channel) so the rate at which the
bits are encoded is between 2.048 and 3.072 MHz.
 
The shortest time period that we have to measure (let's call it "t")
is the time that the input signal stays at the same level during the
transmission of a "1" bit. This corresponds to half the time of one
encoded bit, and conversely the duration of one encoded bit is 2*t.
 
Here's an overview of some timing values.      
 
+--------+-----------+-------+-------+-------+--------+--------+--------+
| Sample | Bit rate  | t     | 2*t   | 3*t   | 1*t    | 2*t    | 3*t    |
| Freq.  | (64 * Fs) | (ns)  | (ns)  | (ns)  | (clks) | (clks) | (clks) |
+========+===========+=======+=======+=======+========+========+========|
| 48,000 | 3,072,000 | 162.8 | 325.5 | 488.3 | 13.0(*)| 26.0(*)| 39.1   |
| 44,100 | 2,822,000 | 177.2 | 354.4 | 531.5 | 14.2   | 28.4   | 42.5   |
| 32,000 | 2,048,000 | 244.1 | 488.3 | 732.4 | 19.5   | 39.1   | 58.6   |
+--------+-----------+-------+-------+-------+--------+--------+--------+

With most Propeller instructions taking 4 cycles of 12.5ns each, the
software has about 6 instructions time to decode and process each bit in
the incoming data stream. We use this fact to our advantage: all
timing-critical loops have a single WAITPxx instruction to synchronize
with the XORIN input, and exactly 5 additional instructions to do their
processing. That way, processing an incoming bit always takes a minimum
of about 325ns: the WAITPxx instruction takes at least 6 cycles and the
other 5 instructions take 4 cycles each.

If the data stream is slower, the WAITPxx instructions will ensure that
the Propeller stays in synch with the input signal. In other words, the
Propeller stays busy processing stuff just short enough to be able to wait
for the next pulse on XORIN.

This is illustrated in the diagram below: The letters "P" indicate the
execution of an instruction that processes the data, and the letters "W"
indicate when a WAITPxx instruction tells the Propeller to wait until
the next positive edge of the XORIN input. The minimum of 6 instructions
processing time per input cycle effectively recovers the clock on the
input signal.

The next step is to extract the data from the input stream. To do this,
we program a timer to count positive edges on the XORIN input. Whenever
execution passes a WAITPxx instruction, we know that we're at the beginning
of a new bit in the stream. At that point, all the code needs to know to
decode the bit is:
* Is the edge counter odd or even now?
* Was the edge counter odd at the beginning of the previous bit?

If the oddness of the counter changed from odd to even or from even to
odd, there must have been only one flank in the signal, so the encoded bit
must have been a 0. If the oddness stayed the same (even to even, or odd
to odd), it means the encoded bit must have been a 1.

         +-+     +-+     +-+ +-+ +-+     +-+ +-+ +-+         +-+ +-+ +-+
XORIN    | |     | |     | | | | | |     | | | | | |         | | | | | |
         + +-----+ +-----+ +-+ +-+ +-----+ +-+ +-+ +---------+ +-+ +-+ +
 
Propeller PPPPPW..PPPPPW..PPPPPW..PPPPPW..PPPPPW..PPPPPW......PPPPPW..PP
 
Count     1       2       3   4   5       6   7   8           9   10  11
Oddness   ^ odd   ^ even  ^ odd   ^ odd   ^ even  ^ even      ^ odd   ^
Changed           ^ yes   ^ yes   ^ no    ^ yes   ^ no        ^ yes   ^
Decoded           ^ 0     ^ 0     ^ 1     ^ 0     ^ 1         ^ 0     ^
               
This method is amazingly reliable and very jitter-proof. It's much easier
and reliable to let a timer count edges (while the code does an exactly
predictable amount of work to make sure that it samples the timer count at
the exact right times) than it would be to write code to sample the input
to see if a second pulse arrived in the middle of a bit.

Another advantage of this method is that it's not necessary to reset the
timer/counter at the beginning of each bit. We only need to keep track of
whether the oddness changed between two bit times,

We also don't need to reset the counter at any time. In the event that the
code starts at the wrong time and executes a WAITPxx when the SECOND pulse
of a 1-bit comes in, it will straighten itself out very quickly (during the
next 0-bit). Then when the code encounters a preamble, it will of course
post the wrong data but the next subframe will be decoded correctly.

         +-+     +-+     +-+ +-+ +-+     +-+ +-+ +-+         +-+ +-+ +-+
XORIN    | |     | |     | | | | | |     | | | | | |         | | | | | |
         + +-----+ +-----+ +-+ +-+ +-----+ +-+ +-+ +---------+ +-+ +-+ +

Propeller             PPPPPW..PPPPPW......PPPPPW..PPPPPW......PPPPPW..PP
                      ^start  ^outofsync  ^back in sync!

So now we have an easy way to recover the bit clock (just execute a WAITPxx
followed by 5 instructions) and we have binary data from the input stream.

The next step is to figure out where one subframe ends and the next one
begins. This needs to be done in a separate cog because the biphase decoder
cog is just about as busy as it can be. Actually, the biphase decoder cog
depends on the preamble decoder cog to recognize the end of a subframe and
the beginning of the next subframe. The two cogs use external pins to
communicate with extreme timing accuracy.

Each subframe starts with a preamble which deliberately violates the
biphase encoding. There are three kinds of preambles: The B-preamble, the
M-preamble and the W-preamble. All preambles take 4 bit times (8*t) and
start with a pulse that's 3*t long. The total number of polarity changes
during a preamble is always 4.


             +-----------+   +---+           +---
B-Preamble:  |           |   |   |           |
(S/PDIF)    -+           +---+   +-----------+

            -+           +---+   +-----------+
or:          |           |   |   |           |
             +-----------+   +---+           +---

             +-+         +-+ +-+ +-+         +-+
XORIN:       | |         | | | | | |         | |
            -+ +---------+ +-+ +-+ +---------+ +-         




             +-----------+           +---+   +---
M-Preamble:  |           |           |   |   |
(S/PDIF)    -+           +-----------+   +---+

            -+           +-----------+   +---+
or           |           |           |   |   |
(inverted):  +-----------+           +---+   +---

             +-+         +-+         +-+ +-+ +-+
XORIN:       | |         | |         | | | | | |
            -+ +---------+ +---------+ +-+ +-+ +-         




             +-----------+       +---+       +---
W-Preamble:  |           |       |   |       |
(S/PDIF)    -+           +-------+   +-------+

            -+           +-------+   +-------+
or           |           |       |   |       |
(inverted):  +-----------+       +---+       +---

             +-+         +-+     +-+ +-+     +-+
XORIN:       | |         | |     | | | |     | |
            -+ +---------+ +-----+ +-+ +-----+ +-         




                        +-----------------+-+
PRADET:                 |                 | |
            ------------+                 +-+----

Preamble cog
events (see  ^1         ^2       ^3A ^3B  ^4^5
below)
            

* The B-Preamble starts a block of 192 frames (384 subframes). Blocks are
  needed to decode the subchannel data. The first subframe in a block is
  always for the left channel.
* The M-Preamble indicates the start of a subframe for the left channel
  that's not at the beginning of a block.
* The W-Preamble indicates the start of a subframe for the right channel.

The preamble detector uses two timers:
* One timer counts positive edges on the XORIN input (just like the
  biphase bit decoder cog)
* The other timer is set up as a Numerically Controlled Oscillator (NCO).
  It basically sets the PRADET (PReAmble DETect) output high after a little
  bit more than 2*t.

The main loop of the preamble detector cog keeps waiting for an incoming
pulse on XORIN (with the usual minimum waiting time of 5 instructions plus
WAITPxx so it doesn't get triggered by the pulses in the middle of the
1-bits in the stream). At the beginning of each loop, it stores the current
count of the edge counter to avoid "interference" from secondary incoming
pulses.

The main loop then checks the PRADET output to see if the long initial
pulse of a preamble came in. If PRADET is still low, it means less than
2*t have elapsed since the last reset (at event ^1). The code resets NCO so
that it's ready to go again for the current bit, and it starts the loop over.

If the PRADET output DID go high, we know that we're at event ^2 in the
diagram above. We don't reset the NCO (otherwise PRADET would go low again)
but we fall through to the second part of the preamble decoding code after
we add the value of 2 to the copy (more about this in a minute). 

The above takes exactly 5 instructions, so now we execute a WAITPxx to wait
for the next pulse close to 2*t after event ^2.

For preambles B or W, there is a phase change at event ^3 in the diagram,
but for preamble M, it takes until event ^4 before the next pulse arrives.
After the WAITPxx instruction, we're either at event ^3A or ^3B depending on
the length of the pulse. The code immediately checks the current edge
counter to test if it's equal to the previous counter value plus 2. If equal,
the current preamble is a B preamble and the Zero flag is set to 1.

Next, the code checks how many Propeller cycles have elapsed since the last
reset of the NCO (which happened at event ^1). Then it resets the NCO at
event ^4 or ^5.

If more than 5*t have elapsed, it must mean that a long pulse must have
followed after the initial pulse, so this must be an M preamble; if less
time elapsed, it must be a B or W preamble.

So now we know whether a B preamble came in and when an M preamble came in.
We do a one-instruction conditional change of the Carry flag so that it
is set not only when an M preamble came in but also when a B preamble came
in (i.e. whenever a subframe was for the left channel). The Zero flag and
the Carry flag are then posted onto the BLKDET (BLocK DETect) and LCHAN
(Left CHANnel) output pins. NOTE: we set the channel to 1 for the LEFT
(not right) channel, because it makes it possible to test the two pins
at the same time:
* If this is the first subframe of a block, both LCHAN and BLKDET are 1,
  so when testing both bits at the same time, Z=0 and C=0.
* If this is another left subframe (not at the start of a block), only
  the LCHAN pin is 1, so Z=0 and C=1.
* If this is a right channel subframe, Z=1 and C=0.
* The combination of Z=1 and C=1 is impossible.

It actually takes a little bit of extra time to decide whether to set the
BLKDET and LCHAN outputs high or low, but that's okay. Any cog that wants
to know what kind of subframe this is, won't need to know it until the end
of the subframe when the next preamble is detected.

So now we have a pulse on the PRADET output pin that goes from low to high
as soon as a preamble is detected (actually shortly before the end of the
long pulse at the beginning of the preamble, as a result of the preamble
NCO timer timing out), and goes low again just before the beginning of the
first significant data bit in the new subframe.

The biphase decoder cog rotates data bits into a longword that is used
to keep track of the bits in the subframe. It also checks if a preamble was
detected. If so, it jumps to the preamble code.

Because the biphase decoder has to check whether the oddness CHANGED, it
consists of two parts: one part that's executed if the count in the
previous loop was even, one part that's executed if the count in the
previous loop was odd.

Testing for the preamble (and bailing out if it was detected) and rotating
the oddnes into the result data turned out to be one cycle too many. The
solution was to only test for the preamble in the "even" loop (after all,
it can't occur in the "odd" loop anyway. But in a small case of "digital
irony", the carry flag in the "even" loop indicates when the encoded bit
was 1 (not zero) and in the "odd" loop, the carry flag corresponds to the
encoded bit. Because we don't have to test for the preamble in the "odd"
loop, we have one extra instruction of time to invert the bit after it's
added to the result data, so the code just ends up composing the data in
ones-complement of the actual value. And there is just enough time during
the preamble pulse to store that value in the hub. Any cog that wants to
pick up and process the value, will have to XOR it with $FFFF_FFFF first.

(*) I just realized that 48kHz may be a little too fast for the current
code: the time-critical loops consist of 5 regular instructions (4 clocks)
plus one WAITPxx instruction (minimum 6 clocks each) which is only 0.5ns
less than 2*t at 48kHz. I would have liked at least one clock cycle
(12.5ns) to spare but oh well. It's fairly easy to overclock a Propeller
and fix the problem, you'd just have to modify the timing constant for
the preamble detection. I may unroll the loops to make the code execute
faster so 48kHz will work with the common Propeller configuration, but
unrolling the loops (i.e. copy-pasting the instructions and removing the
JMP insturctions) makes editing a pain, so I won't do that at least until
I feel that I've gotten everything there is to get from the current code.
         
}}

OBJ
  hw:           "hardware"      ' Pin assignments and other global constants

VAR
  long  pradet_delay            ' Number of Propeller clocks in a preamble
                                
PUB biphasedec(par_delay, par_psample)
'' par_delay (long): Number of Propeller clocks in a preamble
'' par_psample (pointer to long): Location to store constantly updating sample

  pradet_delay := par_delay
  
  cognew(@decodebiphase, @par_psample)
  cognew(@detectpreamble, @pradet_delay)
  
DAT
             
                        org     0
decodebiphase
                        ' Set up timer A, used to count pulses on XORIN
                        mov     ctra, ctraval
                        mov     frqa, frqaval
                        mov     phsa, #0
                        jmp     #evenloop

preamble
                        ' Just after the detection of a preamble, test the pins
                        ' that tell us what kind of subframe this is.
                        ' The only possible combinations are:
                        ' * LCHAN is high and BLKDET is high (Left, first of block) -> C=0 Z=0
                        ' * LCHAN is high and BLKDET is low  (Left, not first)      -> C=1 Z=0
                        ' * LCHAN is low  and BLKDET is low  (Right)                -> C=0 Z=1
                        ' We encode those flags into the (inverted) data that we post to
                        ' the hub, in such a way that the parity remains the same. 
                        test    mask_BLKDET_LCHAN, ina wc,wz
                        muxz    data, mask_ENC_LCHAN    ' Make (inverted) bits 0 for left ch
              if_nz     muxnc   data, mask_ENC_BLKDET   ' Make (inverted) bits 0 for block det

                        wrlong  data, par               ' Write the data to the hub                             
                        waitpeq zero, mask_PRADET       ' Wait until end of preamble

                        ' Fall through to the even-loop of the decoder. We got here from
                        ' the even-loop and the preamble has 4 edges so the number should
                        ' be even again so this is the right thing to do.
                        '
                        ' Even in the worst case (where data comes in at the highest possible
                        ' speed and the WRLONG took 23 Propeller clocks), we should now be
                        ' just ahead of the pulse that marks the start of bit 4 of the
                        ' subframe.
                        '
                        ' The code will spend the following bit time to decode bit 3, but of
                        ' course this is not really necessary (it's always 0 because we're in
                        ' the even loop and the counter will end up being odd after the
                        ' initial WAITPxx), so in the future we may spend this first bit time
                        ' doing some housekeeping to store the data into a buffer that holds
                        ' all the data for an entire block.
evenloop
                        waitpne zero, mask_XORIN        ' Flank detected
                        test    one, phsa wc            ' C=1 if odd number of total flanks

                        test    mask_PRADET, ina wz     ' Z=0 if preamble detected
              if_nz     jmp     #preamble                    

                        ' NOTE: C=1 if the encoded bit was 0 (!)
                        '
                        ' We don't have time to manipulate the data in a such a way
                        ' that the bit that we rotate into it, corresponds to the encoded bit.
                        ' So instead, we simply rotate the carry flag into the result
                        ' and at the end of the subframe, all bits in the result are inverted.
                        rcr     data, #1                ' Rotate 1 if bit was 0, or vice versa 
                        
              if_nc     jmp     #evenloop               ' Go to even loop if total still even
              
oddloop
                        waitpne zero, mask_XORIN        ' Flank detected
                        test    one, phsa wc            ' C=1 if odd number of total flanks

                        ' NOTE: C=1 if the encoded bit was 1.
                        '
                        ' We didn't have time in the even-loop to inverse the carry
                        ' because we needed time to test for preamble there. Here we don't
                        ' have to test for preamble because the total number of bits in a
                        ' subframe is never odd (if it happens anyway, something is wrong).
                        ' Here we have a simple case of "the carry flag is the bit value"
                        ' and we have some time to invert the bit after we insert it, so at
                        ' the end of the subframe, all bits in the result are inverted.
                        rcr     data, #1                ' Rotate 1 if bit was 1, or vice versa
                        xor     data, v8000_0000        ' Invert the inserted bit
                        
              if_nc     jmp     #evenloop
                        jmp     #oddloop                                  

                        
                                      

ctraval                 long    (%01010 << 26) | hw#pin_XORIN ' Count pos. edges on XORIN                   
frqaval                 long    1

zero                    long    0
one                     long    1
v8000_0000              long    $8000_0000

                        ' The data stored here is the one's complement of the actual received
                        ' bits.
                        '
                        ' When valid data is received, the (unreversed) data always has even
                        ' parity when it's valid.
                        '
                        ' We encode the preamble type into the low 4 bits (see the hardware
                        ' module for encoding values), two bits at a time so that parity is
                        ' still always even.
                        '
                        ' We initialize the value with an odd-parity value to ensure that
                        ' it will be rejected by other code.
data                    long    $7FFF_FFFF

mask_XORIN              long    hw#mask_XORIN
mask_PRADET             long    hw#mask_PRADET
mask_BLKDET_LCHAN       long    hw#mask_BLKDET | hw#mask_LCHAN
mask_ENC_BLKDET         long    hw#mask_ENC_BLKDET
mask_ENC_LCHAN          long    hw#mask_ENC_LCHAN        

                        fit

DAT

                        org 0
detectpreamble
                        rdlong  dpcount, par
                        sub     dpresetb, dpcount
                        add     dpdetectm, dpcount
                        
                        ' Set up I/O
                        mov     dira, dpoutputmask                        
                        mov     outa, #0

                        ' Set up timer A, used to count pulses on XORIN
                        mov     ctra, dpctraval
                        mov     frqa, dpfrqaval
                        mov     phsa, dpreseta
                        
                        ' Set up timer B, used for preamble detection
                        mov     ctrb, dpctrbval
                        mov     frqb, dpfrqbval
                        mov     phsb, dpresetb

dploop
                        waitpne dpzero, dpmask_XORIN
                        mov     dpcount, phsa           ' Store flank count
                        test    dpmask_PRADET, ina wz   ' Z=0 if preamble                        
              if_z      mov     phsb, dpresetb          ' Reset timer B, 8 cycles too late

                        add     dpcount, #2             ' Expect 2 flanks for B preamble                        
              if_z      jmp     #dploop

                        ' Preamble detected.                        
                        waitpne dpzero, dpmask_XORIN
                        cmp     dpcount, phsa wz        ' Z=1 C=0 for B; otherwise M or W
                        cmp     dpdetectm, phsb wc      ' C=1 for M; otherwise B or W

                        ' Reset timer B at the exact same time (relative to the previous
                        ' pulse on XORIN) as usual, but use a reset-value of 0 to compensate
                        ' for the unusually long time we spend in the next few instructions.
                        ' Effectively, this switches the preamble detection off until the next
                        ' incoming pulse on XORIN, but that's okay, we're not expecting one
                        ' for a while anyway
                        mov     phsb, #0
                                                        
              if_z      cmp     dpzero, #1 wc           ' Set C if Z=1

                        ' At this point:
                        ' * Z=1 indicates B preamble
                        ' * C=0 indicates W preamble
                        ' * C=1 and Z=0 indicate M preamble
                        
                        ' Set the channel block detect and channel outputs.
                        ' This happens while the mew subframe is already on its way,
                        ' but these signals won't be needed by other cogs until
                        ' they get to the end of the current subframe anyway.
                        muxz    outa, dpmask_BLKDET                                              
                        muxc    outa, dpmask_LCHAN

                        ' NOTE: This would be a good time to read an updated value
                        ' of the timing constant from the hub (to make it possible to
                        ' run some sort of smart code that statistically determines what
                        ' it should be or to let the user influence it manually),
                        ' but if we replace it with the wrong value, we may never
                        ' get back here. I'll have to think about how to solve this
                        ' and also about how to detect when the input goes dead, which
                        ' gets everyone stuck in WAITPxx instructions.
                        
                        ' NOTE: we end this loop late. That's fine; there won't be another
                        ' preamble any time soon and timer B won't expire because we set
                        ' PHSB to a special value.
                        jmp     #dploop                        
                        
                        
dpctraval               long    (%01010 << 26) | hw#pin_XORIN ' Count pos. edges on XORIN                   
dpfrqaval               long    1
dpreseta                long    0

dpctrbval               long    (%00100 << 26) | hw#pin_PRADET
dpfrqbval               long    1
dpresetb                long    $8000_0000 + 8          ' Subtract 3*t cycles from this. "+8" compensates for resetting 2 instructions late

dpcount                 long    0

dpzero                  long    0
dpdetectm               long    $8000_0000              ' Add 3*t cycles to this

dpoutputmask            long    hw#mask_PRADET | hw#mask_BLKDET | hw#mask_LCHAN
dpmask_XORIN            long    hw#mask_XORIN
dpmask_PRADET           long    hw#mask_PRADET
dpmask_BLKDET           long    hw#mask_BLKDET
dpmask_LCHAN            long    hw#mask_LCHAN        

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