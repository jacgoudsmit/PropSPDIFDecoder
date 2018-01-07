''***************************************************************************
''* Serial data transmitter
''* Copyright (C) 2018 Barry Meaker and Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''
'' This module implements a fast serial transmitter. It cannot receive, and
'' it doesn't implement flow control.
''
'' A cog is dedicated to transmitting data on a single pin, based on a
'' command that's passed through a single longword. That way, it can easily
'' be used from Spin as well as PASM.
''
'' Following are the comments from Barry Meaker's original code. Things have
'' been optimized since he did his measurements, so things might work even
'' faster now. On the other hand, the new features may also have a small
'' negative impact on performance.
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

  NULL = 0
  
VAR

  long cog         'Cog ID
  long tx_pin      'transmit pin
  long bit_time    'bit time
  long bufptr      'pointer to string pointer  
  long strptr      'string pointer
  byte bytebuf     'place to hold bytes for transmission
  byte bytebufterm 'terminating zero for byte transmission
  
PUB start(txpn, baudrate) : success
{{Start tx process in new cog; return True if successful.

Parameters:
  txpn       - The transmit pin
  baudrate   - The speed of the transmission
}}
  stop
  tx_pin := |<txpn
  bit_time := clkfreq / baudrate
  bufptr := @strptr
  bytebufterm := 0
  success := (cog := cognew(@fasttx, @tx_pin) + 1)


PUB stop
''Stop the tx process, if any.

  if cog
    cogstop(cog~ - 1)

PUB str(data_ptr)
'' Send string                    

    repeat until strptr == NULL  'wait until any previous string has been transmitted
    strptr := data_ptr           'transmit the new string


PUB tx(txbyte)
'' Send byte

  bytebuf := txbyte
  str(@bytebuf)

PUB dec(value) | i, x

'' Print a decimal number

  x := value == NEGX                                                            'Check for max negative
  if value < 0
    value := ||(value+x)                                                        'If negative, make positive; adjust for max negative
    tx("-")                                                                     'and output sign

  i := 1_000_000_000                                                            'Initialize divisor

  repeat 10                                                                     'Loop for 10 digits
    if value => i                                                               
      tx(value / i + "0" + x*(i == 1))                                          'If non-zero digit, output digit; adjust for max negative
      value //= i                                                               'and digit from value
      result~~                                                                  'flag non-zero found
    elseif result or i == 1
      tx("0")                                                                   'If zero digit (or only digit) output it
    i /= 10                                                                     'Update divisor


PUB hex(value, digits)

'' Print a hexadecimal number

  value <<= (8 - digits) << 2
  repeat digits
    tx(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))


PUB bin(value, digits)

'' Print a binary number

  value <<= 32 - digits
  repeat digits
    tx((value <-= 1) & 1 + "0")

DAT

                        org  0

fasttx                  mov     tmp, par                    'get the shared RAM address where the
                        rdlong  txpin, tmp                  'transmit pin is
                        add     tmp, #4
                        rdlong  bittime, tmp                'get the bit time
                        add     tmp, #4
                        rdlong  buf_ptr, tmp                'get the buffer pointer

init                    mov     pin_val, txpin              'set the bit for txpin high
                        mov     dira, pin_val               'set the direction of txpin to output
                        mov     outa, pin_val               'set txpin high
                            
done                    mov     byte_ptr, #NULL
                        wrlong  byte_ptr, buf_ptr           'start with a NULL in the string pointer

main_loop               rdlong  byte_ptr, buf_ptr wz        'read the string pointer
                if_z    jmp     #main_loop                  'loop until it's not NULL


byte_loop               rdbyte  tx_data, byte_ptr wz         'read the byte to transmit
                if_z    jmp     #done                        'if it's a NULL, we're done

                        or      tx_data, #$100              'add in a stop bit
                        shl     tx_data, #1                 'shift to create a start bit

                        mov     bit_cnt, #10                '1 start, 8 data, 1 stop
                        mov     wait_time, cnt              'read the current count
                        add     wait_time, #bytetime        'add a small time to it

tx_loop                 waitcnt wait_time, bittime          'wait until time for this bit
                        shr     tx_data, #1  wc             'shift the bit to transmit into carry
                        muxc    outa, pin_val
                        djnz    bit_cnt, #tx_loop           'loop if more bits to transmit             

                        ' At this point, the stop bit is still on the line. That's okay.

                        add     byte_ptr, #1                'point to the next byte
                        jmp     #byte_loop

'
' Initialized data
'
bytetime                long    25                      ' Extra clocks between bytes (min=9)                           

'
' Uninitialized data
'
pin_val                 res     1
tmp                     res     1
txpin                   res     1
bittime                 res     1
buf_ptr                 res     1
byte_ptr                res     1
tx_data                 res     1
bit_cnt                 res     1
wait_time               res     1

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