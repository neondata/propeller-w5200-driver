'':::::::[ Socket ]:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
{{ 
''
''AUTHOR:           Mike Gebhard
''COPYRIGHT:        Parallax Inc.
''LAST MODIFIED:    10/19/2013
''VERSION:          1.0
''LICENSE:          MIT (see end of file)
''
''
''DESCRIPTION:
''                  Socket.spin is a generic high level wrapper object for the W5100/W5200.
''                  Socket.spin encapsulates a W5100/W5200 hardware socket and exposes
''                  generic socket methods. 
''
''                  ┌─────────────────┐
''                  │ Socket Object   │
''                  ├─────────────────┤
''                  │ W5200 Object    │
''                  ├─────────────────┤
''                  │ SPI Driver      │
''                  └─────────────────┘
''
''MODIFICATIONS:
'' 8/12/2012        original file ?
''10/04/2013        added minimal spindoc comments
''10/19/2013        added async test code
''                  moved SendReceive to socket
''                  Michael Sommer (MSrobots)
}}
CON
''
''=======[ Global CONstants ]=============================================================
  'MACRAW and PPPOE can only be used with socket 0
  #0, CLOSED, TCP, UDP, IPRAW, MACRAW, PPPOE

  UPD_HEADER_IP       = $00
  UDP_HEADER_PORT     = $04
  UDP_HEADER_LENGTH   = $06
  UPD_DATA            = $08

  'Increase TRANS_TIMEOUT in increments of 100*X if you are experiencing timeouts
  TRANS_TIMEOUT       = 1500  
  TIMEOUT             = TRANS_TIMEOUT * 10


  DISCONNECT_TIMEOUT  = 500  
       
''
''=======[ VARiables ]====================================================================
VAR
  byte  _sock
  byte  _protocol
  byte  _remoteIp[4]
  byte  readCount
  word  _remotePort
  word  _dataLen
  word  _trans_timeout
  word  _timeout

''
''=======[ Global DATa ]==================================================================
DAT
  _port       word  $2710
  null        long  $00

''
''=======[ Used OBJects ]=================================================================
OBJ
  wiz           : "W5100"

''
''=======[ PUBlic Spin Methods ]==========================================================
PUB Init(socketId, protocol, portNum)
{{
''DESCRIPTION:
''  Initialize a socket.
''  W5100 has 4 sockets
''  W5200 has 8 sockets
''
''PARMS:
''  socketId  - Socket ID to initialize (0-n)
''  protocol  - TCP/UPD
''  portNum   - Listener port (0-65535)  
''
''RETURNS:
''  Nothing
}}
  _sock := socketId
  _protocol := protocol

  if(_trans_timeout == null)
    _trans_timeout := TRANS_TIMEOUT
    
  if(_timeout == null)
    _timeout := TIMEOUT
  
  'Increment port numbers stating at 10,000
  if(portNum == -1)
    portNum := _port++
    
  'wiz.Init
  wiz.InitSocket(socketId, protocol, portNum)
  wiz.SetSocketIR(_sock, $FF)

  readCount := 0

PUB Destruct
  RemoteIp(0,0,0,0)
  RemotePort(0)
  _sock := -1
  _protocol := CLOSED
  readCount := 0

''-------[ Socket Commands... ]-----------------------------------------------------------
PUB Open
{{
''DESCRIPTION: Open socket
''
''PARMS:
''  
''RETURNS: Nothing
}}
  wiz.OpenSocket(_sock)

PUB Listen
{{
''DESCRIPTION: Listen on socket
''
''PARMS:
''  
''RETURNS: True if started; otherwise returns false.
}}
  if(wiz.IsInit(_sock))
    wiz.StartListener(_sock)
    return true
  return false

PUB Connect
{{
''DESCRIPTION: Connect remote socket
''
''PARMS:
''  
''RETURNS: Nothing
}}

  wiz.OpenRemoteSocket(_sock)

PUB Close
{{
''DESCRIPTION: Close socket
''
''PARMS:
''  
''RETURNS: Nothing
}}
  return wiz.CloseSocket(_sock)

