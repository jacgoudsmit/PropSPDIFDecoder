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
  sh_AH                        '/

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
  sh_LH                         '/

  sh_Q0                         '\
  sh_QH                         '/ Output format

  sh_I0                         '\
  sh_IH                         '/ Input format


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
  sh_TH                        '/
  
  sh_RESET20                    '\
  sh_RESET21                    '| Reserved
  sh_RESET22                    '/

  sh_P0                         '\
  sh_P1                         '|
  sh_P2                         '| Pin number for TXD
  sh_P3                         '|
  sh_PH                         '/

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


                        '======================================================================
                        ' Initialization
                        
fasttx
                        ' Read the address of the command long
                        rdlong  pcmd, PAR
                        jmp     #readcmd


                        '======================================================================
                        ' Item loop
                        '                        
                        ' The following code processes items (bytes, words, longs) until the
                        ' command is done
                        ' The instructions are modified depending on input mode, output mode,
                        ' length parameter and runtime state.
                         
itemloop
                        ' Load an item
                        ' This is changed to the appropriate RD... instruction
ins_load                rdbyte  x, address wz

                        ' Take action if the item was zero
                        ' If count was initialized to nonzero, this is changed to a NOP  
ins_zeroitem  if_z      jmp     #endcmd

                        ' Process the item
                        ' This is replaced depending on the output format
ins_process             jmpret  (0), #(0)

                        ' Bump source address
                        add     address, bytesperitem
                        
                        ' Next item
                        ' If the length parameter was zero, the djnz is replaced by a jmp
ins_nextitem            djnz    count, #itemloop


                        '======================================================================
                        ' Command finished
                        '
                        ' Execution lands here when a command is done
                        
endcmd
                        wrlong  zero, pcmd              ' Clear command code                        

                        ' Reset first-item flag
                        mov     firstitem, #1
                        

                        '======================================================================
                        ' Get and process incoming command

readcmd
                        rdlong  command, pcmd wz
              if_z      jmp     #readcmd

                        ' Save address
                        mov     address, command
                        'shr     address, #sh_A0
                        and     address, mask_address
                        
                        mov     count, command
                        shr     count, #sh_L0
                        and     count, mask_count wz                        

                        ' If count is zero, stop at a zero-item, and loop unconditionally
                        ' If count is nonzero, use a DJNZ to count down the items
              if_z      mov     ins_zeroitem, ins_nop
              if_z      mov     ins_nextitem, ins_djnzitemloop
              if_nz     mov     ins_zeroitem, ins_ifjmpend
              if_nz     mov     ins_nextitem, ins_jmpitemloop                                               

                        ' Get output mode
                        mov     outmode, command
                        shr     outmode, #sh_Q0
                        and     outmode, mask_outmode                        
                        
                        ' Get input mode
                        ' Select the output mode initializer jump table based on whether the
                        ' input mode is %00 or not.
                        mov     inmode, command
                        shr     inmode, #sh_I0
                        and     inmode, mask_inmode wz  ' Z=1 for character/reset mode
              if_z      movs    ins_outmode_tab, jmptab_outmode_zero
              if_nz     movs    ins_outmode_tab, jmptab_outmode_nonzero               

                        ' Execute input mode initializer based on jump table 
                        mov     x, inmode
                        add     x, #jmptab_inmode
                        jmp     x

                        ' All input mode initializers jump to this location.
                        ' Execute output mode initializer based on jump table
                        ' The table that is used depends on whether the input mode is
                        ' %00 or not.
end_inmode_init
                        mov     x, outmode
ins_outmode_tab         add     x, #(0)                 ' Modified depending on inmode 
                        jmp     x


                        '======================================================================
                        ' Input-mode initializers
                        '
                        ' These must run before the output initializers because they depend on
                        ' each other's data.

                        '----------------------------------------------------------------------                        
                        ' II=%00: Init for processing characters
                        ' Note, in case of a reset, the character initializer is useless,
                        ' but it's more efficient to just execute them here, with a penalty
                        ' of wasted clock cycles when resetting, as compared to doing an
                        ' extra check to skip this when we're initializing string mode.
                        '
                        ' Input mode for characters is identical to input for bytes,
                        ' so fall through to the initializer for bytes
init_char

                        '----------------------------------------------------------------------
                        ' II=%01: Init for processing bytes
init_byte
                        mov     bytesperitem, #1        ' Each iteration goes to next byte
                        mov     numdecdigits, #3        ' "255" is worst case dec value
                        mov     unusedbits, #24         ' Each item starts with 24 unused bits
                        mov     ins_load, ins_rdbyte    ' Load data as byte
                        jmp     #end_inmode_init

                        '----------------------------------------------------------------------                        
                        ' II=%10: Init for processing words
