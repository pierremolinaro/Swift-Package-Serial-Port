//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendString (_ inString : String) {
    let data = inString.data (using: String.Encoding.utf8)!
    self.mSendTaskBuffer.withLock( { $0 += data } )
    self.mSendSemaphore.signal ()
    self.reportSendingState (data.count)
    let consoleLogIsEnabled = self.nonisolatedConsoleLogIsEnabled
    if consoleLogIsEnabled {
      let e = ConsoleTextBuffer.Element (string: inString, foregroundColor: kSendColor, backgroundColor: .clear)
      self.mConsoleBuffer.append (e)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func sendData (_ inData : Data) {
    self.mSendTaskBuffer.withLock( { $0 += inData } )
    self.mSendSemaphore.signal ()
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
    self.mSendThread = Thread {
 //     print ("START")
      while !self.mSendTaskIsCancelled.withLock ( { $0 } ) {
        self.mSendSemaphore.wait ()
//        print ("PASS")
        if !self.mSendTaskBuffer.withLock( { $0.isEmpty } ) {
          let data = self.mSendTaskBuffer.withLock( { $0 } )
          let sent = unsafe data.withUnsafeBytes {
            return unsafe Darwin.write (inFileDescriptor, $0.baseAddress, $0.count)
          }
          self.mSendTaskBuffer.withLock { $0.removeFirst (sent) }
          if sent < data.count {
            Task {
              try! await Task.sleep (nanoseconds: 1_000_000) // 1 ms
              self.mSendSemaphore.signal ()
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