PUB Receive(buffer, bytesToRead) | ptr
{{
''DESCRIPTION:
''  Read the Rx socket buffer into HUB memory.  The W5200/W5100
''  use a circlar buffer. If the buffer is 100 bytes, we're
''  currently at 91 and receice 20 bytes the first 10 bytes fill
''  addresses 91-100. The remaining 10 bytes fill addresses 0-9.
''
''  The Rx method figures ot if the buffer wraps an updates the
''  buffer pointers for the next read.
''
''PARMATERS:
''  buffer         - Pointer to HUB memory
''  bytesToRead    - Bytes to read into HUB memory
''
''RETURNS:
''  pointer to buffer or (buffer + UPD_DATA) if protocol UDP 
}}
  ptr := buffer
  wiz.Rx(_sock, buffer, bytesToRead)
  byte[buffer][bytesToRead] := NULL
  
  if(_protocol == UDP)
    'ParseHeader(buffer, bytesToRead)
    ptr += UPD_DATA

  return ptr
      
PUB Send(buffer, length)
{{
''DESCRIPTION:
''  Write HUB memory to the socket Tx buffer.  If the Tx buffer is 100
''  bytes, we're  currently pointing to 91, and we need to transmit 20 bytes
''  the first 10 byte fill addresses 91-100. The remaining 10 bytes
''  fill addresses 0-9.
''
''PARMS:
''  buffer            - Pointer to HUB memory
''  length            - Bytes to write to the socket buffer
''  
''RETURNS:            - bytes written
}}
  return SendAsync(buffer, length, true)
  
PUB SendAsync(buffer, length, waitforcompletion) | bytesToWrite
{{
''DESCRIPTION:
''  Write HUB memory to the socket Tx buffer.  If the Tx buffer is 100
''  bytes, we're  currently pointing to 91, and we need to transmit 20 bytes
''  the first 10 byte fill addresses 91-100. The remaining 10 bytes
''  fill addresses 0-9.
''
''PARMS:
''  buffer            - Pointer to HUB memory
''  length            - Bytes to write to the socket buffer
''  waitforcompletion - true to wait or false for async - still debug / testing
''  
''RETURNS:            - bytes written
}}
  'Validate max Rx length in bytes
  bytesToWrite := length
  if(bytesToWrite > wiz.SocketTxSize(_sock))
    bytesToWrite := wiz.SocketTxSize(_sock)

  wiz.Tx(_sock, buffer, bytesToWrite, waitforcompletion)
    
  return  bytesToWrite

PUB Disconnect : i
{{
''DESCRIPTION: Disconnect socket
''
''PARMS:
''  
''RETURNS: True if the socket is closed; otherwise returns false.
}}
  i := readCount := 0
  wiz.DisconnectSocket(_sock)
  repeat until wiz.IsClosed(_sock)
    if(i++ > DISCONNECT_TIMEOUT)
      wiz.CloseSocket(_sock)
      return false
  return true  

PUB SendMac(buffer, len) | bytesToWrite
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  ifnot(_protocol == UDP)
    return Send(buffer, len)
    
  'Validate max Rx length in bytes
  bytesToWrite := len
  if(len > wiz.SocketTxSize(_sock))
    bytesToWrite := wiz.SocketTxSize(_sock)

  wiz.Tx(_sock, buffer, bytesToWrite, false)

  return  bytesToWrite

PUB RemotePort(port)
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  wiz.SetRemotePort(_sock, port)

PUB DeserializeWord(buffer)
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
return wiz.DeserializeWord(buffer)

PUB SendReceive(buffer, len) | bytesToRead 
  RESULT := -1                                          'Timeout
  bytesToRead := 0
  Open                                                  'Open socket and Send Message
  Send(buffer, len)
  bytesToRead := Available
  if(bytesToRead =< 0 )                                 'Check for a timeout
    bytesToRead~
  else  
    RESULT := Receive(buffer, bytesToRead)              'Get the Rx buffer
  Disconnect

''-------[ Socket Status... ]-------------------------------------------------------------
PUB Connected
{{
''DESCRIPTION: Determine if the socket is established
''
''PARMS:
''  
''RETURNS: True if the socket is established; otherwise returns false. 
}}
  return wiz.IsEstablished(_sock)

PUB DataReady
{{
''DESCRIPTION:
''  Read socket receive size register
''  
''PARMS:
''    
''RETURNS:
''  2 bytes: Number of bytes received
}}
  return wiz.GetRxBytesToRead(_sock)

