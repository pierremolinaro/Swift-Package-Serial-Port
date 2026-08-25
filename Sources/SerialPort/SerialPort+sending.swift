//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendString (_ inString : String) {
    let data = inString.data (using: String.Encoding.utf8)!
    self.mSendThreadBuffer.withLock( { $0 += data } )
    self.mSendThreadActivationSemaphore.signal ()
    self.reportSendingState (data.count)
    let consoleLogIsEnabled = self.nonisolatedConsoleLogIsEnabled
    if consoleLogIsEnabled {
      let e = ConsoleTextBuffer.Element (string: inString, foregroundColor: kSendColor, backgroundColor: .clear)
      self.mConsoleBuffer.append (e)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendData (_ inData : Data) {
    self.mSendThreadBuffer.withLock( { $0 += inData } )
    self.mSendThreadActivationSemaphore.signal ()
    self.reportSendingState (inData.count)
    let consoleLogIsEnabled = self.nonisolatedConsoleLogIsEnabled
    if consoleLogIsEnabled {
      var s = ""
      for byte in inData {
        s += unsafe String (format: "<0x%02X>", byte)
      }
      let e = ConsoleTextBuffer.Element (string: s, foregroundColor: kSendColor, backgroundColor: kCtrlCharacterBackColor)
      self.mConsoleBuffer.append (e)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func launchSendTask (_ inFileDescriptor : Int32) {
    self.mSendThreadIsCancelled.withLock { $0 = false }
    self.mSendThread = Thread {
      while !self.mSendThreadIsCancelled.withLock ( { $0 } ) {
        self.mSendThreadActivationSemaphore.wait ()
        if self.mSendThreadBuffer.withLock ( { !$0.isEmpty } ) {
          let data = self.mSendThreadBuffer.withLock( { $0 } )
          let sent = unsafe data.withUnsafeBytes {
            let r = unsafe Darwin.write (inFileDescriptor, $0.baseAddress, $0.count)
            return r
          }
          self.mSendThreadBuffer.withLock { $0.removeFirst (sent) }
          if sent < data.count {
            Task {
              try! await Task.sleep (nanoseconds: 1_000_000) // 1 ms
              self.mSendThreadActivationSemaphore.signal ()
            }
          }
        }
      }
      print ("SEND THREAD ENDED")
    }
    self.mSendThread?.start ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
