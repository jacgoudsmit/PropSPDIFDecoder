''***************************************************************************
''* Subchannel Decoder for S/PDIF Decoder
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
{{
This module can be used to demultiplex one of the subchannels of the S/PDIF
signal.
}}
CON
  con_retrycount = 8            ' Retry this many times to get lock
                          
OBJ
  hw:           "hardware"

VAR
  ' Data needed by Spin only
  long  mycogid                 ' Cog ID + 1
  long  blockcounter            ' Block counter for statistics (0=none yet)
  byte  data[384/8]             ' Data storage

  ' Data needed by PASM as well as Spin. Must be in same order as DAT area
  long  psubframe               ' Pointer to live updating subframe
  long  pdata                   ' Pointer to data array
  long  leftonly                ' Nonzero=skip subframes for right chan
  long  pblockcounter           ' Pointer to block counter in hub            
  long  mask                    ' Mask to test for 
  long  lockid                  ' Lock ID + 1 for synchronization

PUB Start(par_psubframe, par_bit, par_leftonly)
'' Starts the decoder
''
'' par_psubframe (pointer to long): pointer to live updated SPDIF subframe
'' par_pdata (pointer to array of bytes): array to update from subchannel
'' par_bit (long): bit number of subchannel (see hardware module)
'' par_leftonly: (boolean long) Handle only the left-channel subframes 
'' 
'' result (long): lock ID to use for accessing the data, -1 if start failed
''
'' The data array should have enough space for the data: 192 bits (24 bytes)
'' for the Channel Status, or 384 bits (48 bytes) for the User Data.
'' 

  ' Check if we're already running. If so, stop before restarting.
  Stop

  ' Init local variables  
  psubframe     := par_psubframe
  pdata         := @data
  leftonly      := par_leftonly
  pblockcounter := @blockcounter
  mask          := |< par_bit

  ' Allocate a lock            
  lockid := locknew + 1

  ' Start the cog if the lock allocation was successful
  if (lockid <> 0)
    mycogid := cognew(@subchannelcog, @psubframe) + 1

  ' Clean up if we couldn't allocate a cog or lock
  if (mycogid == 0) or (lockid == 0)
    Stop

  ' Return with lock ID, -1=failed    
  return lockid - 1

PUB Stop
'' Stops the decoder if it's running
''

  if (mycogid <> 0)
    cogstop(mycogid - 1)
    mycogid := 0

  if (lockid <> 0)
    lockret(lockid - 1)
    lockid := 0

PUB Get(par_pdata, par_prevblocknum) | n
'' Copy a block of data to the data pointer, but only if the current
'' data block is not equal to the given block number
''
'' par_pdata (pointer to bytes): destination pointer for data
'' par_prevblocknum (long): Don't store if block number matches this (0=don't use)
''
'' result (long): block counter for the current block
''

  repeat
    repeat while lockset(lockid - 1)

    if (par_prevblocknum == 0) or (par_prevblocknum <> blockcounter)
      quit

    ' Caller already got this block, clear the lock
    lockclr(lockid - 1)

    ' Hold off for a little while so the PASM code can take it
    ' The timing is probably not very critical    
    waitcnt(10_000 + cnt) ' 

  if (leftonly)
    n := constant(192/8)
  else
    n := constant(384/8)
    
  bytemove(par_pdata, @data, n)
      
  result := blockcounter

  lockclr(lockid - 1)

DAT
                        org 0
subchannelcog
                        ' Copy spin data to cog
                        mov     copyptr, par
                        mov     copycounter, #(parameters_end - parameters)

initloop
ins_initrdlong          rdlong  parameters, copyptr
                        add     copyptr, #4
                        add     ins_initrdlong, d1
                        djnz    copycounter, #initloop

                        ' Initialize calculated constants
                        test    gleftonly, gleftonly wz ' Z=1 left+right Z=0 left only
              if_z      mov     ins_jmpleft, #0         ' Change JMP to NOP        
                         
                        ' Backup the instruction that rotates the bit into the data
                        mov     restore_ins_rcrbits1, ins_rcrbits1
                        mov     blkcounter, #0

                        ' Initialize the counters
                        call    #nextblock                        

                        ' This loop reads subframes and stores the requested bit
                        ' from each subframe into consecutive bits in the cog buffer.
                        ' When it encounters the start of a new block, it tries to get
                        ' get the lock and if successful, copies the entire buffer to the hub
                        ' before it starts storing the data for the next block.
                        ' That means the hub is always a block behind but it only gets
                        ' complete blocks, not partial ones.
loop
                        ' Synchronize with the subframe clock and get the subframe
                        ' We start processing the subframe after the biphase cog is done
                        ' processing a preamble.
                        waitpne zero, mask_PRADET       ' Got a preamble                        
                        waitpeq zero, mask_PRADET       ' End of preamble                        
                        rdlong  subframe, gpsubframe

                        ' If the subframe is the first in a block, copy the current data
                        ' to the hub and reset the counters before continuing
                        test    subframe, mask_sf_BLKDET wc
              if_c      call    #saveblocktohub

                        ' Track the number of subframes that have been read in this
                        ' block.
                        ' We need to do this here: the subroutine call above may
                        ' reinitialize the counter before we update it, and the
                        ' test and jump below may restart the loop if we're skipping
                        ' right channel subframes.
                        ' By putting this instruction here, we can always use 384 for the
                        ' initialization of the subframe counter.                        
                        sub     sfcounter, #1 wz

                        ' Skip subframes that aren't marked for the left channel if desired.
                        ' The conditional JMP is changed to a NOP during initialization if
                        ' we need all subframes
                        test    subframe, mask_sf_LCHAN wc
