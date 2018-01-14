''***************************************************************************
''* Serial data transmitter
''* Copyright (C) 2018 Jac Goudsmit
''* Based on tx.spin from obex.parallax.com/object/619, (C) 2011 Barry Meaker
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
'' This module implements a fast serial transmitter. It cannot receive, and
'' it doesn't implement flow control (the code has been prepared for CTS
'' handshaking but this is not implemented; The Propeller Plug can't do it).
''
'' A cog is dedicated to transmitting data on a single pin, based on a
'' command that's passed through a single longword. That way, it can easily
'' be used from Spin as well as PASM. Note: The command is backwards
'' compatible with Barry Meaker's version of the code: if you simply put a
'' longword with a hub address between $0001 and $FFFF in the command, the
'' cog will print a nul-terminated buffer as before.  
''
'' Each command to the PASM code is a single longword that has the following
'' format:
''
'' %II_QQ_LLLL_LLLL_LLLL_AAAA_AAAA_AAAA_AAAA
''  --                                       Input format (see below)
''     --                                    Output format (see below)
''        -------------                      Length (0=stop at value 0)
''                      -------------------  Hub addr for data (0=nop)
''
'' When resetting, the command is formatted as follows:
'' %001C_PPPPP_RRR_TTTT_TTTT_TTTT_TTTT_TTTT
''     -                                     Enable CTS on pin+1
''       -----                               Pin number for TXD
''             ---                           Reserved
''                 ------------------------  Bit time in cycles
''
'' The II format bits determine how the cog reads data from the hub.
'' It can read values in bytes, words or longs, or it can read bytes as
'' characters that are sent directly to the serial output.
''
'' II=%00 read chars (length is in bytes)
''    %01 read bytes (length is in bytes)
''    %10 read words (length is in words)
''    %11 read longs (length is in longs)
''
'' The QQ format bits determine how the cog formats the output. The meaning
'' of the bits depends on whether the II bits are set to 00 (character input)
'' or other modes. For non-character output, when printing multiple values,
'' values are separated by spaces.
''
'' For II=0:
'' QQ=%00 send characters directly to output
''    %01 send printable characters directly to output, replace others by '.'
''    %10 reset cog
''    %11 (reserved for CTS handshaking)
''          
'' For II=not 0:
'' QQ=%00 send unsigned decimal 
''    %01 send signed decimal ('-' prefix for negative, no prefix otherwise)
''    %10 send hexadecimal padded with 0
''    %11 send binary padded with 0 
''
'' Examples:
'' - To print a nul-terminated string at address ABCD, use code $0000ABCD
'' - To print a $123 byte buffer at address ABCD, use code $0123ABCD
'' - To print a single character at address ABCD, use $0001ABCD
'' - To print a hexdump of a nul-terminated string at address ABCD: $6000ABCD
'' - To print a hexdump of a $3EF byte buffer at ABCD: $63EFABCD
'' - To print the unsigned decimal value of the longword at ABCD: $C001ABCD
''
'' Value 0 for the command longword is used as a special value to represent
'' "nothing to do". That value would normally correspond to a command to
'' "Print nul-terminated string stored at address $0000" which is not likely
'' to be needed anyway. In a pinch, it can be easily worked around: test if
'' the byte at $0000 is equal to $00. If not, print the character at $0000
'' followed by the zero-terminated string at $0001.  
'' 
'' Following are the comments from Barry Meaker's original code. Things have
'' been optimized since he did his measurements, so things work even faster
'' now. The maximum bit rate is 4Mbps (the bit loop takes 20 clock cycles).
'' The byte cycle has a much bigger influence on throughput and depends on
'' the input and output format configuration in the command.
''