init_word
                        mov     bytesperitem, #2        ' Each iteration goes to next word
                        mov     numdecdigits, #5        ' "65535" is worst case dec value
                        mov     unusedbits, #16         ' Each item starts with 16 unused bits
                        mov     ins_load, ins_rdword    ' Load data as word
                        jmp     #end_inmode_init

                        '----------------------------------------------------------------------
                        ' II=%11: Init for processing longs
init_long
                        mov     bytesperitem, #4        ' Each iteration goes to next word
                        mov     numdecdigits, #10       ' "4294967295" is worst case dec value
                        mov     unusedbits, #0          ' Each item starts with 0 unused bits
                        mov     ins_load, ins_rdlong    ' Load data as long
                        jmp     #end_inmode_init


                        '======================================================================
                        ' Output mode initializers for input mode %00

                        '----------------------------------------------------------------------
                        ' QQ=%00 for II=00: Init for printing a string         
init_char_string
                        mov     ins_process, ins_call_char
                        jmp     #itemloop


                        '----------------------------------------------------------------------                        
                        ' QQ=%01 for II=00: Init for printing a filtered string 
init_char_filter       
                        mov     ins_process, ins_call_filter ' Filter byte, send to output
                        jmp     #itemloop                                       


                        '----------------------------------------------------------------------                        
                        ' QQ=%10 for II=00: Init bit rate and pin number
init_reset
                        mov     bittime, command
                        shr     bittime, #sh_T0
                        and     bittime, mask_bittime 

                        mov     x, command
                        shr     x, #sh_P0
                        and     x, mask_pinnum
                        mov     bitmask, #1
                        shl     bitmask, x
                        mov     OUTA, bitmask
                        mov     DIRA, bitmask

                        ' All done here                        
                        jmp     #endcmd


                        '----------------------------------------------------------------------
                        ' Q=%11 for II=00: Init bit rate and pin number, enable CTS handshake
                        '
                        ' This is not implemented because the Prop plug doesn't have CTS broken
                        ' out anyway.
                        ' Basically, to implement this, the bit mask for the CTS pin should be
                        ' initialized here and the main loop should check wait for that pin to
                        ' be high before sending a byte in the main loop.
init_res_cts
                        jmp     #init_reset             ' Just handle this as a normal reset


                        '======================================================================
                        ' Output mode initializers for input modes unequal to 00
                        '
                        ' These must be run after the input mode initializers because they
                        ' depend on variables being initialized there.
                        
                        '----------------------------------------------------------------------                                                                                           
                        ' QQ=%00 for II <> 00: Init for generating decimal
init_dec                                                                                                                         
                        mov     ins_process, ins_call_dec ' Generate decimal number
                        mov     digits, bytesperitem
                        shl     digits, #3              ' 8 digits per byte       
                        jmp     #itemloop
                        

                        '----------------------------------------------------------------------                                                                                           
                        ' QQ=%01 for II <> 0: Init for generating signed decimal
init_sgd                                                                                                                         
                        mov     ins_process, ins_call_sgd ' Generate decimal number
                        jmp     #itemloop


                        '----------------------------------------------------------------------                                                                                           
                        ' QQ=%10 for II <> 0: Init for generating hexadecimal
init_hex                                                                                                                         
                        mov     ins_process, ins_call_hex ' Generate hexadecimal
                        mov     digits, bytesperitem
                        shl     digits, #1              ' 2 digits per byte 
                        jmp     #itemloop


                        '----------------------------------------------------------------------                                                                                           
                        ' QQ=%11 for II <> 0: Init for generating binary
init_bin
                        mov     ins_process, ins_call_bin ' Generate binary
                        mov     digits, bytesperitem
                        shl     digits, #3              ' 8 digits per byte
                        jmp     #itemloop


                        '======================================================================
                        ' Processing subroutine for filtered characters (II=00 QQ=01)
                        '
                        ' If the input character is non-printable, it's replaced by a period
                        ' character '.'. This is useful e.g. in hexdumps
                                                
proc_filter
                        cmp     x, #$20 wc              ' If value is below space
              if_nc     cmp     v_127, x wc             ' ... or value is equal/above 127
              if_c      mov     x, #"."                 ' ... Change value to period '.'
                        ' Fall through to string processor

              
                        '======================================================================
                        ' Processing subroutine for characters (II=00 QQ=00)
                        '
                        ' This sends the character in x directly to the serial output
                        ' Other processing functions also call this to print the character
                        ' in x.
                        '
                        ' x is destroyed.
               
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


                        '======================================================================
                        ' Process a decimal number (II=nonzero QQ=00)
                        '
                        ' This converts the number in x to BCD using the "double dabble"
                        ' algorithm, then it prints each of the significant digits to ASCII
                        ' and prints them.
                        '
                        ' The "double dabble" algorithm is roughly as follows:
                        ' 1. Initialize the BCD digits buffer to zeroes.
                        ' 2. Repeat the following steps (bytesperitem * 8) times:
                        '    2.1 Rotate the msb of the binary bits into the lsb of the BCD
                        '        digits.
                        '    2.2 Check each BCD digit from left (msd) to right (lsd), If the
                        '        digit is 5 or higher, add 3 to the digit (without carry)
                        ' 4. Go to step 2
                                                 
