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
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func setupReceive (_ inFileDescriptor : Int32) {
    let readSource = DispatchSource.makeReadSource (
      fileDescriptor: inFileDescriptor,
      queue: self.mReceiveQueue
    )
    self.mReadSource = readSource
    readSource.setEventHandler (handler: self.makeEventHandler (inFileDescriptor))
    readSource.setCancelHandler { Darwin.close (inFileDescriptor) }
    readSource.resume ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Point subtil (merci Claude) : makeEventHandler s'exécute sur le main thread,
  // mais une seule fois, quand setupReceive est appelé
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func makeEventHandler (_ inFileDescriptor : Int32) -> () -> Void {
    // print ("makeEventHandler, on main thread: \(Thread.isMainThread)") // --> true
    return { [weak self] in self?.readSourceHandler (inFileDescriptor) }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Point subtil (merci Claude) : readSourceHandler ne s'exécute pas sur le main thread,
  // mais sur la « self.mReceiveQueue »

  nonisolated private func readSourceHandler (_ inFileDescriptor : Int32) {
//    print ("readSourceHandler, on main thread: \(Thread.isMainThread)") // --> false
//    dispatchPrecondition (condition: .onQueue (self.mReceiveQueue)) // Ok
  // nonisolated: on ne peut pas accéder directement aux propriétés (utiliser Mutex)
  //   enterTracing ("read.source.handler")
    var buffer = [UInt8] (repeating: 0, count: 1024)
    let bytesRead = unsafe Darwin.read (inFileDescriptor, &buffer, buffer.count)
    let data = (bytesRead > 0) ? Data (buffer.prefix (bytesRead)) : Data ()
  //--- Handle data
    if data.isEmpty {
//      Task (name: "handle.received.line") { await self.mReceiveHandler? ([]) } // Close
    }else{
      self.mReceivedDataHandler.withLock {
        $0.mReceivedData += data
        if let s = String (data: $0.mReceivedData, encoding: .utf8) {
          Task { @MainActor in self.updateUIOnReceiving (string: s) }
          $0.mReceivedData.removeAll ()
          $0.mReceivedStringFragment += s
          let unixString = $0.mReceivedStringFragment.replacingOccurrences (of: "\r\n", with: "\n")
          var lines = unixString.components (separatedBy: "\n")
          $0.mReceivedStringFragment = lines.removeLast ()
          $0.mReceivedLinesBuffer += lines
        }
      }
    }
//    exitTracing ("handle.receive.data")
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func getReceivedLine () async -> String? {
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

  public nonisolated func removeAllReceivedDatas () {
    self.mReceivedDataHandler.withLock {
      $0.mReceivedData.removeAll ()
      $0.mReceivedStringFragment = ""
      $0.mReceivedLinesBuffer.removeAll ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private func updateUIOnReceiving (string inString : String) {
    self.reportReceivingState ()
    if self.mConsoleLogIsEnabled {
      let atStringArray = inString.unicodeScalars.map { scalar -> AttributedString in
        if scalar.isASCII, scalar.value < 0x20, scalar.value != 0x0A, scalar.value != 0x0D {
          var attributeContainer = AttributeContainer ()
          attributeContainer.font = Font.custom ("Menlo", size: 12)
          attributeContainer.foregroundColor = kReceiveColor
          attributeContainer.backgroundColor = kCtrlCharacterBackColor
          return AttributedString (
            unsafe String (format: "<0x%02X>", scalar.value),
            attributes: attributeContainer
          )
        }else{
          var attributeContainer = AttributeContainer ()
          attributeContainer.font = Font.custom ("Menlo", size: 12)
          attributeContainer.foregroundColor = kReceiveColor
          return AttributedString (String (scalar), attributes: attributeContainer)
        }
      }
      for at in atStringArray {
        self.mConsoleAttributedString.append (at)
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