{{
' This routine is optimized to transmit a zero-terminated string
'
' FullDuplexSerial.spin uses spin to send each byte to the assembly language
' routine for transmission. The result is that at 921600 baud each byte only takes
' 10.85uS, but when sending a string, the overall rate is about 64uS per byte
' Including the initial spin call to strsize, FullDuplexSerial.spin takes about 5.2mS
' to transmit a 77 byte string.
'
' This routine uses an assembly language routine to scan and transmit the
' bytes in the zero terminated string. Transmitting the same 77 byte string at
' 921600 baud takes about 1mS.
'
'-----------------REVISION HISTORY-----------------
' v1.0 - 2011-04-27 Original version by Barry Meaker
' v2.0 - 2018-01-06 Various enhancements by Jac Goudsmit
}}
CON

  ' Bits in the command word for non-reset commands
  #0
  
  sh_A0                         '\
  sh_A1                         '|
  sh_A2                         '|
  sh_A3                         '|
                                '|
  sh_A4                         '|
  sh_A5                         '|
  sh_A6                         '|
  sh_A7                         '|
                                '| Hub address for (first) item
  sh_A8                         '|
  sh_A9                         '|
  sh_A10                        '|
  sh_A11                        '|
                                '|
  sh_A12                        '|
  sh_A13                        '|
  sh_A14                        '|
  sh_A15                        '/

  sh_L0                         '\
  sh_L1                         '|
  sh_L2                         '|
  sh_L3                         '|
                                '|
  sh_L4                         '|
  sh_L5                         '| Number of items to process
  sh_L6                         '| (0=stop when there is an item with value 0
  sh_L7                         '|
                                '|
  sh_L8                         '|
  sh_L9                         '|
  sh_L10                        '|
  sh_L11                        '/

  sh_Q0                         '\
  sh_Q1                         '/ Output format

  sh_I0                         '\
  sh_I1                         '/ Input format


  ' Bits in the command word for the reset command
  #0
  
  sh_T0                         '\
  sh_T1                         '|
  sh_T2                         '|
  sh_T3                         '|
                                '|
  sh_T4                         '|
  sh_T5                         '|
  sh_T6                         '|
  sh_T7                         '|
                                '|
  sh_T8                         '|
  sh_T9                         '| Bit time in clock cycles
  sh_T10                        '|
  sh_T11                        '|
                                '|
  sh_T12                        '|
  sh_T13                        '|
  sh_T14                        '|
  sh_T15                        '|
                                '|
  sh_T16                        '|
  sh_T17                        '|
  sh_T18                        '|
  sh_T19                        '/
  
  sh_RESET20                    '\
  sh_RESET21                    '| Reserved
  sh_RESET22                    '/

  sh_P0                         '\
  sh_P1                         '|
  sh_P2                         '| Pin number for TXD
  sh_P3                         '|
  sh_P4                         '/

  sh_C                          ' Enable CTS on pin+1
  sh_RESET29                    ' Always 1 for reset                        
  sh_RESET30                    ' Always 0 for reset                        
  sh_RESET31                    ' Always 0 for reset
                                        
  ' Input types
  mask_IN_CHAR = (%00 << sh_I0) ' Read characters (or reset)
  mask_IN_BYTE = (%01 << sh_I0) ' Read bytes
  mask_IN_WORD = (%10 << sh_I0) ' Read words
  mask_IN_LONG = (%11 << sh_I0) ' Read longs

  ' Output types when NOT using mask_IN_CHARS
  mask_OUT_DEC = (%00 << sh_Q0) ' Unsigned decimal
  mask_OUT_SGD = (%01 << sh_Q0) ' Signed decimal                        
  mask_OUT_HEX = (%10 << sh_Q0) ' Hexadecimal, 2/4/8 digits padded with zeroes
  mask_OUT_BIN = (%11 << sh_Q0) ' Binary, 8/16/32 digits padded with zeroes 

  ' Output types when using mask_IN_CHARS (or without a mask_IN value)
  mask_STRING  = (%00 << sh_Q0) ' Print string
  mask_FILTER  = (%01 << sh_Q0) ' Print filtered string
  mask_RESET   = (%10 << sh_Q0) ' Reset
  'mask_RES_CTS = (%11 << sh_Q0) ' Reset with CTS handshaking
  
  ' Additional values that might come in useful
  mask_SINGLE  = (1 << sh_L0)   ' Single item (character or longword)                            
  
  
VAR

  long cog            ' Cog ID + 1
  long value          ' Buffer for printing a single decimal or hex value
  long cmd            ' Command
  
PUB Start(par_txpin, par_baudrate)
'' Starts serial transmitter in a new cog.
''
'' par_txpin      (long): Pin number (0..31)
'' par_baudrate   (long): Number of bits per second (clkfreq/20 .. clkfreq/$F_FFFF)
''
'' Returns (ptr to long): Address of command, or 0 on failure                  

  ' Stop the cog if it's running
  Stop

  ' Set the command to reset with the given pin number and baud rate
  cmd := mask_RESET | (par_txpin << sh_L0) | (clkfreq / par_baudrate)
  
  if (cog := cognew(@fasttx, @cmd) + 1)
    result := @cmd