PUB Available | i, bytesToRead, tout
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  bytesToRead := i := 0

  if(readCount++ == 0)
    tout := _timeout 
  else
    tout := _trans_timeout

  repeat until NULL < bytesToRead := wiz.GetRxBytesToRead(_sock)
    'waitcnt(((clkfreq / 1_000_000 * TIMEOUT_DELAY - 3932) #> 381) + cnt) 
    if(i++ > tout)
      if(tout == TIMEOUT)
        readCount := 0
        return -1
      else
        return 0 

  return bytesToRead

PUB IsClosed
{{
''DESCRIPTION: Determine if the socket is closed
''
''PARMS:
''  
''RETURNS: True if the socket is closed; otherwise returns false. 
}}
  return wiz.IsClosed(_sock)

PUB IsCloseWait
{{
''DESCRIPTION: Determine if the socket is close wait
''
''PARMS:
''  
''RETURNS: True if the socket is close wait; otherwise returns false. 
}}
  return wiz.IsCloseWait(_sock)

PUB GetStatus
  return wiz.GetSocketStatus(_sock)

''-------[ Socket Properties... ]---------------------------------------------------------
PUB Id
  return _sock

PUB SetTimeout(value)
  _timeout := value

PUB SetTransactionTimeout(value)
  _trans_timeout := value

PUB GetUpdRemoteIP
  return @_remoteIp

PUB GetUpdDataLength
  return _dataLen

PUB GetUpdRemotePort
  return _remotePort

PUB GetPort
  return wiz.GetSocketPort(_sock)
  
PUB RemoteIp(octet3, octet2, octet1, octet0)
  wiz.RemoteIp(_sock, octet3, octet2, octet1, octet0)

PUB GetRemoteIP
  return wiz.GetRemoteIp(_sock)

PUB GetMtu
  return wiz.GetMaximumSegmentSize(_sock)

PUB GetTtl
  return wiz.GetTimeToLive(_sock)
  
PUB GetSocketIR
  return wiz.GetSocketIR(_sock)
  
PUB SetSocketIR(value)
  wiz.SetSocketIR(_sock, value)

''
''=======[ PRIvate Spin Methods... ]=========================================================
PRI ParseHeader(buffer, bytesToRead)
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  if(bytesToRead > 8)
    UpdHeaderIp(buffer)
    UdpHeaderPort(buffer)
    UdpHeaderDataLen(buffer)

PRI UpdHeaderIp(header)
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  _remoteIp[0] := byte[header][UPD_HEADER_IP]
  _remoteIp[1] := byte[header][UPD_HEADER_IP+1]
  _remoteIp[2] := byte[header][UPD_HEADER_IP+2]
  _remoteIp[3] := byte[header][UPD_HEADER_IP+3]

PRI UdpHeaderPort(header)
{{
''DESCRIPTION:
''
''PARMS:
''  
''RETURNS:
''  
}}
  _remotePort := DeserializeWord(header + UDP_HEADER_PORT)

PRI UdpHeaderDataLen(header)
  _dataLen := DeserializeWord(header + UDP_HEADER_LENGTH)

''
''=======[ Documentation ]================================================================
CON                                                 
{{{
This .spin file supports PhiPi's great Spin Code Documenter found at
http://www.phipi.com/spin2html/

You can at any time create a .htm Documentation out of the .spin source.

If you change the .spin file you can (re)create the .htm file by uploading your .spin file
to http://www.phipi.com/spin2html/ and then saving the the created .htm page. 
}}

''
''=======[ MIT License ]==================================================================
CON                                                 
{{{
 ______________________________________________________________________________________
|                            TERMS OF USE: MIT License                                 |                                                            
|______________________________________________________________________________________|
|Permission is hereby granted, free of charge, to any person obtaining a copy of this  |
|software and associated documentation files (the "Software"), to deal in the Software |
|without restriction, including without limitation the rights to use, copy, modify,    |
|merge, publish, distribute, sublicense, and/or sell copies of the Software, and to    |
|permit persons to whom the Software is furnished to do so, subject to the following   |
|conditions:                                                                           |
|                                                                                      |
|The above copyright notice and this permission notice shall be included in all copies |
|or substantial portions of the Software.                                              |
|                                                                                      |
|THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,   |
|INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A         |
|PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT    |
|HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF  |
|CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE  |
|OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                                         |
|______________________________________________________________________________________|
}} 