ins_jmpleft   if_nc     jmp     #loop                                     

                        ' Extract the requested bit and insert it into the current
                        ' longword. Bits get inserted with a Rotate with Carry Right
                        ' so that the first bit is stored in the lsb, and the last bit
                        ' is stored in the msb. That way when we transfer the longword
                        ' to the hub, the least significant BYTE is stored as the first
                        ' byte in the Spin array (the Propeller is little-endian).
                        '
                        ' The RCR instruction is updated below to change the destination
                        ' address. Also, when we've done all the subframes of a block,
                        ' the instruction is replaced by a NOP to prevent going out of
                        ' bounds on the array in the cog. The code below that saves the
                        ' block to the hub restores the instruction to the initial state.
                        test    subframe, gmask wc      ' Read channel bit
ins_rcrbits1            rcr     bits, #1                ' Rotate it into the bits

                        ' If we just stored the last bit of a block, replace the
                        ' instruction that stores the bits with a NOP so that if the
                        ' signal doesn't have a BLKDET flag in the next subframe (which
                        ' shouldn't happen), the stored data will not overrun the array.
              if_z      mov     ins_rcrbits1, #0

                        ' Count down bits. If all bits for the current longword are done,
                        ' move on to the next longword in the array                                                
                        djnz    bitcounter, #loop       ' Next bit

                        mov     bitcounter, #32
                        add     ins_rcrbits1, d1
                        jmp     #loop

                        '----------------------------------------------------------------------
                        
                        ' This code takes the lock from the spin code and stores the
                        ' data from this block into the hub, but only if an entire block
                        ' came in.
saveblocktohub
                        ' Increase the block counter in the cog.
                        ' If we end up not being able to copy this block to the hub for some
                        ' reason, the discontinuity can be detected by other cogs that use
                        ' the hub data.
                        add     blkcounter, #1

                        ' Check if an entire block was received
                        ' If not, discard block and return
                        tjnz    sfcounter, #nextblock

                        ' Init copy loop
                        movd    ins_wrlongbitsp, #bits  ' NOTE: WRLONG has cog addr in DEST
                        mov     copyptr, gpdata         ' Init hub address
                        mov     copycounter, #(384/32)  ' Counter for number of longs
                        test    gleftonly, gleftonly wz ' Z=0 left only
              if_nz     shr     copycounter, #1         ' Half as much data                             
                                                   
                        ' Set the lock
                        ' Make sure the lock isn't in use by the spin code
                        ' We retry a limited number of times before giving up
                        mov     sfcounter, #con_retrycount ' reusing frame counter here                                                
lockloop
                        lockset glockid wc              ' C=0 if we got the lock
              if_c      djnz    sfcounter, #lockloop    ' Retry a few times
              if_c      jmp     #nextblock              ' Time-out, skip this block 

                        ' Copy the bits to the hub
copyloop
ins_wrlongbitsp         wrlong  bits, copyptr
                        add     copyptr, #4             ' Next longword in hub
                        add     ins_wrlongbitsp, d1     ' Next longword in cog
                        djnz    copycounter, #copyloop                         

                        ' Update the block counter in the hub
                        wrlong  blkcounter, gpblockcounter

                        ' Clear the lock                        
                        lockclr glockid

                        ' Reinitialize counters for the next block                                                                                                                        
nextblock                        
                        mov     ins_rcrbits1, restore_ins_rcrbits1
                        mov     bitcounter, #32
                        mov     sfcounter, #384
                        
nextblock_ret                        
saveblocktohub_ret      ret                         
                        
' Constants
zero                    long    0
d1                      long    1 << 9
mask_PRADET             long    hw#mask_PRADET
mask_XORIN              long    hw#mask_XORIN
mask_sf_BLKDET          long    |< hw#sf_BLKDET
mask_sf_LCHAN           long    |< hw#sf_LCHAN

' Parameters (must be in same order as VAR area
parameters
gpsubframe              res     1                       ' Pointer to live updating subframe
gpdata                  res     1                       ' Pointer to data array
gleftonly               res     1                       ' Nonzero=skip subframes for right chan
gpblockcounter          res     1                       ' Pointer to block counter
gmask                   res     1                       ' Mask to test for 
glockid                 res     1                       ' Lock ID + 1 for synchronization
parameters_end

' Variables
subframe                res     1                       ' Actual subframe value read from hub        
blkcounter              res     1                       ' Local block counter
sfcounter               res     1                       ' Subframe countdown
bitcounter              res     1                       ' Stored bits per longword countdown
copyptr                 res     1                       ' Destination address during copy                        
copycounter             res     1                       ' Used during copying to hub
restore_ins_rcrbits1    res     1                       ' Backup for bit inserting instruction                        
bits                    res     (384/32)                ' Gathered up bits

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