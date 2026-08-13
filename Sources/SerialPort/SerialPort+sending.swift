//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendString (_ inString : String) {
//    enterTracing ("send.string")
    if var data = inString.data (using: String.Encoding.utf8) {
      if let fd = self.mFileDescriptor.withLock ( { $0 } ) {
        var sent = 0
        var ok = true
        while sent < data.count, ok {
          data.removeFirst (sent)
          _ = unsafe data.withUnsafeBytes {
            let n = unsafe Darwin.write (fd, $0.baseAddress, $0.count)
            ok = n > 0
            sent += n
          }
        }
        self.reportSendingState (data.count)
        let consoleLogIsEnabled = self.mReceivedDataHandler.withLock { $0.mConsoleLogIsEnabled }
        if consoleLogIsEnabled {
          var attributeContainer = AttributeContainer ()
          attributeContainer.font = Font.custom ("Menlo", size: 12)
          attributeContainer.foregroundColor = kSendColor
          let at = AttributedString (inString, attributes: attributeContainer)
          self.appendToConsoleAttributedString (at)
        }
      }
    }else{
      Task { @MainActor in
        self.closePort (withMessage: "Send string is not UTF8")
      }
    }
//    exitTracing ("send.string")
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendData (_ inData : Data) {
//    enterTracing ("send.data")
    if let fd = self.mFileDescriptor.withLock ( { $0 } ) {
      var data = inData
      var sent = 0
      var ok = true
      while sent < data.count, ok {
        data.removeFirst (sent)
        _ = unsafe data.withUnsafeBytes {
          let n = unsafe Darwin.write (fd, $0.baseAddress, $0.count)
          ok = n > 0
          sent += n
        }
      }
      self.reportSendingState (inData.count)
      let consoleLogIsEnabled = self.mReceivedDataHandler.withLock { $0.mConsoleLogIsEnabled }
      if consoleLogIsEnabled {
        var s = ""
        for byte in inData {
          s += unsafe String (format: "<0x%02X>", byte)
        }
        s += "\n"
        var attributeContainer = AttributeContainer ()
        attributeContainer.font = Font.custom ("Menlo", size: 12)
        attributeContainer.foregroundColor = kSendColor
        attributeContainer.backgroundColor = kCtrlCharacterBackColor
        let at = AttributedString (s, attributes: attributeContainer)
        self.appendToConsoleAttributedString (at)
      }
    }
//    exitTracing ("send.data")
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
