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
  ser:          "serout"

VAR
  long  subframe

PUB main | i, count

  cognew(@logicprobe, 0)

  'play.Start(@subframee)

  biphase.biphasedec(39, @subframe)

  ser.Start(hw#pin_TX, @subframe)

  repeat

DAT

                        org 0
logicprobe
                        mov     dira, outputmask
loop
                        test    mask_PROBE, ina wc
                        muxc    outa, mask_LED26
                        muxnc   outa, mask_LED27
                        jmp     #loop

outputmask              long    (|< hw#pin_LED26) | (|< hw#pin_LED27)
mask_LED26              long    |< hw#pin_LED26
mask_LED27              long    |< hw#pin_LED27
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