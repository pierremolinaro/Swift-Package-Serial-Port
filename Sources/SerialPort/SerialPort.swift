//--------------------------------------------------------------------------------------------------

import SwiftUI
import Observation
import IOKit.serial
import IOKit.usb
import Synchronization

//--------------------------------------------------------------------------------------------------

let kSendColor = NSColor.green.blended (withFraction: 0.25, of: .black)! //.mix (with: .black, by: 0.25)
let kReceiveColor = NSColor.red
let kCtrlCharacterBackColor = NSColor.gray.blended (withFraction: 0.85, of: .white)! // .mix (with: .white, by: 0.85)

//--------------------------------------------------------------------------------------------------

@MainActor @Observable open class SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor public init () {
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private var mPath : String = ""
  let mFileDescriptor = Mutex <Int32?> (nil)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private var mIsSerialPortConnected : Bool = false
  @MainActor public var isSerialPortConnected : Bool  { self.mIsSerialPortConnected }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private(set) var title = ""
  @MainActor private(set) var errorString = ""

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Disconnection
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor open var disconnectIsEnabled : Bool { true }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Properties for receiving data
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mReadSource : DispatchSourceRead? = nil
  let mReceiveQueue = DispatchQueue (label: "name.pcmolinaro.receive.queue", qos: .userInteractive)
  let mReceivedDataHandler = Mutex <ReceivedDataHandler> (ReceivedDataHandler ())

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private struct SendingState {
    var mSendingReportTimer : Timer? = nil
    var mSendingByteCount = 0
  }
  
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mSendingState = Mutex <SendingState> (SendingState ())
  private var mSendingStateString = ""

