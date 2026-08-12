//--------------------------------------------------------------------------------------------------

import SwiftUI
import Observation
import IOKit.serial
import IOKit.usb
import Synchronization

//--------------------------------------------------------------------------------------------------

let kReceiveColor = Color.green.mix (with: .black, by: 0.25)
let kSendColor = Color.red
let kCtrlCharacterBackColor = Color.gray.mix (with: .white, by: 0.85)

//--------------------------------------------------------------------------------------------------

@MainActor @Observable open class SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init () {
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private var mPath : String = ""
  let mFileDescriptor = Mutex <Int32?> (nil)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var isConnected : Bool = false
  var isReady : Bool { self.isConnected }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private(set) var title = ""
  private(set) var errorString = ""

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Properties for receiving data
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mReadSource : DispatchSourceRead? = nil
  let mReceiveQueue = DispatchQueue (label: "name.pcmolinaro.receive.queue", qos: .userInteractive)
  let mReceivedDataHandler = Mutex <ReceivedDataHandler> (ReceivedDataHandler ())

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private enum ReportPhase { case off, signaling, continueSignaling }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private struct SendingState {
    var mSendingReportTimer : Timer? = nil
    var mSendingStateReportPhase = ReportPhase.off
    var mWaiting = false
  }
  
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mSendingState = Mutex <SendingState> (SendingState ())
  private(set) var mSendingStateReport = false

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func reportSendingState () {
    self.mSendingState.withLock {
      switch $0.mSendingStateReportPhase {
      case .signaling :
        $0.mSendingStateReportPhase = .continueSignaling
      case .continueSignaling :
        ()
      case .off :
        Task { @MainActor in self.mSendingStateReport = true }
        $0.mSendingStateReportPhase = .signaling
        $0.mWaiting = false
        let timer = Timer (timeInterval: 0.125, repeats: true) { _ in
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
      if $0.mWaiting {
        $0.mSendingReportTimer?.invalidate ()
        $0.mSendingReportTimer = nil
        let state = $0.mSendingStateReportPhase
        $0.mSendingStateReportPhase = .off
        if state == .continueSignaling {
          Task { self.reportSendingState () }
        }
      }else{
        $0.mWaiting = true
        Task { @MainActor in self.mSendingStateReport = false }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Receiving State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private(set) var mReceivingStateReport = false
  private var mReceivingStateReportPhase = ReportPhase.off
  private var mReceivingReportTimer : Timer? = nil

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func reportReceivingState () {
    Task { @MainActor in
      switch self.mReceivingStateReportPhase {
      case .signaling :
        self.mReceivingStateReportPhase = .continueSignaling
      case .continueSignaling :
        ()
      case .off :
        self.mReceivingStateReport = true
        self.mReceivingStateReportPhase = .signaling
        self.mReceivingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                           repeats: false) { [weak self] _ in
          Task { @MainActor in
            self?.mReceivingStateReport = false
            self?.mReceivingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                                repeats: false) { [weak self] _ in
              Task { @MainActor in
                self?.mReceivingReportTimer = nil
                if let state = self?.mReceivingStateReportPhase, state == .continueSignaling {
                  self?.mReceivingStateReportPhase = .off
                  self?.reportReceivingState ()
                }else{
                  self?.mReceivingStateReportPhase = .off
                }
              }
            }
          }
        }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Open port
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func openPort (withDescription inDescription : SerialPortDescription,
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
        self.isConnected = true
        self.setupReceive (fileDescriptor)
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

  @MainActor public func closePort (withMessage inMessage : String?) {
    self.title = ""
    self.isConnected = false
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

  private struct ConsoleState {
    var mInternalConsoleAttributedString = AttributedString ()
    var mConsoleRefreshTimer : Timer? = nil
    var mConsoleAttributedString = AttributedString ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mConsoleState = Mutex <ConsoleState> (ConsoleState ())

  private var mConsoleAttributedString = AttributedString ()
  public var consoleAttributedString : AttributedString  { self.mConsoleAttributedString }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var mConsoleLogIsEnabled = false {
    didSet {
      self.mReceivedDataHandler.withLock {
        $0.mConsoleLogIsEnabled = self.mConsoleLogIsEnabled
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func appendToConsoleAttributedString (_ inAT : AttributedString) {
    self.mConsoleState.withLock { state in
      state.mInternalConsoleAttributedString.append (inAT)
      if state.mConsoleRefreshTimer == nil {
        let timer = Timer (timeInterval: 0.5, repeats: false) { _ in
          self.consoleTimerDidFire ()
        }
        state.mConsoleRefreshTimer = timer
        RunLoop.main.add (timer, forMode: .common)
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func consoleTimerDidFire () {
    self.mConsoleState.withLock { state in
      state.mConsoleRefreshTimer?.invalidate ()
      state.mConsoleRefreshTimer = nil
      let newValue = state.mInternalConsoleAttributedString
      state.mConsoleAttributedString = newValue
      Task { @MainActor in self.mConsoleAttributedString = newValue }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor public func clearConsole () {
    self.mConsoleState.withLock {
      $0.mConsoleRefreshTimer = nil
      $0.mInternalConsoleAttributedString = AttributedString ()
      $0.mConsoleAttributedString = AttributedString ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
