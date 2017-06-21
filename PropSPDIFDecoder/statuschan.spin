''***************************************************************************
''* Channel Status Subchannel Decoder for S/PDIF Decoder
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
OBJ
  hw:           "hardware"

VAR
  long  blockcounter            ' Block counter for statistics (0=none yet)
  byte  chanstatblock[192/8]    ' 192 bits = 24 bytes

PUB Start(par_psubframe)
'' par_psubframe (pointer to long): pointer to live updated SPDIF subframe 
''

  gpsubframe := par_psubframe
  if (glockid == -1)
    glockid := locknew
    cognew(@channelstatusdec, @blockcounter)

PUB GetBlock(par_dest)
'' par_dest (pointer to bytes): pointer to store a copy of the block

  repeat while lockset(glockid)

  result := blockcounter
  
  bytemove(par_dest, @chanstatblock[0], constant (192/8))

  lockclr(glockid)

DAT
                        org 0
channelstatusdec
                        ' Store pointers to object-specific spin data 
                        mov     pblockcounter, par
                        mov     pchanstat, par
                        add     pchanstat, #4

                        ' Backup the instruction that rotates the bit into the data
                        mov     restore_ins_rcrbits1, ins_rcrbits1

                        ' This loop reads subframes and stores the subchannel bit
                        ' from each subframe into consecutive bits in the cog.
                        ' When it encounters the start of a new block, it gets the lock
                        ' and copies the entire stored data to the hub before it starts
                        ' storing the data for the next block (so the hub is always a
                        ' block behind).
loop
                        ' Synchronize with the subframe clock and get the subframe
                        waitpeq zero, mask_PRADET                        
                        waitpne zero, mask_PRADET
                        rdlong  subframe, gpsubframe

                        ' If the subframe is the first in a block, copy the current data
                        ' to the hub and reset the counters.
                        test    subframe, mask_BLKDET wc ' Test for first subframe in block
              if_c      call    #saveblocktohub

                        ' Skip subframes that aren't marked for the left channel
                        ' TODO: ignore entire block if L/R don't match?              
                        test    subframe, mask_LCHAN wc
              if_nc     jmp     #loop                                     

                        ' If the subframe has odd parity, skip it (this will discard
                        ' the block).
                        test    subframe, subframe wc
              if_c      jmp     #loop
                        
                        ' Extract the channel status bit and insert it into the current
                        ' longword. Bits get inserted with a Rotate with Carry Right
                        ' so that the first bit is stored in the lsb, and the last bit
                        ' is stored in the msb. That way when we transfer the longword
                        ' to the hub, the least significant BYTE is stored as the first
                        ' byte in the Spin array (the Propeller is little-endian).
                        '
                        ' The RCR instruction is updated below to change the destination
                        ' address. The code that saves the block to the hub restores the
                        ' instruction to the initial state.
                        test    subframe, mask_CHANSTAT wc ' Read channel status bit
ins_rcrbits1            rcr     bits, #1                ' Rotate it into the bits

                        ' If we just stored the last bit of a block, replace the
                        ' instruction that stores the bits with a NOP so that if the
                        ' signal doesn't have a BLKDET flag in the next subframe (which
                        ' shouldn't happen), the stored data will not overrun the array.
                        sub     sfcounter, #1 wz
              if_z      mov     ins_rcrbits1, #0

                        ' Count down bits. If all bits for the current longword are done,
                        ' move on to the next longword in the array                                                
                        djnz    bitcounter, #loop       ' Next bit

                        mov     bitcounter, #32
                        jmp     #loop
                                                
                        add     ins_rcrbits1, d1
                        jmp     #loop

                        ' This code takes the lock from the spin code and stores the
                        ' data from this block into the hub, but only if an entire block
                        ' came in.
saveblocktohub
                        ' Check if an entire block was received
                        ' If not, discard block and return
                        tjnz    sfcounter, #nextblock

                        ' Increase the block counter in the hub
                        add     blkcounter, #1
                        wrlong  blkcounter, pblockcounter

                        ' Init copy loop
                        movd    ins_wrlongbitsp, #bits  ' NOTE: WRLONG has cog addr in DEST
                        mov     copydest, pchanstat     ' NOTE: WRLONG has hub addr in SRC
                        mov     copycounter, #(192/32)  ' Counter for number of longs     
                                                   
                        ' Set the lock
                        ' Make sure the lock isn't in use by the spin code
lockloop
                        lockset glockid wc
              if_c      jmp     #lockloop

                        ' Copy the bits to the hub
copyloop
ins_wrlongbitsp         wrlong  bits, copydest
                        add     copydest, #4            ' Next longword in hub
                        add     ins_wrlongbitsp, d1     ' Next longword in cog
                        djnz    copycounter, #copyloop                         

                        ' Clear the lock                        
                        lockclr glockid

                        ' Reinitialize counters for the next block                                                                                                                        
nextblock                        
                        mov     ins_rcrbits1, restore_ins_rcrbits1
                        mov     bitcounter, #32
                        mov     sfcounter, #192

                        ' Return from the subroutine
                        ' At this point, the first subframe of the next block can be
                        ' stored
saveblocktohub_ret      ret                         
                        
' Parameters
pblockcounter           long    0                       ' Hub address to block counter
pchanstat               long    0                       ' Hub address to output array
gpsubframe              long    0                       ' Pointer to live updated subframe
glockid                 long    -1                      ' Lock for communication

' Variables
subframe                long    0                       ' Actual subframe value read from hub        
blkcounter              long    0                       ' Local block counter
sfcounter               long    192                     ' Subframe countdown
bitcounter              long    32                      ' Stored bits per longword countdown
copydest                long    0                       ' Destination address during copy                        
copycounter             long    0                       ' Used during copying to hub
restore_ins_rcrbits1    long    0                       ' Backup for bit inserting instruction                        
bits                    long    0[192/32]               ' Gathered up bits

' Constants
zero                    long    0
d1                      long    1 << 9
mask_PRADET             long    hw#mask_PRADET
mask_BLKDET             long    |< hw#sh_BLKDET
mask_LCHAN              long    |< hw#sh_LCHAN
mask_CHANSTAT           long    |< hw#sh_CHANSTAT     
                        
                        
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