proc_dec
                        call    #separator

                        ' This is the entry point from the signed decimal code
proc_dec_no_separator                        
                        ' We will print digits from the msb down, but all significant
                        ' bits are at the lsb of the item. So shift the bits up as necessary.
                        shl     item, unusedbits

                        ' Clear the decimal digit buffer
                        mov     decdigitcount, #numdecdigits
                        movd    ins_cleardec, #decdigits

ins_cleardec            mov     decdigits, #0                        
                        add     ins_cleardec, d1
                        djnz    decdigitcount, #ins_cleardec                        

                        ' Init digit counter from number of significant bits
                        ' Note, in this case the counter counts input bits, not output digits
                        mov     digitcount, digits     
dec_shiftloop
                        test    item, v_8000_0000h wc   ' C=1 if bit=1

                        ' Rotate bit into the decimal digits

                        ' Init pointers
                        movd    ins_dec_rcl, #decdigits
                        movd    ins_dec_cmpsub, #decdigits

                        mov     decdigitcount, #numdecdigits
dec_rotateloop                                                
ins_dec_rcl             rcl     decdigits, #1           ' Rotate C into digit
ins_dec_cmpsub          cmpsub  decdigits, #$10 wc      ' C = old bit 3, bit 3 is now reset
                        add     ins_dec_rcl, d1         ' Bump pointer for rcl instruction
                        add     ins_dec_cmpsub, d1      ' Bump pointer for cmpsub instruction

                        djnz    decdigitcount, #dec_rotateloop

                        ' Add 3 to all digits that are 5 or higher

                        ' Init pointers                         
                        movd    ins_dec_cmp, #decdigits
                        movd    ins_dec_add, #decdigits

dec_add3loop
ins_dec_cmp             cmp     decdigits, #5 wc
ins_dec_add   if_nc     add     decdigits, #3
                        add     ins_dec_cmp, d1
                        add     ins_dec_add, d1

                        djnz    decdigitcount, #dec_add3loop                             

                        ' Next bit
                        shl     item, #1
                        djnz    digitcount, #dec_shiftloop

                        ' At this point, the decimal digits contain a BCD representation of the
                        ' original item value, padded with zeroes
                        ' Find the first significant digit first, then print the digits

                        ' Init pointers
                        mov     x, numdecdigits
                        add     x, #(decdigits - 1)
                        movd    ins_dec_test, x
                        movd    ins_dec_mov, x

                        ' Init count
                        sub     numdecdigits, #1        ' Always print at least 1 digit

                        ' Trim digits
dec_trimloop
ins_dec_test            test    decdigits, #$F wz       ' Z=1 if digit is zero
              if_z      sub     ins_dec_test, d1        ' Trim one digit
              if_z      djnz    numdecdigits, #dec_trimloop

                        ' Print rest of the digits

                        add     numdecdigits, #1        ' Always print at least 1 digit
dec_printloop
ins_dec_mov             mov     x, decdigits            ' Get digit
                        add     x, #"0"                 ' Make ASCII
                        call    #proc_char              ' Print it
                        
                        sub     ins_dec_mov, d1         ' Next digit
                        djnz    numdecdigits, #dec_printloop                        

                        ' All done
proc_sgd_ret
proc_dec_ret            ret


                        '======================================================================
                        ' Process a signed decimal number (II=nonzero QQ=01)
                        '
                        ' If the value in x is negative, send a '-' and negate the value.
                        ' Then print the resulting unsigned value.

proc_sgd
                        call    #separator

                        test    item, v_8000_0000h wz   ' Z=1 if positive
              if_nz     mov     x, #"-"                 ' If negative, print "-"
              if_nz     call    #proc_char
              if_nz     neg     item, item              ' Negate item

                        ' Continue as if item is unsigned
                        jmp     proc_dec_no_separator
                        


                        '======================================================================
                        ' Process a hexadecimal number (II=nonzero QQ=10)
                        '
                        ' Iterate the value in x, converting each group of 4 bits into a
                        ' hexadecimal digit, and print each digit, msd first.
