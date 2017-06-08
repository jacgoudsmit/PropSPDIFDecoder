''***************************************************************************
''* Pin assignments and other global constants
''* Copyright (C) 2017 Jac Goudsmit
''*
''* TERMS OF USE: MIT License. See bottom of file.                                                            
''***************************************************************************
''

CON

  #0

  pin_1
  pin_2
  pin_3
  pin_XORIN                     ' XORed SPDIF input (SPDIN == SPDDEL)
  
  pin_4                         
  pin_5
  pin_6
  pin_7

  pin_8
  pin_9
  pin_10
  pin_11

  pin_12
  pin_13
  pin_14
  pin_15

  pin_BINDAT                    ' Recovered binary data
  pin_PRADET                    ' Preamble Detect
  pin_BLKDET                    ' Beginning of block Detect                                                
  pin_RCHAN                     ' Right channel

  pin_20
  pin_21
  pin_22
  pin_23

  pin_24
  pin_25
  pin_LED26                     ' LED on the Parallax FLiP
  pin_LED27                     ' LED on the Parallax FLiP
  
  pin_SCL                       ' I2C clock                                      
  pin_SDA                       ' I2C data
  pin_TX                        ' Serial transmit                        
  pin_RX                        ' Serial receive

  ' Bitmasks for each of the pins
  mask_XORIN  = |< pin_XORIN
  mask_BINDAT = |< pin_BINDAT
  mask_PRADET = |< pin_PRADET
  mask_BLKDET = |< pin_BLKDET
  mask_RCHAN  = |< pin_RCHAN
  mask_LED26  = |< pin_LED26
  mask_LED27  = |< pin_LED27

  ' Use pin 26 as debug output
  pin_DEBUG = pin_LED26
  mask_DEBUG = mask_LED26  
  
PUB dummy
{{ The module won't compile with at least one public function }}

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