PUB Stop
'' Stop the tx cog, if any.

  if cog
    cogstop(cog - 1)

PUB Wait
'' Wait until previous command is done.
''
'' This can be used to ensure that buffers that are used in commands are not
'' overwritten while the cog is processing them. 

  repeat until cmd == 0  

PUB Str(data_ptr)
'' Send string
''
'' The parameter can either be a 16-bit address of a nul-terminated string, or
'' a command composed in spin, as described in the documentation at the top of
'' this source file.                      

  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command for string
  cmd := data_ptr

PUB Tx(par_byte)
'' Send byte

  value := par_byte
  
  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command to print one byte
  cmd := @value | mask_SINGLE

PUB Dec(par_value)
'' Send an unsigned decimal number

  value := par_value

  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command to print one decimal value
  cmd := @value | constant(mask_IN_LONG | mask_OUT_DEC | mask_SINGLE)  
  
PUB SignedDec(par_value)
'' Send a signed decimal number

  value := par_value

  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command to print one signed decimal value
  cmd := @value | constant(mask_IN_LONG | mask_OUT_SGD | mask_SINGLE)

PUB Hex(par_value)
'' Send a hexadecimal number

  value := par_value

  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command to print one hex value
  cmd := @value | constant(mask_IN_LONG | mask_OUT_HEX | mask_SINGLE)

PUB Bin(par_value)
'' Send a binary number

  value := par_value

  ' Wait until any previous command has finished
  repeat until cmd == 0

  ' Set command to print one binary value
  cmd := @value | constant(mask_IN_LONG | mask_OUT_BIN | mask_SINGLE)

DAT

                        org  0

                        ' The lowest locations of cog memory are used as a jump table once the
                        ' main loop is running.
                        ' The JMP instructions aren't actually executed, they're just a neat
                        ' reminder of what these locations are used for.
fasttx
                        jmp     #init                   ' 00_00=char/string (Replaced below)
                        jmp     #init_char_filter       ' 00_01=char/filtered string
                        jmp     #init_reset             ' 00_10=reset baud rate, pin number
                        jmp     #init_res_cts           ' 00_11=reset with CTS
                        jmp     #init_byte_dec          ' 01_00=byte/unsigned decimal                                   
                        jmp     #init_byte_sgd          ' 01_01=byte/signed decimal
                        jmp     #init_byte_hex          ' 01_10=byte/hexadecimal
                        jmp     #init_byte_bin          ' 01_11=byte/binary
                        jmp     #init_word_dec          ' 10_00=word/unsigned decimal
                        jmp     #init_word_sgd          ' 10_01=word/signed decimal
                        jmp     #init_word_hex          ' 10_10=word/hexadecimal
                        jmp     #init_word_bin          ' 10_11=word/binary
                        jmp     #init_long_dec          ' 11_00=long/unsigned decimal
                        jmp     #init_long_sgd          ' 11_01=long/signed decimal
                        jmp     #init_long_hex          ' 11_10=long/hexadecimal
                        jmp     #init_long_bin          ' 11_11=long/binary
init
                        movs    0, #init_char_string

                        ' Read the address of the command long
                        rdlong  pcmd, PAR
                        jmp     #readcmd

                        ' Process an item
itemloop
                        ' Load an item
                        ' This is changed to the appropriate RD... instruction
ins_load                rdbyte  x, address wz

                        ' Take action if it was zero
                        ' If count was initialized to nonzero, this is changed to a NOP  
ins_zeroitem  if_z      jmp     #endcmd

                        ' Process the item
                        ' This is replaced depending on the output format
ins_process             jmpret  0, #0

                        ' TODO: add code here to print separator for dec/sgd/hex/bin
                        
                        ' Next item
                        add     address, bytesperitem
ins_nextitem            djnz    count, #itemloop

                        ' Finish a command by writing zero to the command long.
endcmd
                        wrlong  zero, pcmd                        

                        ' Get command