proc_hex
                        call    #separator

                        ' We will print hex digits from the msb down, but all significant
                        ' bits are at the lsb of the item. So shift the bits up as necessary.
                        shl     item, unusedbits

                        ' Init digit counter
                        mov     digitcount, digits

hexdigitloop                        
                        ' Get a hex digit
                        mov     x, item
                        shr     x, #24
                        cmpsub  x, #10 wc               ' C=0 for "0-9", 1 for "A-F"
              if_nc     add     x, #"0"
              if_c      add     x, #"A"

                        ' Print the digit
                        call    #proc_char

                        ' Repeat for all digits
                        shl     item, #4
                        djnz    digitcount, #hexdigitloop    
                         
proc_hex_ret            ret


                        '======================================================================
                        ' Process a binary number (II=nonzero QQ=11)
                        '
                        ' Iterate the value in x, converting each bit into a binary digit, and
                        ' print each digit, msd first.
proc_bin
                        call    #separator

                        ' We will print binary digits from the msb down, but all significant
                        ' bits are at the lsb of the item. So shift the bits up as necessary.
                        shl     item, unusedbits

                        ' Init digit counter
                        mov     digitcount, digits

bindigitloop                        
                        ' Get a bit
                        test    item, v_8000_0000h wc   ' C=1 if bit is 1
              if_nc     mov     x, #"0"
              if_c      mov     x, #"1"

                        ' Print the digit
                        call    #proc_char

                        ' Repeat for all digits
                        shl     item, #1
                        djnz    digitcount, #bindigitloop    
                         
proc_bin_ret            ret                                                                                                                        


                        '======================================================================
                        ' Init numeric item from x and print separator if necessary
separator
                        ' Copy value before it's destroyed
                        mov     item, x

                        ' Check if this is the first item being printed
                        ' If not, print a space
                        ' The cmpsub instruction resets the flag
                        cmpsub  firstitem, #1   ' Z=1 if first item
              if_nz     mov     x, #" "
              if_nz     call    #proc_char                                        

separator_ret           ret

                                                                        
' Constants
zero                    long    0
v_127                   long    127
v_8000_0000h            long    $8000_0000
d1                      long    (|< 9)            
mask_address            long    (|< (1 + sh_AH - sh_A0)) - 1
mask_count              long    (|< (1 + sh_LH - sh_L0)) - 1
mask_bittime            long    (|< (1 + sh_TH - sh_T0)) - 1
mask_pinnum             long    (|< (1 + sh_PH - sh_P0)) - 1
mask_inmode             long    (|< (1 + sh_IH - sh_I0)) - 1
mask_outmode            long    (|< (1 + sh_QH - sh_Q0)) - 1
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

' Jump table for input modes ("II" values)
jmptab_inmode           long    init_char               ' II=%00: char or reset
                        long    init_byte               ' II=%01: byte
                        long    init_word               ' II=%10: word
                        long    init_long               ' II=%11: long

' Jump table for output modes (where "II" is zero)
jmptab_outmode_zero     long    init_char_string        ' QQ=%00: character or string
                        long    init_char_filter        ' QQ=%01: filtered character or string
                        long    init_reset              ' QQ=%10: reset pin/baud rate
                        long    init_res_cts            ' QQ=%11: reset pin/baud rate, w/CTS
                         
' Jump table for output modes (where "II" is nonzero)                        
jmptab_outmode_nonzero  long    init_dec                ' QQ=%00: decimal
                        long    init_sgd                ' QQ=%01: signed decimal
                        long    init_hex                ' QQ=%10: hexadecimal
                        long    init_bin                ' QQ=%11: binary                                 

' Uninitialized variables
x                       res     1                       ' Multi-use variable
item                    res     1                       ' Used for non-character items
pcmd                    res     1                       ' Address of cmd passed through PAR
command                 res     1                       ' Current command
inmode                  res     1                       ' Input mode
outmode                 res     1                       ' Output mode                                
address                 res     1                       ' Address from the command
bytesperitem            res     1                       ' How much to add to source address
unusedbits              res     1                       ' Number of bits to discard
digits                  res     1                       ' Number of hex/bin digits to generate
digitcount              res     1                       ' Digit counter while printing item
decdigitcount           res     1                       ' Counter for decimal digits
numdecdigits            res     1                       ' Maximum number of decimal digits
count                   res     1                       ' Number of items left to process
firstitem               res     1                       ' Used as flag to print separators
bitmask                 res     1                       ' Bitmask for output
bittime                 res     1                       ' Time between bits, in clock cycles
shiftcount              res     1                       ' Shift counter in bit loop
time                    res     1                       ' Time keeper in bit loop
decdigits               res     10                      ' Buffer for decimal digits

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