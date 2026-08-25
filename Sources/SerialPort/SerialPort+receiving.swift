//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  struct ReceivedDataHandler {
    var mReceivedData = Data ()
    var mReceivedStringFragment = ""
    var mReceivedLinesBuffer = [String] ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Receive
  // Point subtil (merci Claude) : il faut que les handlers s'exécutent sur la « mReceiveQueue »
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func setupReceive (_ inFileDescriptor : Int32) {
    self.mReceiveQueue.async {
      let readSource = DispatchSource.makeReadSource (
        fileDescriptor: inFileDescriptor,
        queue: self.mReceiveQueue
      )
      Task { @MainActor in self.mReadSource = readSource }
      readSource.setEventHandler  { self.readSourceHandler (inFileDescriptor) }
      readSource.setCancelHandler { self.cancelHandler (inFileDescriptor) }
      readSource.resume ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func cancelHandler (_ inFileDescriptor : Int32) {
    _ = Darwin.tcflush (inFileDescriptor, TCIFLUSH)
    _ = Darwin.close (inFileDescriptor)
    Task { @MainActor in self.mReadSource = nil }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func readSourceHandler (_ inFileDescriptor : Int32) {
//    print ("readSourceHandler, on main thread: \(Thread.isMainThread)") // --> false
//    dispatchPrecondition (condition: .onQueue (self.mReceiveQueue)) // Ok
  // nonisolated: on ne peut pas accéder directement aux propriétés (utiliser Mutex)
  //   enterTracing ("read.source.handler")
    var buffer = [UInt8] (repeating: 0, count: 1024)
    let bytesRead = unsafe Darwin.read (inFileDescriptor, &buffer, buffer.count)
    let data = (bytesRead > 0) ? Data (buffer.prefix (bytesRead)) : Data ()
  //--- Handle data
    if data.isEmpty { // IMPORTANT : ceci permet de détecter une fermeture intempestive
      Task { @MainActor in self.closePort (withMessage: "Disconnected") }
    }else{
      self.mReceivedDataHandler.withLock {
        $0.mReceivedData += data
        if let s = String (data: $0.mReceivedData, encoding: .utf8) {
          self.reportReceivingState ($0.mReceivedData.count)
          if self.nonisolatedConsoleLogIsEnabled {
            self.updateUIOnReceiving (string: s)
          }
          $0.mReceivedData.removeAll ()
          $0.mReceivedStringFragment += s
          let unixString = $0.mReceivedStringFragment.replacingOccurrences (of: "\r\n", with: "\n")
          var lines = unixString.components (separatedBy: "\n")
          $0.mReceivedStringFragment = lines.removeLast ()
          self.handleReceivedLines (lines, &$0.mReceivedLinesBuffer)
        }
      }
    }
//    exitTracing ("handle.receive.data")
  }

 // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func updateUIOnReceiving (string inString : String) {
    var elementArray = [ConsoleTextBuffer.Element] ()
    var currentString = ""
    for scalar in inString.unicodeScalars {
      if scalar.isASCII, scalar.value < 0x20, scalar.value != 0x0A, scalar.value != 0x0D {
        if !currentString.isEmpty {
          let e = ConsoleTextBuffer.Element (string: currentString, foregroundColor: kReceiveColor, backgroundColor: .clear)
          elementArray.append (e)
          currentString.removeAll (keepingCapacity: true)
        }
        let s = unsafe String (format: "<0x%02X>", scalar.value)
        let e = ConsoleTextBuffer.Element (string: s, foregroundColor: kReceiveColor, backgroundColor: kCtrlCharacterBackColor)
        elementArray.append (e)
      }else{
        currentString += String (scalar)
      }
    }
    if !currentString.isEmpty {
      let e = ConsoleTextBuffer.Element (string: currentString, foregroundColor: kReceiveColor, backgroundColor: .clear)
      elementArray.append (e)
    }
    self.mConsoleBuffer.append (elementArray)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public func getReceivedLine () async -> String? {
    let start = ContinuousClock.now
    while true {
      if let line = self.extractFirstReceivedLine () {
        return line
      }else if (ContinuousClock.Instant.now - start) > .seconds (1) {
        return nil
      }
      await Task.yield ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func extractFirstReceivedLine () -> String? {
    self.mReceivedDataHandler.withLock {
      if $0.mReceivedLinesBuffer.isEmpty {
        return nil
      }else{
        return $0.mReceivedLinesBuffer.removeFirst ()
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