  public var sendingStateView : some View {
    Text (self.mSendingStateString).foregroundStyle (Color (kSendColor))
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func reportSendingState (_ inByteCount : Int) {
    self.mSendingState.withLock {
      $0.mSendingByteCount += inByteCount
      if $0.mSendingReportTimer == nil {
        let timer = Timer (timeInterval: 1.0, repeats: true) { _ in
          self.sendingReportTimerDidFire ()
        }
        $0.mSendingReportTimer = timer
        RunLoop.main.add (timer, forMode: .common)
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func sendingReportTimerDidFire () {
    self.mSendingState.withLock {
      if $0.mSendingByteCount == 0 {
        Task { @MainActor in self.mSendingStateString = "" }
        $0.mSendingReportTimer?.invalidate ()
        $0.mSendingReportTimer = nil
      }else{
        let str = "Tx: \($0.mSendingByteCount) bytes/s"
        Task { @MainActor in self.mSendingStateString = str }
        $0.mSendingByteCount = 0
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Receiving State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private struct ReceivingState {
    var mReceivingReportTimer : Timer? = nil
    var mReceivedByteCount = 0
  }
  
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mReceivingState = Mutex <ReceivingState> (ReceivingState ())
  private var mReceivingStateString = ""

  public var receivingStateView : some View {
    Text (self.mReceivingStateString).foregroundStyle (Color (kReceiveColor))
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func reportReceivingState (_ inByteCount : Int) {
    self.mReceivingState.withLock {
      $0.mReceivedByteCount += inByteCount
      if $0.mReceivingReportTimer == nil {
        let timer = Timer (timeInterval: 1.0, repeats: true) { _ in
          self.receivingReportTimerDidFire ()
        }
        $0.mReceivingReportTimer = timer
        RunLoop.main.add (timer, forMode: .common)
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func receivingReportTimerDidFire () {
    self.mReceivingState.withLock {
      if $0.mReceivedByteCount == 0 {
        Task { @MainActor in self.mReceivingStateString = "" }
        $0.mReceivingReportTimer?.invalidate ()
        $0.mReceivingReportTimer = nil
      }else{
        let str = "Rx: \($0.mReceivedByteCount) bytes/s"
        Task { @MainActor in self.mReceivingStateString = str }
        $0.mReceivedByteCount = 0
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  open nonisolated func removeAllReceivedDatas () {
    self.mReceivedDataHandler.withLock {
      $0.mReceivedData.removeAll ()
      $0.mReceivedStringFragment = ""
      $0.mReceivedLinesBuffer.removeAll ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Open port
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor open func openPort (withDescription inDescription : SerialPortDescription,
                                 baudRate inBaudRate : BaudRate,
                                 parity inParity : Parity,
                                 stopBits inStopBits : StopBits) {
    self.mPath = inDescription.path
    self.title = inDescription.title
    self.errorString = ""
    if self.mPath.isEmpty {
      self.title = ""
      self.errorString = "Empty file path"
    }else{
      let flags : Int32 = O_RDWR | O_NOCTTY
      // O_RDWR: Read / write access
      // O_NOCTTY: If path refers to a terminal device—see tty(4)—it will not
      //     become the process's controlling terminal even if the
      //     process does not have one.
      let fileDescriptor = unsafe open (self.mPath, flags)
      if fileDescriptor > 0 {
        self.mFileDescriptor.withLock { $0 = fileDescriptor }
        Self.setSettings (
          baudRate: inBaudRate,
          parity: inParity,
          stopBits: inStopBits,
          fileDescriptor: fileDescriptor
        )
        self.setupReceive (fileDescriptor)
        self.launchSendTask (fileDescriptor)
        self.mIsSerialPortConnected = true
      }else{
        self.mFileDescriptor.withLock { $0 = nil }
        self.title = ""
        self.errorString = "Failed to open port"
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private static func setSettings (baudRate inBaudRate : BaudRate,
                                              parity inParity : Parity = .none,
                                              stopBits inStopBits : StopBits = .one,
                                              dataBitsSize: DataBitsSize = .bits8,
                                              fileDescriptor inFileDescriptor : Int32,
                                              useHardwareFlowControl: Bool = false,
                                              useSoftwareFlowControl: Bool = false,
                                              processOutput: Bool = false) {
  //--- Set up the control structure
    var settings = termios ()
  //--- Get options structure for the port
    unsafe tcgetattr (inFileDescriptor, &settings)
  //--- Set baud rates
    unsafe cfsetispeed (&settings, inBaudRate.speedValue)
    unsafe cfsetospeed (&settings, inBaudRate.speedValue)
  //--- Enable parity (even/odd) if needed
    settings.c_cflag &= ~Parity.odd.parityValue
    settings.c_cflag |= inParity.parityValue
  //--- Set stop bit flag
    inStopBits.enterSetting (&settings)
  //--- Set data bits size flag
    settings.c_cflag &= ~tcflag_t(CSIZE)
    settings.c_cflag |= dataBitsSize.flagValue
  //--- Disable input mapping of CR to NL, mapping of NL into CR, and ignoring CR
    settings.c_iflag &= ~tcflag_t (ICRNL | INLCR | IGNCR)
  //-- Set hardware flow control flag
    if useHardwareFlowControl {
      settings.c_cflag |= tcflag_t (CRTS_IFLOW)
      settings.c_cflag |= tcflag_t (CCTS_OFLOW)
    }else{
      settings.c_cflag &= ~tcflag_t (CRTS_IFLOW)
      settings.c_cflag &= ~tcflag_t (CCTS_OFLOW)
    }
  //-- Set software flow control flags
    let softwareFlowControlFlags = tcflag_t (IXON | IXOFF | IXANY)
    if useSoftwareFlowControl {
      settings.c_iflag |= softwareFlowControlFlags
    }else{
      settings.c_iflag &= ~softwareFlowControlFlags
    }
  //--- Turn on the receiver of the serial port, and ignore modem control lines
    settings.c_cflag |= tcflag_t (CREAD | CLOCAL)
  //--- Turn off canonical mode
    settings.c_lflag &= ~tcflag_t (ICANON | ECHO | ECHOE | ISIG)
  //--- Set output processing flag
    if processOutput {
      settings.c_oflag |= tcflag_t (OPOST)
    }else{
      settings.c_oflag &= ~tcflag_t (OPOST)
    }
  //--- Special characters
  // We do this as c_cc is a C-fixed array which is imported as a tuple in Swift.
  // To avoid hardcoding the VMIN or VTIME value to access the tuple value, we use the typealias instead
    typealias specialCharactersTuple = (VEOF: cc_t, VEOL: cc_t, VEOL2: cc_t, VERASE: cc_t, VWERASE: cc_t, VKILL: cc_t, VREPRINT: cc_t, spare1: cc_t, VINTR: cc_t, VQUIT: cc_t, VSUSP: cc_t, VDSUSP: cc_t, VSTART: cc_t, VSTOP: cc_t, VLNEXT: cc_t, VDISCARD: cc_t, VMIN: cc_t, VTIME: cc_t, VSTATUS: cc_t, spare: cc_t)
    var specialCharacters : specialCharactersTuple = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) // NCCS = 20
    specialCharacters.VMIN = 0 // minimumBytesToRead == 0
    specialCharacters.VTIME = cc_t (20) // Unit: 0,1s
    settings.c_cc = specialCharacters
  //--- Commit settings
    unsafe tcsetattr (inFileDescriptor, TCSANOW, &settings)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Close port
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor open func closePort (withMessage inMessage : String?) {
    self.title = ""
    self.mSendTaskIsCancelled.withLock { $0 = true }
    self.mSendSemaphore.signal ()
    self.mSendThread = nil
    self.mIsSerialPortConnected = false
    if self.mFileDescriptor.withLock ({ $0 }) != nil {
      self.mFileDescriptor.withLock { $0 = nil }
      if let s = inMessage {
        self.errorString = s
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Console
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public let mConsoleBuffer = ConsoleTextBuffer (flushInterval: 0.5)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public func appendToConsole (string : String,
                                           foregroundColor : NSColor,
                                           backgroundColor : NSColor) {
    let consoleLogIsEnabled = self.nonisolatedConsoleLogIsEnabled
      if consoleLogIsEnabled {
      let e = ConsoleTextBuffer.Element (
        string: string,
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor
      )
      self.mConsoleBuffer.append (e)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor public func clearConsole () {
    self.mConsoleBuffer.clear()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Enable 
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @ObservationIgnored private let mNonIsolatedConsoleLogIsEnabled = Mutex <Bool> (false)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor public var mainActorConsoleLogIsEnabled : Bool {
    set {
      self.nonisolatedSetConsoleLogIsEnabled (newValue: newValue)
    }
    get {
      self.access (keyPath: \.mainActorConsoleLogIsEnabled)
      return self.mNonIsolatedConsoleLogIsEnabled.withLock { $0 }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public var nonisolatedConsoleLogIsEnabled : Bool {
    self.mNonIsolatedConsoleLogIsEnabled.withLock { $0 }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func nonisolatedSetConsoleLogIsEnabled (newValue inNewValue : Bool) {
  //-- Écriture immédiate, thread-safe, visible tout de suite
  //     par tout code qui lit mEngraverStateMutex directement
    let modified = self.mNonIsolatedConsoleLogIsEnabled.withLock {
      let condition = $0 != inNewValue
      if condition {
        $0 = inNewValue
      }
      return condition
    }
  //--- Notification Observation, différée sur le MainActor
    if modified {
      Task { @MainActor in
        self.withMutation (keyPath: \.mainActorConsoleLogIsEnabled) { }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Override this function for intercepting received lines
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated open func handleReceivedLines (_ inLines : [String], _ ioBuffer : inout [String]) {
    ioBuffer += inLines
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Send Task
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mSendThread : Thread? = nil
  let mSendTaskIsCancelled = Mutex <Bool> (false)
  let mSendTaskBuffer = Mutex <Data> (Data ())
  nonisolated let mSendSemaphore = DispatchSemaphore (value: 0)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