readcmd                 rdlong  x, pcmd wz
              if_z      jmp     #readcmd

                        ' Save address and length
                        mov     address, x
                        mov     count, x
                        shl     count, #( 31 - sh_L11)
                        shr     count, #((31 - sh_L11) + sh_L0) wz

                        ' If count is zero, stop at a zero-item
              if_z      mov     ins_zeroitem, ins_nop
              if_z      mov     ins_nextitem, ins_djnzitemloop
              if_nz     mov     ins_zeroitem, ins_ifjmpend
              if_nz     mov     ins_nextitem, ins_jmpitemloop                                               

                        ' Get input mode and jump to that mode's initialization via the jump
                        ' table.
                        shr     x, #sh_I0   
                        jmp     x


                        
                        ' Initialization for each input/output mode


                        ' IIQQ=%0000: Init for printing a string         
init_char_string
                        mov     ins_process, ins_call_char
                        call    #init_char
                        jmp     #itemloop

                        
                        ' IIQQ=%0001: Init for printing a filtered string 
init_char_filter       
                        mov     ins_process, ins_call_filter ' Filter byte, send to output
                        call    #init_byte
                        jmp     #itemloop                                       

                        
                        ' IIQQ=%0010: Init bit rate and pin number
init_reset
                        mov     bittime, x 
                        shl     bittime, #( 31 - sh_T19)
                        shr     bittime, #((31 - sh_T19) + sh_T0)

                        shl     x, #( 31 - sh_P4)
                        shr     x, #((31 - sh_P4) + sh_P0)
                        mov     bitmask, #1
                        shl     bitmask, x
                        mov     OUTA, bitmask
                        mov     DIRA, bitmask
                        
                        jmp     #endcmd

                        
                        ' IIQQ=%0011: Init bit rate and pin number with CTS handshaking
init_res_cts
                        jmp     #init_reset             ' Not implemented, do regular reset


                        ' IIQQ=%0100: Init for printing byte as decimal value                        
init_byte_dec
                        call    #init_byte
                        jmp     #init_dec


                        ' IDQQ=%0101: Init for printing byte as signed decimal
init_byte_sgd
                        call    #init_byte
                        jmp     #init_sgd


                        ' IDQQ=%0110: Init for printing byte as hex                        
init_byte_hex
                        call    #init_byte
                        jmp     #init_hex                        


                        ' IDQQ=%0111: Init for printing byte as binary
init_byte_bin
                        call    #init_byte
                        jmp     #init_hex


                        ' IIQQ=%1000: Init for printing word as decimal value                        
init_word_dec
                        call    #init_word
                        jmp     #init_dec


                        ' IDQQ=%1001: Init for printing word as signed decimal
init_word_sgd
                        call    #init_word
                        jmp     #init_sgd


                        ' IDQQ=%1010: Init for printing word as hex                        
init_word_hex
                        call    #init_word
                        jmp     #init_hex                        


                        ' IDQQ=%1011: Init for printing word as binary
init_word_bin
                        call    #init_word
                        jmp     #init_hex


                        ' IIQQ=%1100: Init for printing long as decimal value                        
init_long_dec
                        call    #init_long
                        jmp     #init_dec


                        ' IDQQ=%1101: Init for printing long as signed decimal
init_long_sgd
                        call    #init_long
                        jmp     #init_sgd


                        ' IDQQ=%1110: Init for printing long as hex                        
init_long_hex
                        call    #init_long
                        jmp     #init_hex                        


                        ' IDQQ=%1111: Init for printing long as binary
init_long_bin
                        call    #init_long
                        jmp     #init_hex


                        ' IDQQ=%00xx: Init for processing characters
init_char
                        mov     bytesperitem, #1        ' Each iteration goes to next byte
                        mov     ins_load, ins_rdbyte    ' Load data as byte
init_char_ret           ret                                       

                        
                        ' IDQQ=%01xx: Init for processing bytes
init_byte
                        mov     bytesperitem, #1        ' Each iteration goes to next byte
                        mov     ins_load, ins_rdbyte    ' Load data as byte
init_byte_ret           ret                                       

                        
                        ' IDQQ=%10xx: Init for processing words
init_word
                        mov     bytesperitem, #2        ' Each iteration goes to next word
                        mov     ins_load, ins_rdword    ' Load data as word
init_word_ret           ret


                        ' IDQQ=%11xx: Init for processing longs
init_long
                        mov     bytesperitem, #4        ' Each iteration goes to next word
                        mov     ins_load, ins_rdlong    ' Load data as long
