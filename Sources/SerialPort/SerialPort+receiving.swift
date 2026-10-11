//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

//  struct ReceivedDataHandler {
//    var mReceivedData = Data ()
//    var mReceivedStringFragment = ""
//    var mReceivedLinesBuffer = [String] ()
//  }

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
      self.handleReceivedData (data)
    }
//    exitTracing ("handle.receive.data")
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
