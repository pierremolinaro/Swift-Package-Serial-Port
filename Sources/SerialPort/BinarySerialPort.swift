//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 10/10/2026.
//--------------------------------------------------------------------------------------------------

import Foundation
import Observation
import Synchronization

//--------------------------------------------------------------------------------------------------

@MainActor @Observable open class BinarySerialPort : SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mReceivedData = Mutex <Data> (Data ())

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public override func handleReceivedData (_ inData : Data) {
    self.mReceivedData.withLock {
      $0 += inData
      self.reportReceivingState (inData.count)
    }
    var s = ""
    for byte in inData {
      s += " \(String (byte, radix: 16, uppercase: true))"
    }
    Swift.print ("Received[\(inData.count)]:\(s)")
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  open nonisolated override func removeAllReceivedDatas () {
    self.mReceivedData.withLock { $0.removeAll () }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------