init_long_ret           ret


                        ' IDQQ=%xx00 (where xx <> 0): Init for generating decimal
init_dec                                                                                                                         
                        mov     ins_process, ins_call_dec ' Generate decimal number
                        mov     digits, #0              ' Process output as 0-terminated string
                        jmp     #itemloop
                        

                        ' IDQQ=%xx01 (where xx <> 0): Init for generating signed decimal
init_sgd                                                                                                                         
                        mov     ins_process, ins_call_sgd ' Generate decimal number
                        mov     digits, #0              ' Process output as 0-terminated string
                        jmp     #itemloop


                        ' IDQQ=%xx10 (where xx <> 0): Init for generating hexadecimal
init_hex                                                                                                                         
                        mov     ins_process, ins_call_hex ' Generate hexadecimal
                        mov     digits, bytesperitem
                        shl     digits, #1              ' 2 digits per byte 
                        jmp     #itemloop


                        ' IDQQ=%xx11 (where xx <> 0): Init for generating binary
init_bin
                        mov     ins_process, ins_call_bin ' Generate binary
                        mov     digits, bytesperitem
                        shl     digits, #3              ' 8 digits per byte
                        jmp     #itemloop


                        ' Process a character
proc_char
                        ' TODO: Wait until CTS is set here, if enabled
                        
                        or      x, #$100                ' Add in a stop bit
                        shl     x, #1                   ' Shift to create a start bit

                        mov     shiftcount, #10         ' 1 start, 8 data, 1 stop
                        mov     time, CNT               ' Read the current count
                        add     time, #9                ' Value 9 immediately ends waitcnt

                        ' When execution falls into the bit loop below, the first instruction
                        ' must be a waitcnt. The wait time of 9 cycles in the instruction above
                        ' accomplishes that the waitcnt immediately exits.
                                                 
tx_loop                 waitcnt time, time              ' Wait until time for this bit
                        shr     x, #1  wc               ' Shift the bit to transmit into carry
                        muxc    OUTA, bitmask           ' Set the output
                        djnz    shiftcount, #tx_loop    ' Loop if more bits to transmit
                        waitcnt time, bittime          'make sure stop bit at least 1 bit time                                                             

                        ' At this point, the stop bit is still on the line. That's what we want

proc_filter_ret
proc_char_ret
                        ret


                        ' Process a character and filter it
proc_filter
                        cmp     x, #$20 wc              ' If value is below space
              if_nc     cmp     v_127, x wc             ' ... or value is equal/above 127
              if_c      mov     x, #46                  ' ... Change value to period '.'
                        jmp     #proc_char              ' Process further as a regular char


                        ' Process a decimal number
proc_dec
                        ' Not implemented yet

proc_dec_ret            ret


                        ' Process a signed decimal number
proc_sgd
                        ' Not implemented yet

proc_sgd_ret            ret


                        ' Process a hexadecimal number
proc_hex
                        ' Not implemented yet

proc_hex_ret            ret


                        ' Process a binary number
proc_bin
                        ' Not implemented yet

proc_bin_ret            ret                                                                                                                        
                        
                                                
' Constants
zero                    long    0
v_127                   long    127
ins_rdbyte              rdbyte  x, address wz
ins_rdword              rdword  x, address wz
ins_rdlong              rdlong  x, address wz
ins_nop                 nop
ins_ifjmpend  if_z      jmp     #endcmd
ins_djnzitemloop        djnz    count, #itemloop
ins_jmpitemloop         jmp     #itemloop
ins_call_char           call    #proc_char
ins_call_filter         call    #proc_filter
ins_call_dec            call    #proc_dec
ins_call_sgd            call    #proc_sgd
ins_call_hex            call    #proc_hex
ins_call_bin            call    #proc_bin                  

' Uninitialized variables
x                       res     1                       ' Multi-use variable                       
pcmd                    res     1                       ' Address of cmd passed through PAR
address                 res     1                       ' Address from the command
bytesperitem            res     1                       ' How much to add to source address
digits                  res     1                       ' Number of hex/bin digits to generate
count                   res     1                       ' Number of items left to process
bitmask                 res     1                       ' Bitmask for output
bittime                 res     1                       ' Time between bits, in clock cycles
shiftcount              res     1                       ' Shift counter in bit loop
time                    res     1                       ' Time keeper in bit loop

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