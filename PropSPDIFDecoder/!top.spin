''***************************************************************************
''* S/PDIF Analyzer for Propeller
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''

CON

  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

OBJ

  hw:           "hardware"
  biphase:      "biphasedec"
  play:         "audioout"
  statuschan:   "statuschan"
  ser:          "FullDuplexSerial"

VAR
  long  sample
  byte  statusblock[192/8]
  
PUB main | i, j, count, newcount            

  'cognew(@logicprobe, 0)
  
  'play.Start(@sample)
  
  biphase.biphasedec(39, @sample)                        

  statuschan.Start(@sample)
    
  ser.Start(hw#pin_RX, hw#pin_TX, %0000, 115200)        'requires 1 cog for operation

  waitcnt(cnt + (1 * clkfreq))                          'wait 1 second for the serial object to start
  
  ser.Str(STRING("Hello, World!"))                      'print a test string
  ser.Tx($0D)                                           'print a new line

  ' Dump the status channel in Hex
  repeat
    newcount := statuschan.GetBlock(@statusblock[0])

    if (newcount <> count)
      count := newcount

      ser.Dec(count)
      ser.Tx(32)
          
      repeat i from 0 to constant(192/8) - 1
       ser.Hex(statusblock[i], 2)
       ser.Tx(32)

      ser.Tx($0D)

    waitcnt(10_000 + cnt)
             
    
  waitcnt(cnt + (1 * clkfreq))                          'wait 1 second for the serial object to finish printing
  
  ser.Stop                                              'Stop the object

DAT

                        org 0
logicprobe
                        mov     dira, outputmask
loop                        
                        test    mask_PROBE, ina wc
                        muxc    outa, mask_LED22
                        muxnc   outa, mask_LED23
                        jmp     #loop

outputmask              long    |< hw#pin_LED22 | |< hw#pin_LED23
mask_LED22              long    |< hw#pin_LED22
mask_LED23              long    |< hw#pin_LED23
mask_PROBE              long    |< hw#pin_0

                                              
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
                                                            