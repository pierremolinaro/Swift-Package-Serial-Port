//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 10/10/2026.
//--------------------------------------------------------------------------------------------------

import Foundation
import Observation
import Synchronization

//--------------------------------------------------------------------------------------------------

@MainActor @Observable open class TextualSerialPort : SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Override this function for intercepting received lines
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated open func handleReceivedLines (_ inLines : [String], _ ioBuffer : inout [String]) {
    ioBuffer += inLines
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  struct ReceivedDataHandler {
    var mReceivedData = Data ()
    var mReceivedStringFragment = ""
    var mReceivedLinesBuffer = [String] ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  let mReceivedDataHandler = Mutex <ReceivedDataHandler> (ReceivedDataHandler ())

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  open nonisolated override func removeAllReceivedDatas () {
    self.mReceivedDataHandler.withLock {
      $0.mReceivedData.removeAll ()
      $0.mReceivedStringFragment = ""
      $0.mReceivedLinesBuffer.removeAll ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public final override func handleReceivedData (_ inData : Data) {
    var s = ""
    for byte in inData {
      s += " \(String (byte, radix: 16, uppercase: true))"
    }
    Swift.print ("Received[\(inData.count)]:\(s)")
    self.mReceivedDataHandler.withLock {
      $0.mReceivedData += inData
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

 // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated internal func updateUIOnReceiving (string inString : String) {
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

